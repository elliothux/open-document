///|
fn Session::body_field_source(
  self : Session,
  document : @xml.Document,
  position : Position,
  instruction : String,
) -> @xml.SourceChange raise @failure.Failure {
  let tree = WordTree::new(document)
  let texts = docx_texts(tree).filter(item => {
    item.paragraph == position.paragraph
  })
  let target = for item in texts; offset = 0 {
    let length = inline_text(tree.nodes[item.id]).length()
    if position.offset < offset + length ||
      (position.offset == offset + length && position.affinity == "before") {
      break Some((item.id, position.offset - offset))
    }
    continue offset + length
  } nobreak {
    texts
    .last()
    .map(item => (item.id, inline_text(tree.nodes[item.id]).length()))
  }
  let run = target.map(pair => {
    let node = tree.nodes[pair.0]
    if node.name == "fldSimple" {
      tree.field_result_run(node.id).unwrap()
    } else {
      node.parent
    }
  })
  let properties = if run is Some(run) {
    if self.typing_format is Some(patch) {
      formatted_properties(tree, document, run, "rPr", patch.properties())
    } else {
      tree
      .child(run, "rPr")
      .map(id => tree.standalone_markup(document, id))
      .unwrap_or("")
    }
  } else {
    tree.empty_run_properties(document, position.paragraph)
  }
  let field = "<od:fldSimple xmlns:od=\"\{word_uri}\" od:instr=\"\{property_attribute(instruction)}\" od:dirty=\"true\"><od:r>\{properties}<od:t>1</od:t></od:r></od:fldSimple>"
  let paragraph = tree.nodes[position.paragraph]
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let change : @xml.SourceChange = if target is Some((id, offset)) {
    let node = tree.nodes[id]
    if node.name == "fldSimple" {
      {
        node: paragraph.id,
        offset: (if offset == 0 { node.start } else { node.end }) -
        paragraph.start,
        length: 0,
        xml: field,
      }
    } else {
      let parent = tree.nodes[node.parent]
      guard parent.parent == paragraph.id else {
        @failure.reject(
          "protected-content", "Field insertion inside hyperlinks requires editing support",
        )
      }
      let original = tree
        .child(parent.id, "rPr")
        .map(id => tree.standalone_markup(document, id))
        .unwrap_or("")
      let frame = "</\{parent.qualified}>\{field}\{structure_opening(parent)}\{original}"
      if node.name == "t" {
        guard node.attributes.all(a => {
            a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
          }) &&
          !document.source()[node.start:node.end].contains("<!--") &&
          !document.source()[node.start:node.end].contains("<?") else {
          @failure.reject(
            "protected-content", "Opaque source prevents field insertion",
          )
        }
        {
          node: paragraph.id,
          offset: node.start - paragraph.start,
          length: node.end - node.start,
          xml: inline_markup(node.text[:offset].to_owned(), limit) +
          frame +
          inline_markup(node.text[offset:].to_owned(), limit),
        }
      } else {
        {
          node: paragraph.id,
          offset: (if offset == 0 { node.start } else { node.end }) -
          paragraph.start,
          length: 0,
          xml: frame,
        }
      }
    }
  } else if paragraph.empty {
    {
      node: paragraph.id,
      offset: paragraph.opening_end - paragraph.start - 2,
      length: 2,
      xml: ">\{field}</\{paragraph.qualified}>",
    }
  } else {
    {
      node: paragraph.id,
      offset: paragraph.closing_start - paragraph.start,
      length: 0,
      xml: field,
    }
  }
  guard change.xml.length() <= limit else {
    @failure.reject("limit-exceeded", "Field insertion source exceeds budget")
  }
  change
}

///|
/// Replaces the current range with one page field, caching its actual layout value.
pub fn Session::insert_body_page_field(
  self : Session,
  revision : Int,
  field : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let instruction = running_field_instruction(field)
  guard self.selection is Some(selection) else {
    @failure.reject("invalid-position", "Select a document position first")
  }
  let original = self.document()
  WordTree::new(original).check_body_field_target(field)
  ignore(self.editable_page_section(WordTree::new(original)))
  let prepared = self.prepare_plain_range(selection, "")
  let document = prepared.map(p => p.document).unwrap_or(original)
  let position = prepared
    .bind(p => p.edit.after)
    .map(s => s.focus)
    .unwrap_or(selection.focus)
  let steps = prepared.map(p => p.edit.xml.copy()).unwrap_or([])
  let change = self.body_field_source(document, position, instruction)
  let (candidate, edit) = document.edit_source([change])
  steps.push(edit)
  let before = WordTree::new(document)
  let tree = WordTree::new(candidate)
  let inserted = tree.children[position.paragraph]
    .iter()
    .find_first(id => {
      tree.nodes[id].name == "fldSimple" && !before.nodes.contains(id)
    })
    .unwrap()
  let flow = { ..self, document: Some(candidate), }.flow()
  let layout = @layout.paginate(probe, flow, profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Field insertion requires a complete layout",
    )
  }
  let (candidate, edit) = candidate.edit_text(
    self.field_cache_changes(tree, [inserted], layout),
  )
  steps.push(edit)
  let mut bytes = 0
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "Field insertion history exceeds budget",
      )
    }
    bytes += size
  }
  let focus = {
    ..position,
    offset: position.offset + 1,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  self.check_position_in(candidate, focus)
  let paragraphs = prepared
    .map(p => p.edit.paragraphs)
    .unwrap_or([position.paragraph])
  self.commit_edit(
    {
      xml: steps,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: focus, focus, }),
      paragraphs,
      bytes,
    },
    candidate,
  )
  self.edit_result(paragraphs)
}
