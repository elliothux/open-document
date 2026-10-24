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
/// Reads a section's effective watermarks and document-wide picture resources.
pub fn Session::watermark(
  self : Session,
  revision : Int,
  sectionIndex : Int,
) -> Json raise @failure.Failure {
  self.check_revision_value(revision)
  guard sectionIndex >= 0 && sectionIndex < 1024 else {
    @failure.reject("invalid-operation", "Invalid page section")
  }
  try {
    let tree = WordTree::new(self.display_document())
    guard tree.page_sections().get(sectionIndex) is Some(_) else {
      @failure.reject("invalid-operation", "Unknown page section")
    }
    let headers = self.watermark_headers(tree)
    let sources = self.watermark_sources(headers)
    let values = ["default", "first", "even"].map(variant => {
      headers[sectionIndex]
      .get(variant)
      .bind(part => sources[part])
      .map(mark => mark.value)
    })
    let images : Array[String] = []
    for source in sources.values() {
      if source is Some({ value: Picture(Resource(key), _, _, _), .. }) &&
        !images.contains(key) {
        images.push(key)
      }
    }
    images.sort()
    let reason = try {
      ignore(self.editable_page_section(tree, target=Some(sectionIndex)))
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    {
      "section": sectionIndex,
      "value": if reason.is_empty() {
        values[0].map(value => value.json()).unwrap_or(Json::null())
      } else {
        Json::null()
      },
      "revision": revision,
      "mixed": reason.is_empty() && values.any(value => value != values[0]),
      "reason": reason,
      "images": images,
    }
  } catch {
    @failure.Failure(code="invalid-operation", ..) as error => raise error
    @failure.Failure(message~, ..) =>
      {
        "revision": revision,
        "section": sectionIndex,
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
  sectionIndex : Int,
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
  let section = self.editable_page_section(tree, target=Some(sectionIndex))
  let targets = ["default", "first", "even"].map(variant => {
    let (_, reference, part) = self.running_target(
      tree, sectionIndex, "header", variant,
    )
    let old = part.bind(part => {
      WordTree::new(self.part_xml(part)).header_watermark()
    })
    (variant, part, old, reference)
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
  let copies : Map[String, String] = Map([])
  let (initial, edits, section) = page_section(original, tree, section)
  let mut candidate = initial
  for (variant, existing, old, reference) in targets {
    if old.map(mark => self.watermark_value(existing.unwrap(), mark.value)) ==
      value {
      continue
    }
    let view = { ..self, parts, media, }
    let part = existing
      .map(existing => {
        let shared_elsewhere = tree.order.any(id => {
          let node = tree.nodes[id]
          node.uri == word_uri &&
          node.name == "headerReference" &&
          node.parent != section &&
          self.running_part(tree, id, "header") == existing
        })
        if reference is None || shared_elsewhere {
          if copies.get(existing) is Some(copy) {
            copy
          } else {
            let copy = view.copy_running_part(
              "header",
              Some(existing),
              parts,
              part_edits,
              created,
            )
            copies[existing] = copy
            copy
          }
        } else {
          existing
        }
      })
      .unwrap_or_else(() => {
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
            .filter(_ => existing == Some(part))
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
        let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
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
        if created.contains(part) {
          created[part] = document
        } else {
          part_edits.get_or_init(part, () => []).push(edit)
        }
      }
    }
    if existing != Some(part) || reference is None {
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
      let current = WordTree::new(candidate)
      let change = if reference is Some(id) {
        let node = current.nodes[id]
        let attribute = node.attributes
          .iter()
          .find_first(a => a.uri == running_rel_uri && a.name == "id")
          .unwrap()
        @xml.SourceChange::{
          node: id,
          offset: attribute.start - node.start,
          length: attribute.end - attribute.start,
          xml: property_attribute(relation.id),
        }
      } else {
        current.running_reference_change(
          section,
          "header",
          variant,
          relation.id,
        )
      }
      let (updated, edit) = candidate.edit_source([change])
      candidate = updated
      edits.push(edit)
    }
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
