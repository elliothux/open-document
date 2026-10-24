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
/// Reads the single-section watermark; mixed header variants are reported explicitly.
pub fn Session::watermark(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  try {
    let tree = WordTree::new(self.document())
    ignore(self.editable_page_section(tree))
    let values = ["default", "first", "even"].map(variant => {
      let (_, _, part) = self.running_target(tree, 0, "header", variant)
      part.bind(part => {
        WordTree::new(self.part_xml(part))
        .header_watermark()
        .map(mark => self.watermark_value(part, mark.value))
      })
    })
    let images : Array[String] = []
    for value in values {
      if value is Some(Picture(Resource(key), _, _, _)) && !images.contains(key) {
        images.push(key)
      }
    }
    {
      "value": values[0].map(value => value.json()).unwrap_or(Json::null()),
      "revision": revision,
      "mixed": values.any(value => value != values[0]),
      "reason": "",
      "images": images,
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "revision": revision,
        "value": Json::null(),
        "mixed": false,
        "reason": message,
        "images": [],
      }
  }
}

///|
/// Sets or removes a native text or picture watermark across all three stored header variants.
pub fn Session::set_watermark(
  self : Session,
  revision : Int,
  value : Watermark?,
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
    let (_, _, part) = self.running_target(tree, 0, "header", variant)
    let old = part.bind(part => {
      WordTree::new(self.part_xml(part)).header_watermark()
    })
    (variant, part, old)
  })
  let mut value = match value {
    Some(Picture(Resource(key), width, height, opacity)) => {
      let link = self.image_relationship(key)
      guard !link.external else {
        @failure.reject(
          "protected-content", "Watermark images must be internal",
        )
      }
      ignore(@image.type_info(self.image_bytes(key)))
      Some(
        Picture(Resource("watermark:" + link.target), width, height, opacity),
      )
    }
    Some(Picture(Data(bytes), width, height, opacity)) => {
      guard bytes.length() <= history_byte_limit else {
        @failure.reject(
          "limit-exceeded", "Watermark image exceeds history budget",
        )
      }
      ignore(@image.type_info(bytes))
      let mut matching : String? = None
      for target in targets {
        if target.2 is Some(mark) &&
          self.watermark_value(target.1.unwrap(), mark.value)
          is Picture(Resource(key), _, _, _) &&
          self.image_bytes(key) == bytes {
          matching = Some(key)
          break
        }
      }
      Some(
        Picture(
          matching
          .map(key => WatermarkImage::Resource(key))
          .unwrap_or(Data(bytes)),
          width,
          height,
          opacity,
        ),
      )
    }
    _ => value
  }
  if targets.all(target => {
      target.2.map(mark => self.watermark_value(target.1.unwrap(), mark.value)) ==
      value
    }) {
    return self.edit_state()
  }
  let (width, height) = if value is Some(Text(value)) {
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
  } else if value is Some(Picture(_, width, height, _)) {
    (width, height)
  } else {
    (0.0, 0.0)
  }
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let media = self.media.copy()
  let created_media : Map[String, Bytes] = Map([])
  let changed : Set[String] = Set([])
  let references = StringBuilder()
  for (variant, existing, old) in targets {
    if existing is None && value is None {
      continue
    }
    let view = { ..self, parts, media, }
    let part = existing.unwrap_or_else(() => {
      view.new_word_part("header", parts, part_edits, created)
    })
    if !changed.contains(part) {
      changed.add(part)
      if value is Some(Picture(Data(bytes), width, height, opacity)) {
        let kind = @image.type_info(bytes)
        let resource = view.prepare_picture_resource(
          view.next_drawing_identity(),
          bytes,
          (kind.0, kind.1),
          owner=part,
        )
        for name, document in resource.parts {
          parts[name] = document
        }
        for name, data in resource.media {
          media[name] = data
        }
        for name, edits in resource.edits {
          part_edits.get_or_init(name, () => []).append(edits)
        }
        for name, document in resource.created {
          created[name] = document
        }
        created_media[resource.path] = resource.data
        value = Some(
          Picture(
            Resource("watermark:" + resource.path),
            width,
            height,
            opacity,
          ),
        )
      }
      let markup = value
        .map(value => {
          let identity = old
            .map(mark => mark.identity)
            .unwrap_or_else(() => view.next_drawing_identity().to_string())
          match value {
            Text(text) => watermark_markup(text, identity, width, height)
            Picture(Resource(key), width, height, opacity) =>
              picture_watermark_markup(
                identity,
                view.watermark_image_link(
                  part,
                  view.image_relationship(key).target,
                  parts,
                  part_edits,
                  created,
                ),
                width,
                height,
                opacity,
              )
            _ =>
              @failure.reject(
                "invalid-operation", "Watermark image was not prepared",
              )
          }
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
      let view = { ..self, parts, media, }
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
    media~,
    created_media~,
  )
}
