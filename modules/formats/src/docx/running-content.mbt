///|
/// Ordered text, links and page fields in a single-section header or footer.
pub(all) enum RunningContent {
  Text(String)
  Link(String, String)
  Field(String)
  FormattedField(String, String)
} derive(Eq)

///|
pub extend RunningContent with Eq::{equal, not_equal}

///|
pub extend RunningContent with ToJson::{to_json}

///|
pub impl ToJson for RunningContent with fn to_json(self) {
  match self {
    Text(text) => { "text": text }
    Link(text, target) => { "text": text, "target": target }
    Field(code) => { "field": code }
    FormattedField(code, format) => { "field": code, "format": format }
  }
}

///|
fn push_running_text(content : Array[RunningContent], text : String) -> Unit {
  if text.is_empty() {
    return
  }
  if content.last() is Some(Text(previous)) {
    content[content.length() - 1] = Text(previous + text)
  } else {
    content.push(Text(text))
  }
}

///|
fn normalize_running_content(
  content : Array[RunningContent],
) -> Array[RunningContent] raise @failure.Failure {
  guard content.length() <= 256 else {
    @failure.reject("invalid-operation", "Running content exceeds 256 items")
  }
  let result : Array[RunningContent] = []
  let mut units = 0
  for item in content {
    match item {
      Text(text) | Link(text, _) => {
        guard !text.contains("\r") && !has_region_break(text) else {
          @failure.reject("invalid-operation", "Invalid running text control")
        }
        guard text.length() <= 8192 - units else {
          @failure.reject(
            "invalid-operation", "Running content exceeds 8192 units",
          )
        }
        units += text.length()
        if item is Link(_, target) {
          check_hyperlink_target(target)
          guard !text.is_empty() else {
            @failure.reject(
              "invalid-operation", "Running links require display text",
            )
          }
          push_running_link(result, text, target)
        } else {
          push_running_text(result, text)
        }
      }
      Field(code) | FormattedField(code, _) => {
        guard ["PAGE", "NUMPAGES"].contains(code) else {
          @failure.reject("invalid-operation", "Invalid running field")
        }
        units += 1
        if item is FormattedField(_, format) {
          ignore(running_field_instruction(code + ":" + format))
        }
        result.push(item)
      }
    }
    guard units <= 8192 else {
      @failure.reject("invalid-operation", "Running content exceeds 8192 units")
    }
  }
  if result.is_empty() {
    result.push(Text(""))
  }
  result
}

///|
fn running_content(
  paragraphs : Array[@layout.Paragraph],
  links : Map[Int, String],
) -> Array[RunningContent] {
  let result : Array[RunningContent] = []
  for index, paragraph in paragraphs {
    if index > 0 {
      push_running_text(result, "\n")
    }
    for span in paragraph.spans {
      if span.field.is_empty() {
        let text = span.text.replace_all(old="\n", new="\u2028")
        if links.get(span.node) is Some(target) {
          push_running_link(result, text, target)
        } else {
          push_running_text(result, text)
        }
      } else {
        let tokens = span.field.split(":").to_array()
        result.push(
          if tokens.length() == 2 {
            FormattedField(tokens[0].to_owned(), tokens[1].to_owned())
          } else {
            Field(span.field)
          },
        )
      }
    }
  }
  if result.is_empty() {
    result.push(Text(""))
  }
  result
}

///|
fn running_content_paragraphs(
  content : Array[RunningContent],
) -> Array[Array[RunningContent]] {
  let result : Array[Array[RunningContent]] = [[]]
  for item in content {
    match item {
      Field(_) | FormattedField(_, _) => result.last().unwrap().push(item)
      Text(text) | Link(text, _) =>
        for index, line in text.split("\n").to_array() {
          if index > 0 {
            result.push([])
          }
          if item is Link(_, target) {
            push_running_link(result.last().unwrap(), line.to_owned(), target)
          } else {
            push_running_text(result.last().unwrap(), line.to_owned())
          }
        }
    }
  }
  for paragraph in result {
    if paragraph.is_empty() {
      paragraph.push(Text(""))
    }
  }
  result
}

///|
fn running_content_markup(
  document : @xml.Document,
  story : WordTree,
  current : Array[@layout.Paragraph],
  content : Array[RunningContent],
  current_links : Map[Int, String],
  relations : Map[String, String],
) -> String raise @failure.Failure {
  let paragraphs = story.running_nodes()
  let watermarks = story.children[0]
    .filter(id => story.watermark_block(id))
    .map(id => {
      document.source()[story.nodes[id].start:story.nodes[id].end].to_owned()
    })
    .join("")
  watermarks +
  running_content_paragraphs(content)
  .mapi((index, value) => {
    if current.get(index) is Some(paragraph) &&
      running_content([paragraph], current_links) == value {
      let node = story.nodes[paragraphs[index]]
      return document.source()[node.start:node.end].to_owned()
    }
    let template = match paragraphs.get(index) {
      Some(id) => Some(id)
      None => paragraphs.last()
    }
    let ppr = template
      .bind(id => story.child(id, "pPr"))
      .map(id => story.standalone_markup(document, id))
      .unwrap_or("")
    let rpr = template
      .bind(id => story.paragraph_runs(id, running=true).get(0))
      .bind(id => story.child(id, "rPr"))
      .map(id => story.standalone_markup(document, id))
      .unwrap_or("")
    let fields = current
      .get(index)
      .map(p => p.spans.filter(s => !s.field.is_empty()))
      .unwrap_or([])
    let mut field = 0
    let markup = value
      .map(item => {
        match item {
          Text(text) =>
            "<w:r>\{rpr}\{inline_markup(text, history_byte_limit / 2)}</w:r>"
          Link(text, target) => {
            let attribute = if target.has_prefix("#") {
              "w:anchor=\"\{property_attribute(target[1:].to_owned())}\""
            } else {
              "xmlns:r=\"\{running_rel_uri}\" r:id=\"\{property_attribute(relations[target])}\""
            }
            "<w:hyperlink \{attribute}><w:r>\{rpr}\{inline_markup(text, history_byte_limit / 2)}</w:r></w:hyperlink>"
          }
          Field(code) | FormattedField(code, _) => {
            let properties = fields
              .get(field)
              .bind(span => story.child(story.nodes[span.node].parent, "rPr"))
              .map(id => story.standalone_markup(document, id))
              .unwrap_or(rpr)
            field += 1
            let code = running_field_instruction(
              if item is FormattedField(_, format) {
                code + ":" + format
              } else {
                code
              },
            )
            "<w:fldSimple w:instr=\"\{code}\" w:dirty=\"true\"><w:r>\{properties}<w:t>1</w:t></w:r></w:fldSimple>"
          }
        }
      })
      .join("")
    "<w:p xmlns:w=\"\{word_uri}\">\{ppr}\{markup}</w:p>"
  })
  .join("")
}

///|
fn refresh_running_fields(
  part : String,
  variant : String,
  section : Int,
  flow : @layout.Flow,
  layout : @layout.Layout,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Running field update requires a complete layout",
    )
  }
  guard layout.sectionNumbering.get(section) is Some(numbering) else {
    @failure.reject("invalid-operation", "Missing running section numbering")
  }
  let (first, even) = if section == 0 {
    (flow.differentFirst, flow.differentEven)
  } else {
    let profile = flow.sectionBreaks[section - 1]
    (profile.differentFirst, profile.differentEven)
  }
  let page = [0, 1, 2]
    .iter()
    .find_first(page => {
      numbering.variant(
        page,
        first || variant == "first",
        even || variant == "even",
      ) ==
      variant
    })
    .unwrap_or(0)
  let document = parts[part]
  let tree = WordTree::new(document)
  let changes : Array[@xml.SourceChange] = []
  for paragraph in tree.children[0] {
    for id, code in tree.running_fields(paragraph) {
      let value = if code.is_empty() {
        ""
      } else {
        numbering.field_text(code, page, layout.pages.length())
      }
      let node = tree.nodes[id]
      if node.text != value {
        changes.push(
          if node.empty {
            {
              node: id,
              offset: node.opening_end - node.start - 2,
              length: 2,
              xml: ">\{value}</\{node.qualified}>",
            }
          } else {
            {
              node: id,
              offset: node.opening_end - node.start,
              length: node.closing_start - node.opening_end,
              xml: value,
            }
          },
        )
      }
    }
  }
  if changes.is_empty() {
    return
  }
  let (updated, edit) = document.edit_source(changes)
  parts[part] = updated
  if created.contains(part) {
    created[part] = updated
  } else if edits.get(part) is Some(previous) {
    previous.push(edit)
  } else {
    edits[part] = [edit]
  }
}
