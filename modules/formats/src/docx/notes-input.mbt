///|
fn WordTree::note_input_properties(
  self : WordTree,
  document : @xml.Document,
  id : Int,
) -> String raise @failure.Failure {
  formatted_properties(
    self,
    document,
    self.nodes[id].parent,
    "rPr",
    CharacterFormat::new(style=Clear, vertAlign=Set("baseline")).properties(),
  )
}

///|
fn WordTree::note_text_changes(
  self : WordTree,
  document : @xml.Document,
  id : Int,
  text : String,
  retained : Int?,
  limit : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let node = self.nodes[id]
  let run = self.nodes[node.parent]
  let paragraph = self.nodes[run.parent]
  let container = self.nodes[paragraph.parent]
  let properties = self.note_input_properties(document, id)
  let original = self
    .child(run.id, "rPr")
    .map(id => self.standalone_markup(document, id))
    .unwrap_or("")
  fn frame(value : String) -> String raise @failure.Failure {
    "</\{run.qualified}><od:r xmlns:od='\{word_uri}'>\{properties}\{inline_markup(value, limit)}</od:r>\{structure_opening(run)}\{original}"
  }
  let changes : Array[@xml.SourceChange] = if retained is Some(offset) {
    guard offset >= 0 && offset < text.length() && text[offset] == '\ufffc' else {
      @failure.reject("invalid-operation", "Invalid retained note marker")
    }
    [
      (node.start, text[:offset].to_owned()),
      (node.end, text[offset + 1:].to_owned()),
    ]
    .filter(pair => !pair.1.is_empty())
    .map(pair => {
      node: container.id,
      offset: pair.0 - container.start,
      length: 0,
      xml: frame(pair.1),
    })
  } else {
    [
      {
        node: container.id,
        offset: node.start - container.start,
        length: node.end - node.start,
        xml: frame(text),
      },
    ]
  }
  guard changes.fold(init=0, (total, item) => total + item.xml.length()) <=
    limit else {
    @failure.reject("limit-exceeded", "Note input source exceeds budget")
  }
  changes
}

///|
fn WordTree::split_note_input(
  self : WordTree,
  document : @xml.Document,
  paragraph : Int,
  insertion : Int,
  offset : Int,
  parts : Array[String],
  tail : String,
  limit : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let node = self.nodes[insertion]
  let run = self.nodes[node.parent]
  let p = self.nodes[paragraph]
  let parent = self.nodes[p.parent]
  let original = self
    .child(run.id, "rPr")
    .map(id => self.standalone_markup(document, id))
    .unwrap_or("")
  let properties = self.note_input_properties(document, insertion)
  let mark = "<od:r xmlns:od='\{word_uri}'>\{original}\{self.standalone_markup(document, insertion)}</od:r>"
  let next = "</\{p.qualified}>\{structure_opening(p)}\{self.continuation_properties(document, paragraph)}"
  let out = StringBuilder()
  out.write_string("</\{run.qualified}>")
  let mut units = run.qualified.length() + 3
  for index, part in parts {
    let prefix = if index > 0 { next } else if offset == 1 { mark } else { "" }
    let suffix = if index == parts.length() - 1 &&
      offset == 0 &&
      tail == "\ufffc" {
      mark
    } else {
      ""
    }
    let content = prefix +
      "<od:r xmlns:od='\{word_uri}'>\{properties}\{inline_markup(part, limit-units)}</od:r>" +
      suffix
    units += content.length()
    guard units <= limit else {
      @failure.reject(
        "limit-exceeded", "Note paragraph split exceeds source budget",
      )
    }
    out.write_string(content)
  }
  let ending = structure_opening(run) + original
  guard ending.length() <= limit - units else {
    @failure.reject(
      "limit-exceeded", "Note paragraph split exceeds source budget",
    )
  }
  out.write_string(ending)
  [
    {
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: out.to_string(),
    },
  ]
}
