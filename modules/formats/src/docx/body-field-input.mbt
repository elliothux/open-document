///|
fn WordTree::field_result_run(self : WordTree, field : Int32) -> Int32? {
  self.children[field]
  .iter()
  .find_first(id => {
    self.nodes[id].uri == word_uri &&
    self.nodes[id].name == "r" &&
    self.child(id, "t") is Some(_)
  })
}

///|
fn WordTree::simple_page_fields(
  self : WordTree,
  paragraph : Int32,
) -> Unit raise @failure.Failure {
  ignore(self.running_fields(paragraph)) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) =>
      @failure.reject("protected-content", message)
  }
  guard !self
    .descendants(paragraph)
    .any(id => {
      self.nodes[id].uri == word_uri &&
      !self.index_markers.contains(id) &&
      ["fldChar", "instrText"].contains(self.nodes[id].name)
    }) else {
    @failure.reject(
      "protected-content", "Complex page fields require range editing support",
    )
  }
}

///|
fn WordTree::paragraph_object_properties(
  self : WordTree,
  document : @xml.Document,
  id : Int32,
) -> String raise @failure.Failure {
  if self.nodes[id].name == "fldSimple" {
    self
    .field_result_run(id)
    .bind(run => self.child(run, "rPr"))
    .map(id => self.standalone_markup(document, id))
    .unwrap_or("")
  } else {
    self.empty_run_properties(document, self.nodes[id].parent)
  }
}

///|
fn paragraph_object_text_changes(
  tree : WordTree,
  document : @xml.Document,
  id : Int32,
  text : String,
  retained : Int32?,
  limit : Int32,
  notes~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let node = tree.nodes[id]
  let paragraph = tree.nodes[node.parent]
  let parent = tree.nodes[paragraph.parent]
  tree.check_editable_paragraph(
    paragraph.id,
    part="",
    pictures=true,
    fields=true,
    math=true,
    notes~,
  )
  let properties = tree.paragraph_object_properties(document, id)
  fn run(value : String) -> String raise @failure.Failure {
    if value.is_empty() {
      return ""
    }
    "<od:r xmlns:od=\"\{word_uri}\">\{properties}\{inline_markup(value, limit)}</od:r>"
  }
  if retained is Some(offset) {
    guard offset >= 0 && offset < text.length() && text[offset] == '\ufffc' else {
      abort("Invalid retained field position")
    }
    [
      (node.start, text[:offset].to_owned()),
      (node.end, text[offset + 1:].to_owned()),
    ]
    .filter(pair => !pair.1.is_empty())
    .map(pair => {
      node: parent.id,
      offset: pair.0 - parent.start,
      length: 0,
      xml: run(pair.1),
    })
  } else {
    [
      {
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: run(text),
      },
    ]
  }
}

///|
fn WordTree::split_paragraph_object_input(
  self : WordTree,
  document : @xml.Document,
  paragraph : Int32,
  insertion : Int32,
  offset : Int32,
  parts : Array[String],
  tail : String,
  limit : Int32,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let node = self.nodes[insertion]
  let p = self.nodes[paragraph]
  let parent = self.nodes[p.parent]
  let properties = self.paragraph_object_properties(document, insertion)
  let frame = "</\{p.qualified}>" +
    structure_opening(p) +
    self.continuation_properties(document, paragraph)
  let output = StringBuilder()
  let mut units = 0
  for index, part in parts {
    if index > 0 {
      units += frame.length()
      output.write_string(frame)
    }
    guard units <= limit else {
      @failure.reject(
        "limit-exceeded", "Field paragraph split exceeds source budget",
      )
    }
    let markup = "<od:r xmlns:od=\"\{word_uri}\">\{properties}\{inline_markup(part,limit-units)}</od:r>"
    units += markup.length()
    guard units <= limit else {
      @failure.reject(
        "limit-exceeded", "Field paragraph split exceeds source budget",
      )
    }
    output.write_string(markup)
  }
  let retained = offset == 1 || tail == "\ufffc"
  [
    {
      node: parent.id,
      offset: (if offset == 1 { node.end } else { node.start }) - parent.start,
      length: if retained {
        0
      } else {
        node.end - node.start
      },
      xml: output.to_string(),
    },
  ]
}
