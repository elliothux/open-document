///|
fn Session::selected_body_page_field(
  self : Session,
  tree : WordTree,
  selection : Selection,
) -> Int? raise @failure.Failure {
  let range = self.paragraph_range(
    tree,
    selection,
    structural=true,
    fields=true,
  )
  if range.start.paragraph != range.end.paragraph {
    return None
  }
  let collapsed = range.start.offset == range.end.offset
  for
    item in docx_texts(tree).filter(item => {
      item.paragraph == range.start.paragraph
    })
    offset = 0 {
    let length = inline_text(tree.nodes[item.id]).length()
    if tree.nodes[item.id].name == "fldSimple" &&
      (if collapsed {
        (range.start.offset == offset && selection.focus.affinity == "after") ||
        (
          range.start.offset == offset + 1 &&
          selection.focus.affinity == "before"
        )
      } else {
        range.start.offset == offset && range.end.offset == offset + 1
      }) {
      return Some(item.id)
    }
    continue offset + length
  }
  None
}

///|
/// Reads one complete simple page field or the field on the caret's affinity side.
pub fn Session::body_page_field(
  self : Session,
  revision : Int,
  selection : Selection,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let mut reason = ""
  let field = self.selected_body_page_field(tree, selection) catch {
    @failure.Failure(code="protected-content", message~, ..) => {
      reason = message
      None
    }
    error => raise error
  }
  let value = match field {
    None => {
      if reason.is_empty() {
        reason = "Select one simple page field or its adjacent caret"
      }
      Json::null()
    }
    Some(id) => {
      let code = running_field_code(
        tree.nodes[id].attribute("instr", uri=word_uri).unwrap(),
      )
      let parts = code.split(":").to_array()
      let value : Map[String, Json] = { "field": Json(parts[0].to_owned()) }
      let reference = parts[0] == "PAGEREF"
      if reference {
        let reference = @layout.PageReference::parse(code)
        value["bookmark"] = Json(reference.bookmark)
        if !reference.format.is_empty() {
          value["format"] = Json(reference.format)
        }
        if reference.hyperlink {
          value["hyperlink"] = Json(true)
        }
        if reference.relative {
          value["relative"] = Json(true)
        }
      } else if parts[0] == "REF" {
        let reference = @layout.TextReference::parse(code)
        value["bookmark"] = Json(reference.bookmark)
        if reference.hyperlink {
          value["hyperlink"] = Json(true)
        }
      } else if parts[0] == "SEQ" {
        let sequence = @layout.SequenceField::parse(code)
        value["sequence"] = Json(sequence.sequence)
        if sequence.hidden {
          value["hidden"] = Json(true)
        }
        if sequence.headingLevel is Some(level) {
          value["headingLevel"] = Json(level)
        }
        if sequence.repeat {
          value["repeat"] = Json(true)
        }
        if sequence.restart is Some(start) {
          value["restart"] = Json(start)
        }
        if !sequence.format.is_empty() {
          value["format"] = Json(sequence.format)
        }
      } else if parts.length() == 2 {
        value["format"] = Json(parts.last().unwrap().to_owned())
      }
      Json(value)
    }
  }
  {
    "revision": revision,
    "selection": Json(selection),
    "field": value,
    "reason": reason,
  }
}

///|
/// Changes the selected simple field's code and refreshes only its result in one transaction.
pub fn Session::edit_body_page_field(
  self : Session,
  revision : Int,
  selection : Selection,
  field : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let instruction = running_field_instruction(field)
  let field = running_field_code(instruction)
  let original = self.document()
  let tree = WordTree::new(original)
  tree.check_body_field_target(field)
  ignore(self.editable_page_section(tree))
  guard self.selected_body_page_field(tree, selection) is Some(id) else {
    @failure.reject(
      "invalid-position", "Select one simple page field or its adjacent caret",
    )
  }
  let node = tree.nodes[id]
  let attribute = node.attributes
    .iter()
    .find_first(a => a.uri == word_uri && a.name == "instr")
    .unwrap()
  if running_field_code(attribute.value) == field {
    return self.edit_state()
  }
  let instruction = instruction +
    (if !(field.has_prefix("SEQ:") && @layout.SequenceField::parse(field).hidden) &&
      !instruction.to_upper().contains("MERGEFORMAT") &&
      attribute.value.to_upper().contains("MERGEFORMAT") {
      " \\* MERGEFORMAT"
    } else {
      ""
    })
  let (candidate, edit) = original.edit_source([
    {
      node: id,
      offset: attribute.start - node.start,
      length: attribute.end - attribute.start,
      xml: property_attribute(instruction),
    },
  ])
  let steps = [edit]
  let view = { ..self, document: Some(candidate), }
  let layout = @layout.paginate(probe, view.flow(), profile, images)
  let changes = self.field_cache_changes(WordTree::new(candidate), [id], layout)
  let candidate = if changes.is_empty() {
    candidate
  } else {
    let (document, edit) = candidate.edit_text(changes)
    steps.push(edit)
    document
  }
  let mut bytes = 0
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "Field instruction history exceeds budget",
      )
    }
    bytes += size
  }
  let paragraphs = [node.parent]
  self.commit_edit(
    {
      xml: steps,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some(selection.without_visual_hints()),
      paragraphs,
      bytes,
    },
    candidate,
  )
  self.edit_result(paragraphs)
}

///|
/// Refreshes supported body page fields in one exact source transaction.
pub fn Session::update_body_page_fields(
  self : Session,
  revision : Int,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let tree = WordTree::new(original)
  ignore(self.editable_page_section(tree))
  let flow = self.flow()
  let layout = @layout.paginate(probe, flow, profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Body field update requires a complete layout",
    )
  }
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        paragraphs.append(cell)
      }
    }
  }
  let fields : Map[(Int, Int), Bool] = Map([])
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if !span.field.is_empty() {
        fields[(paragraph.id, span.node)] = true
      }
    }
  }
  let pages : Map[(Int, Int), Int] = Map([])
  let displayed : Map[(Int, Int), String] = Map([])
  for page, frame in layout.pages {
    for line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          let key = (line.paragraph, source.node)
          if fields.contains(key) && !pages.contains(key) {
            pages[key] = page
            displayed[key] = run.text
          }
        }
      }
    }
  }
  let affected : Array[Int] = []
  let changes : Array[@xml.SourceChange] = []
  let mut count = 0
  for paragraph in paragraphs {
    for id, code in tree.running_fields(paragraph.id) {
      count += 1
      guard count <= 4096 else {
        @failure.reject("limit-exceeded", "Body page fields exceed limits")
      }
      let value = if code.has_prefix("PAGEREF:") ||
        code.has_prefix("SEQ:") ||
        code.has_prefix("REF:") {
        displayed
        .get((paragraph.id, id))
        .unwrap_or_else(() => {
          @failure.reject(
            "unsupported-layout", "Page reference result is unavailable",
          )
        })
      } else if code.is_empty() {
        ""
      } else {
        guard pages.get((paragraph.id, id)) is Some(page) else {
          @failure.reject(
            "unsupported-layout", "Body field position is unavailable",
          )
        }
        flow.pageNumbering.field_text(code, page, layout.pages.length())
      }
      let node = tree.nodes[id]
      if node.text == value {
        continue
      }
      let source = original.source()[node.start:node.end]
      guard !source.contains("<!--") && !source.contains("<?") else {
        @failure.reject(
          "protected-content", "Opaque field result source cannot be refreshed",
        )
      }
      let text = @xml.escape_text(value)
      changes.push(
        if node.empty {
          {
            node: id,
            offset: node.opening_end - node.start - 2,
            length: 2,
            xml: ">\{text}</\{node.qualified}>",
          }
        } else {
          {
            node: id,
            offset: node.opening_end - node.start,
            length: node.closing_start - node.opening_end,
            xml: text,
          }
        },
      )
      if !affected.contains(paragraph.id) {
        affected.push(paragraph.id)
      }
    }
  }
  if changes.is_empty() {
    return self.edit_state()
  }
  let (candidate, step) = original.edit_source(changes)
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [step],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs: affected,
      bytes: edit_bytes(step),
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
