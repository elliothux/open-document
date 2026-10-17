///|
/// Ordered text and decimal page fields in a single-section header or footer.
pub(all) enum RunningContent {
  Text(String)
  Field(String)
} derive(Eq)

///|
pub extend RunningContent with Eq::{equal, not_equal}

///|
pub extend RunningContent with ToJson::{to_json}

///|
pub impl ToJson for RunningContent with fn to_json(self) {
  match self {
    Text(text) => { "text": text }
    Field(code) => { "field": code }
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
      Text(text) => {
        guard !text.contains("\r") && !text.contains("\u000c") else {
          @failure.reject("invalid-operation", "Invalid running text control")
        }
        guard text.length() <= 8192 - units else {
          @failure.reject(
            "invalid-operation", "Running content exceeds 8192 units",
          )
        }
        units += text.length()
        push_running_text(result, text)
      }
      Field(code) => {
        guard ["PAGE", "NUMPAGES"].contains(code) else {
          @failure.reject("invalid-operation", "Invalid running field")
        }
        units += 1
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
) -> Array[RunningContent] {
  let result : Array[RunningContent] = []
  for index, paragraph in paragraphs {
    if index > 0 {
      push_running_text(result, "\n")
    }
    for span in paragraph.spans {
      if span.field.is_empty() {
        push_running_text(result, span.text.replace_all(old="\n", new="\u2028"))
      } else {
        result.push(Field(span.field))
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
      Field(_) => result.last().unwrap().push(item)
      Text(text) =>
        for index, line in text.split("\n").to_array() {
          if index > 0 {
            result.push([])
          }
          push_running_text(result.last().unwrap(), line.to_owned())
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
) -> String raise @failure.Failure {
  let paragraphs = story.children[0]
  running_content_paragraphs(content)
  .mapi((index, value) => {
    if current.get(index) is Some(paragraph) &&
      running_content([paragraph]) == value {
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
          Field(code) => {
            let properties = fields
              .get(field)
              .bind(span => story.child(story.nodes[span.node].parent, "rPr"))
              .map(id => story.standalone_markup(document, id))
              .unwrap_or(rpr)
            field += 1
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
  let page = if variant == "first" {
    1
  } else if variant == "even" {
    2
  } else if flow.differentFirst {
    if flow.differentEven {
      3
    } else {
      2
    }
  } else {
    1
  }
  let document = parts[part]
  let tree = WordTree::new(document)
  let changes : Array[@xml.SourceChange] = []
  for paragraph in tree.children[0] {
    for id, code in tree.running_fields(paragraph) {
      let value = match code {
        "PAGE" => page.to_string()
        "NUMPAGES" => layout.pages.length().to_string()
        _ => ""
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
