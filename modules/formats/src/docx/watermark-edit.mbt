///|
fn WordTree::header_watermark(
  self : WordTree,
) -> WatermarkSource? raise @failure.Failure {
  guard self.nodes[0].uri == word_uri && self.nodes[0].name == "hdr" else {
    @failure.reject("invalid-docx", "Invalid watermark header root")
  }
  let blocks = self.children[0].filter(id => self.watermark_block(id))
  guard blocks.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate header watermarks")
  }
  blocks.get(0).map(id => self.watermark_source(id))
}

///|
/// Reads the single-section text watermark; mixed header variants are reported explicitly.
pub fn Session::text_watermark(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  try {
    let tree = WordTree::new(self.document())
    let values = ["default", "first", "even"].map(variant => {
      let (_, _, part) = self.running_target(tree, "header", variant)
      part
      .bind(part => WordTree::new(self.part_xml(part)).header_watermark())
      .map(mark => mark.value)
    })
    {
      "value": values[0].map(value => Json(value)).unwrap_or(Json::null()),
      "revision": revision,
      "mixed": values.any(value => value != values[0]),
      "reason": "",
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "revision": revision,
        "value": Json::null(),
        "mixed": false,
        "reason": message,
      }
  }
}

///|
/// Sets or removes a native text watermark across all three stored header variants.
pub fn Session::set_text_watermark(
  self : Session,
  revision : Int,
  value : TextWatermark?,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let value = value.map(value => value.normalized())
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree)
  let targets = ["default", "first", "even"].map(variant => {
    let (_, _, part) = self.running_target(tree, "header", variant)
    let old = part.bind(part => {
      WordTree::new(self.part_xml(part)).header_watermark()
    })
    (variant, part, old)
  })
  if targets.all(target => target.2.map(mark => mark.value) == value) {
    return self.edit_state()
  }
  let (width, height) = if value is Some(value) {
    let block = probe.text_block(
      value.text,
      value.style(),
      profile,
      14400,
      false,
    )
    guard block.widths is [width] &&
      width > 0 &&
      width <= 14400 &&
      block.height > 0 &&
      block.height <= 14400 else {
      @failure.reject("limit-exceeded", "Watermark text exceeds drawing bounds")
    }
    ((width * 12700).ceil() / 12700, (block.height * 12700).ceil() / 12700)
  } else {
    (0.0, 0.0)
  }
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let changed : Set[String] = Set([])
  let references = StringBuilder()
  for (variant, existing, old) in targets {
    if existing is None && value is None {
      continue
    }
    let view = { ..self, parts, }
    let part = existing.unwrap_or_else(() => {
      view.new_word_part("header", parts, part_edits, created)
    })
    if !changed.contains(part) {
      changed.add(part)
      let markup = value
        .map(value => {
          watermark_markup(
            value,
            old
            .map(mark => mark.identity)
            .unwrap_or_else(() => view.next_drawing_identity().to_string()),
            width,
            height,
          )
        })
        .unwrap_or("")
      if existing is None {
        let document = @xml.Document::parse(
          @utf8.encode("<w:hdr xmlns:w='\{word_uri}'>\{markup}</w:hdr>"),
          part,
          self.opc.budget.xml_depth,
          self.opc.budget.entry_bytes,
        )
        parts[part] = document
        created[part] = document
      } else {
        let document = self.part_xml(part)
        let story = WordTree::new(document)
        let (document, edit) = if old is Some(old) {
          let root = story.nodes[0]
          let node = story.nodes[old.node]
          document.edit_source([
            {
              node: 0,
              offset: node.start - root.start,
              length: node.end - node.start,
              xml: markup,
            },
          ])
        } else {
          append_part_xml(document, markup)
        }
        parts[part] = document
        part_edits.get_or_init(part, () => []).push(edit)
      }
    }
    if existing is None {
      let view = { ..self, parts, }
      let relation = view
        .relationships()
        .iter()
        .find_first(rel => {
          rel.owner == self.main &&
          rel.target == part &&
          rel.kind == running_rel_uri + "/header"
        })
        .unwrap()
      references.write_string(
        "<w:headerReference xmlns:w='\{word_uri}' xmlns:r='\{running_rel_uri}' w:type='\{variant}' r:id='\{property_attribute(relation.id)}'/>",
      )
    }
  }
  let (initial, edits, section) = page_section(original, tree, section)
  let candidate = if references.to_string().is_empty() {
    initial
  } else {
    let tree = WordTree::new(initial)
    let node = tree.nodes[section]
    let previous = tree.children[section]
      .filter(id => tree.nodes[id].name == "headerReference")
      .last()
    let change : @xml.SourceChange = if node.empty {
      {
        node: section,
        offset: node.opening_end - node.start - 2,
        length: 2,
        xml: ">\{references}</\{node.qualified}>",
      }
    } else {
      {
        node: section,
        offset: previous
        .map(id => tree.nodes[id].end)
        .unwrap_or(node.opening_end) -
        node.start,
        length: 0,
        xml: references.to_string(),
      }
    }
    let (document, edit) = initial.edit_source([change])
    edits.push(edit)
    document
  }
  self.commit_running(
    candidate,
    edits,
    parts,
    part_edits,
    created,
    probe~,
    profile~,
    images~,
  )
}
