///|
fn formatting_boundary(
  tree : WordTree,
  texts : Array[TextNode],
  offset : Int,
) -> (Int, Int) {
  for item in texts; cursor = 0 {
    let length = inline_text(tree.nodes[item.id]).length()
    if offset <= cursor + length {
      break (item.id, offset - cursor)
    }
    continue cursor + length
  } nobreak {
    abort("Validated formatting boundary is missing")
  }
}

///|
fn Session::format_character_document(
  self : Session,
  document : @xml.Document,
  selection : Selection,
  patch : CharacterFormat,
  include_empty~ : Bool = false,
  split~ : Bool = false,
  fields~ : Bool = false,
) -> (@xml.Document, @xml.Edit)? raise @failure.Failure {
  let tree = WordTree::new(document)
  let range = self.formatting_range(
    document,
    selection,
    whole_cells=true,
    fields~,
  )
  let include_empty = include_empty ||
    tree.nodes[range.start.paragraph].parent !=
    tree.nodes[range.end.paragraph].parent
  let source = document.source()
  let changes : Array[@xml.SourceChange] = []
  let properties = patch.properties()
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let mut units = 0
  for paragraph in range.paragraphs {
    let texts = docx_texts(tree).filter(item => item.paragraph == paragraph)
    let length = texts
      .iter()
      .fold(init=0, (sum, item) => {
        sum + inline_text(tree.nodes[item.id]).length()
      })
    let start = if paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if paragraph == range.end.paragraph {
      range.end.offset
    } else {
      length
    }
    if start == end {
      if include_empty && length == 0 {
        if tree.paragraph_runs(paragraph).get(0) is Some(run) {
          let markup = formatted_properties(
            tree, document, run, "rPr", properties,
          )
          if properties_change(tree, document, run, "rPr", markup)
            is Some(change) {
            changes.push(change)
          }
          continue
        }
        let parent = tree.child(paragraph, "pPr")
        let markup = match parent {
          Some(parent) =>
            formatted_properties(tree, document, parent, "rPr", properties)
          None =>
            formatted_properties(tree, document, paragraph, "rPr", properties)
        }
        let change = match parent {
          Some(parent) =>
            properties_change(tree, document, parent, "rPr", markup)
          None =>
            properties_change(
              tree,
              document,
              paragraph,
              "pPr",
              "<od:pPr xmlns:od=\"\{word_uri}\">\{markup}</od:pPr>",
            )
        }
        if change is Some(change) {
          changes.push(change)
        }
      }
      continue
    }
    let runs : Array[Int] = []
    for item in texts {
      if !runs.contains(item.run) {
        runs.push(item.run)
      }
    }
    let mut cursor = 0
    for id in runs {
      let run_texts = texts.filter(item => item.run == id)
      let count = run_texts
        .iter()
        .fold(init=0, (sum, item) => {
          sum + inline_text(tree.nodes[item.id]).length()
        })
      let left = (start - cursor).clamp(min=0, max=count)
      let right = (end - cursor).clamp(min=0, max=count)
      cursor += count
      if left == right {
        continue
      }
      let markup = formatted_properties(tree, document, id, "rPr", properties)
      let original = tree
        .child(id, "rPr")
        .map(child => {
          let node = tree.nodes[child]
          source[node.start:node.end].to_owned()
        })
        .unwrap_or("")
      if markup == original && !split {
        continue
      }
      let run = tree.nodes[id]
      let opening = source[run.start:run.opening_end].to_owned()
      let boundaries : Array[(Int, Int, String)] = []
      if left == 0 {
        if properties_change(tree, document, id, "rPr", markup) is Some(change) {
          changes.push(change)
        }
      } else {
        let boundary = formatting_boundary(tree, run_texts, left)
        guard opening.length() + markup.length() <= limit - units else {
          @failure.reject("limit-exceeded", "Formatting source budget exceeded")
        }
        boundaries.push(
          (boundary.0, boundary.1, "</\{run.qualified}>\{opening}\{markup}"),
        )
      }
      if right < count {
        let boundary = formatting_boundary(tree, run_texts, right)
        guard opening.length() + original.length() <= limit - units else {
          @failure.reject("limit-exceeded", "Formatting source budget exceeded")
        }
        boundaries.push(
          (boundary.0, boundary.1, "</\{run.qualified}>\{opening}\{original}"),
        )
      }
      for item in run_texts {
        let node = tree.nodes[item.id]
        let points = boundaries.filter(point => point.0 == item.id)
        let middle : Array[(Int, String)] = []
        for (_, offset, frame) in points {
          units += frame.length()
          guard units <= limit else {
            @failure.reject(
              "limit-exceeded", "Formatting source budget exceeded",
            )
          }
          if offset == 0 || offset == inline_text(node).length() {
            let position = if offset == 0 { node.start } else { node.end }
            changes.push({
              node: paragraph,
              offset: position - tree.nodes[paragraph].start,
              length: 0,
              xml: frame,
            })
          } else {
            guard node.attributes
              .iter()
              .all(attribute => {
                attribute.uri == "http://www.w3.org/XML/1998/namespace" &&
                attribute.name == "space"
              }) &&
              !source[node.opening_end:node.closing_start].contains("<!--") &&
              !source[node.opening_end:node.closing_start].contains("<?") else {
              @failure.reject(
                "protected-content", "Unknown text markup prevents formatting split",
              )
            }
            let text_opening = structure_opening(node)
            let text_opening = text_opening[:text_opening.length() - 1].to_owned() +
              " xml:space=\"preserve\">"
            middle.push((offset, "</\{node.qualified}>\{frame}\{text_opening}"))
          }
        }
        if !middle.is_empty() {
          let out = StringBuilder()
          let mut start = 0
          for (offset, frame) in middle {
            out.write_string(
              @xml.escape_text(node.text[start:offset].to_owned()),
            )
            out.write_string(frame)
            start = offset
          }
          out.write_string(@xml.escape_text(node.text[start:].to_owned()))
          let xml = out.to_string()
          units += xml.length()
          guard units <= limit else {
            @failure.reject(
              "limit-exceeded", "Formatting source budget exceeded",
            )
          }
          changes.push({
            node: paragraph,
            offset: node.opening_end - tree.nodes[paragraph].start,
            length: node.closing_start - node.opening_end,
            xml,
          })
        }
      }
    }
  }
  if changes.is_empty() {
    None
  } else {
    Some(document.edit_source(changes))
  }
}

///|
/// Applies direct formatting to the explicit range, or to subsequent input at a caret.
pub fn Session::set_character_format(
  self : Session,
  revision : Int,
  selection : Selection,
  patch : CharacterFormat,
) -> Json raise @failure.Failure {
  self.apply_format(revision, selection, patch, ParagraphFormat::new())
}

///|
fn Session::prepare_formatted_input(
  self : Session,
  selection : Selection,
  prepared : PreparedEdit,
  patch : CharacterFormat,
) -> PreparedEdit raise @failure.Failure {
  let focus = { ..prepared.edit.after.unwrap().focus, affinity: "before", }
  let range = { anchor: selection.anchor, focus, }
  guard self.format_character_document(
      prepared.document,
      range,
      patch,
      include_empty=true,
      fields=true,
    )
    is Some((document, xml)) else {
    return prepared
  }
  let bytes = edit_bytes(xml)
  guard bytes <= history_byte_limit - prepared.edit.bytes else {
    @failure.reject("limit-exceeded", "Formatted input history budget exceeded")
  }
  let edits = prepared.edit.xml.copy()
  edits.push(xml)
  let tree = WordTree::new(document)
  let texts = docx_texts(tree).filter(item => item.paragraph == focus.paragraph)
  let typing = if texts.is_empty() {
    None
  } else {
    Some(formatting_boundary(tree, texts, focus.offset).0)
  }
  {
    ..prepared,
    document,
    edit: {
      ..prepared.edit,
      xml: edits,
      bytes: prepared.edit.bytes + bytes,
      after: Some({ anchor: focus, focus, }),
    },
    typing_text: typing,
  }
}
