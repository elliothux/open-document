///|
pub(all) enum ListEdit {
  Create(String)
  Apply(Int, Int)
  Remove
  Restart(Int)
  Level(Bool)
}

///|
/// Changes list membership and numbering metadata as one bounded history entry.
pub fn Session::edit_list(
  self : Session,
  revision : Int,
  selection : Selection,
  change : ListEdit,
) -> Json raise @failure.Failure {
  self.edit_list_with_indent(
    revision,
    selection,
    change,
    if change is Level(_) {
      ParagraphFormat::new(left=Clear, first=Clear)
    } else {
      ParagraphFormat::new()
    },
  )
}

///|
fn Session::edit_list_with_indent(
  self : Session,
  revision : Int,
  selection : Selection,
  change : ListEdit,
  indent : ParagraphFormat,
  prepared~ : PreparedEdit? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let properties = indent.properties()
  let document = prepared
    .map(p => p.document)
    .unwrap_or_else(() => self.document())
  let tree = WordTree::new(document)
  let range = self.formatting_range(
    document,
    selection,
    whole_cells=true,
    notes=true,
  )
  let styles = self.styles([])
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let references : Map[Int, (Int, Int)] = Map([])
  let plain : Map[Int, Map[String, Map[String, String?]?]] = Map([])
  match change {
    Level(increase) => {
      guard range.paragraphs.any(p => {
        styles.numbering_reference(tree, p) is Some(_)
      }) else {
        @failure.reject("invalid-operation", "Select numbered paragraphs first")
      }
      let context = self.numbering_context()
      for p in range.paragraphs {
        guard styles.numbering_reference(tree, p) is Some((instance, level)) else {
          let left = self.formatting_paragraphs(document, [p])[0].left
          // Choose adjacent 12.5 mm grid points after rounding them to twips.
          let step = 12.5 / 25.4 * 1440
          let index = if increase {
            ((left * 20 + 0.5) / step).floor() + 1
          } else {
            (((left * 20 - 0.5) / step).ceil() - 1).max(0)
          }
          plain[p] = ParagraphFormat::new(left=Set((index * step).round() / 20)).properties()
          continue
        }
        let next = (level + (if increase { 1 } else { -1 })).clamp(min=0, max=8)
        if next != level {
          ignore(context.level(instance, next))
          references[p] = (instance, next)
        }
      }
    }
    Remove =>
      for p in range.paragraphs {
        if styles.numbering_reference(tree, p) is Some(_) {
          references[p] = (0, 0)
        }
      }
    Apply(instance, level) => {
      guard instance > 0 && instance <= 2147483646 && level >= 0 && level <= 8 else {
        @failure.reject("invalid-operation", "Invalid list reference")
      }
      ignore(self.numbering_context().level(instance, level))
      for p in range.paragraphs {
        if styles.numbering_reference(tree, p) != Some((instance, level)) {
          references[p] = (instance, level)
        }
      }
    }
    Create(format) => {
      guard [
        "decimal", "decimalZero", "decimalFullWidth", "decimalEnclosedCircle", "lowerLetter",
        "upperLetter", "lowerRoman", "upperRoman", "bullet",
      ].contains(format) else {
        @failure.reject("invalid-operation", "Invalid list format")
      }
      let (instance, abstract_id) = self.list_identities()
      let relationships = self
        .relationships()
        .filter(rel => {
          rel.owner == self.main &&
          rel.kind ==
          "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
        })
      let part = if relationships.is_empty() {
        self.new_word_part("numbering", parts, edits, created)
      } else {
        self.numbering_context().part
      }
      let input = parts.get(part).unwrap_or_else(() => self.part_xml(part))
      let (candidate, edit) = append_part_xml(
        input,
        list_definition(instance, abstract_id, format),
      )
      parts[part] = candidate
      if created.contains(part) {
        created[part] = candidate
      } else {
        edits[part] = [edit]
      }
      for p in range.paragraphs {
        references[p] = (instance, 0)
      }
    }
    Restart(start) => {
      guard start >= 0 &&
        start <= 2147483646 &&
        range.start.paragraph == range.end.paragraph &&
        range.start.offset == range.end.offset else {
        @failure.reject(
          "invalid-operation", "Restart requires a caret and a valid start value",
        )
      }
      guard styles.numbering_reference(tree, range.start.paragraph)
        is Some((old, level)) else {
        @failure.reject("invalid-operation", "The paragraph has no list")
      }
      let context = self.numbering_context()
      guard context.level(old, level).format != "bullet" else {
        @failure.reject("invalid-operation", "Bullets cannot restart")
      }
      let (instance, abstract_id) = self.list_identities()
      let markup = context.restart_markup(
        tree,
        styles,
        range.start.paragraph,
        instance,
        abstract_id,
        start,
      )
      let (candidate, edit) = append_part_xml(
        self.part_xml(context.part),
        markup,
      )
      parts[context.part] = candidate
      edits[context.part] = [edit]
      let related = context.definition(old).levels
        .values()
        .any(l => {
          let mut count = 0
          for i in 0..<(l.pattern.length() - 1) {
            if l.pattern[i] == '%' &&
              l.pattern[i + 1] >= '1' &&
              l.pattern[i + 1] <= '9' {
              count += 1
            }
          }
          count > 1
        })
      let mut found = false
      for p in tree.order {
        if tree.nodes[p].uri != word_uri || tree.nodes[p].name != "p" {
          continue
        }
        if p == range.start.paragraph {
          found = true
        }
        guard found &&
          styles.numbering_reference(tree, p) is Some((current, index)) &&
          current == old else {
          continue
        }
        if level > 0 && !related {
          if index < level {
            break
          }
          if index > level {
            continue
          }
        }
        ignore(
          self.formatting_range(
            document,
            {
              anchor: { ..range.start, paragraph: p, offset: 0, },
              focus: { ..range.start, paragraph: p, offset: 0, },
            },
            notes=true,
          ),
        )
        references[p] = (instance, index)
      }
    }
  }
  if references.is_empty() && plain.is_empty() {
    return self.edit_state()
  }
  let changes : Array[@xml.SourceChange] = []
  for p, (instance, level) in references {
    let markup = formatted_properties(
      tree,
      document,
      p,
      "pPr",
      properties,
      nested=Map::from_array([("numPr", list_properties(instance, level))]),
    )
    if properties_change(tree, document, p, "pPr", markup) is Some(change) {
      changes.push(change)
    }
  }
  for p, patch in plain {
    let markup = formatted_properties(tree, document, p, "pPr", patch)
    if properties_change(tree, document, p, "pPr", markup) is Some(change) {
      changes.push(change)
    }
  }
  if changes.is_empty() {
    return self.edit_state()
  }
  let (candidate, xml) = document.edit_source(changes)
  let bytes = edit_bytes(xml) +
    xml_part_edit_bytes(edits, created) +
    prepared.map(p => p.edit.bytes).unwrap_or(0)
  guard bytes <= history_byte_limit else {
    @failure.reject("limit-exceeded", "List edit exceeds history budget")
  }
  let view = { ..self, parts, document: Some(candidate), }
  let changed = tree.order.filter(id => {
    references.contains(id) || plain.contains(id)
  })
  for p in view.formatting_paragraphs(candidate, changed) {
    validate_paragraph_style_values(p)
    guard p.readOnlyReason.is_empty() else {
      @failure.reject("protected-content", p.readOnlyReason)
    }
  }
  let pending = self.typing_format
  let affected = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p"
  })
  let steps = prepared.map(p => p.edit.xml.copy()).unwrap_or([])
  steps.push(xml)
  if prepared is Some(p) {
    for id in p.edit.paragraphs {
      if !affected.contains(id) {
        affected.push(id)
      }
    }
  }
  self.commit_edit(
    {
      xml: steps,
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: Some(selection.without_visual_hints()),
      paragraphs: affected,
      bytes,
    },
    candidate,
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}

///|
/// Lists supported existing numbering instances; unsupported definitions carry a reason.
pub fn Session::list_catalog(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if !self
    .relationships()
    .any(rel => {
      rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
    }) {
    return { "revision": revision, "lists": [], "truncated": false }
  }
  let context = self.numbering_context()
  let tree = WordTree::new(self.document())
  let styles = self.styles([])
  let previews : Map[Int, String] = Map([])
  let texts = docx_texts(tree)
  for p in tree.order {
    if tree.nodes[p].uri != word_uri || tree.nodes[p].name != "p" {
      continue
    }
    if styles.numbering_reference(tree, p) is Some((id, _)) &&
      !previews.contains(id) {
      let preview = texts
        .filter(t => t.paragraph == p)
        .map(t => inline_text(tree.nodes[t.id]))
        .join("")
      previews[id] = preview[:60].to_owned()
    }
  }
  let result : Array[Json] = []
  for id in context.instances.keys() {
    if id == 0 {
      continue
    }
    if result.length() == 1024 {
      break
    }
    let levels : Array[Json] = []
    let reason = try {
      let definition = context.definition(id)
      for level in 0..<9 {
        if definition.levels.get(level) is Some(value) {
          levels.push({
            "level": level,
            "format": value.format,
            "pattern": value.pattern,
            "start": value.start,
            "restart": if value.restart >= 0 {
              Json(value.restart)
            } else {
              Json::null()
            },
            "align": value.align,
            "suffix": value.suffix,
          })
        }
      }
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    result.push({
      "id": id,
      "preview": previews.get(id).unwrap_or(""),
      "levels": Json(levels),
      "reason": reason,
    })
  }
  {
    "revision": revision,
    "lists": Json(result),
    "truncated": context.instances.length() > 1024,
  }
}
