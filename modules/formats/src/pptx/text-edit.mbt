///|
fn source_xml(source : Ref) -> String {
  source.tree.document.source()[source.node.start:source.node.end].to_owned()
}

///|
fn run_piece(
  run : TextRun,
  start : Int,
  end : Int,
) -> String raise @failure.Failure {
  guard start < end && run.source is Some(source) else { return "" }
  if start == 0 && end == run.text.length() {
    return source_xml(source)
  }
  guard source.node.name == "r" && source.child("t") is Some(text) else {
    @failure.reject("protected-content", "Cannot split a protected text atom")
  }
  let xml = source.tree.document.source()
  xml[source.node.start:text.node.opening_end].to_owned() +
  @xml.escape_text(run.text[start:end].to_owned()) +
  xml[text.node.closing_start:source.node.end].to_owned()
}

///|
fn paragraph_piece(
  paragraph : TextParagraph,
  start : Int,
  end : Int,
) -> String raise @failure.Failure {
  let output = StringBuilder()
  let mut offset = 0
  for run in paragraph.runs {
    let a = start.max(offset) - offset
    let b = end.min(offset + run.text.length()) - offset
    if a < b {
      output.write_string(run_piece(run, a, b))
    }
    offset += run.text.length()
  }
  output.to_string()
}

///|
fn paragraph_location(
  object : Object,
  position : Int,
) -> (Int, Int) raise @failure.Failure {
  let mut offset = 0
  for index, paragraph in object.paragraphs {
    let length = paragraph.runs
      .iter()
      .fold(init=0, (sum, run) => sum + run.text.length())
    if position <= offset + length {
      return (index, position - offset)
    }
    offset += length + 1
  }
  @failure.reject("invalid-position", "Position exceeds text frame")
}

///|
fn generated_text(
  text : String,
  prefix : String,
  properties : String,
) -> String raise @failure.Failure {
  let count = text.split("\u2028").count().to_int64()
  guard count *
    (properties.length().to_int64() + prefix.length().to_int64() * 5 + 80) +
    text.length().to_int64() * 6 <=
    2097152L else {
    @failure.reject(
      "limit-exceeded", "Generated text source exceeds history budget",
    )
  }
  let parts : Array[String] = []
  for part in text.split("\u2028") {
    parts.push(
      "<\{prefix}r>\{properties}<\{prefix}t xml:space=\"preserve\">\{@xml.escape_text(part.to_owned())}</\{prefix}t></\{prefix}r>",
    )
  }
  parts.join("<\{prefix}br/>")
}

///|
fn replacement_properties(
  paragraph : TextParagraph,
  at : Int,
  leading~ : Bool = false,
) -> String raise @failure.Failure {
  let (index, _) = caret_run(paragraph, at, leading~)
  let run = paragraph.runs[index]
  let properties = run.source.bind(source => source.child("rPr"))
  if properties is Some(properties) {
    properties.tree.standalone_markup(
      properties.tree.document,
      properties.node.id,
    )
  } else if run.source is None &&
    paragraph.source.child("endParaRPr") is Some(properties) {
    let xml = properties.tree.standalone_markup(
      properties.tree.document,
      properties.node.id,
    )
    let old = properties.node.qualified
    let name = old[:old.length() - 10].to_owned() + "rPr"
    xml
    .replace(old="<" + old, new="<" + name)
    .replace(old="</" + old + ">", new="</" + name + ">")
  } else {
    ""
  }
}

///|
fn text_changes(
  object : Object,
  selection : Selection,
  text : String,
) -> (Array[@xml.SourceChange], Selection) raise @failure.Failure {
  guard @xml.valid_text(text) && text.length() <= 32767 else {
    @failure.reject("invalid-text", "Invalid or excessive text input")
  }
  let a = selection.anchor.min(selection.focus)
  let b = selection.anchor.max(selection.focus)
  let original = object.text()
  let boundaries = @layout.grapheme_boundaries(original)
  guard boundaries.contains(a) && boundaries.contains(b) else {
    @failure.reject("invalid-position", "Edit must use grapheme boundaries")
  }
  let updated = original[:a].to_owned() + text + original[b:].to_owned()
  guard updated.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Text frame exceeds budget")
  }
  let focus = @layout.grapheme_boundaries(updated)
    .iter()
    .find_first(offset => offset >= a + text.length())
    .unwrap_or(updated.length())
  let after = { ..selection, anchor: focus, focus, }
  if updated == original {
    return ([], after)
  }
  let (first, start) = paragraph_location(object, a)
  let (last, end) = paragraph_location(object, b)
  let initial = object.paragraphs[first]
  let ending_paragraph = object.paragraphs[last]
  guard initial.source.node.parent == ending_paragraph.source.node.parent else {
    @failure.reject("protected-content", "Text replacement crosses table cells")
  }
  let prefix = initial.source.node.qualified[:initial.source.node.qualified.length() -
  1].to_owned()
  let xml = initial.source.tree.document.source()
  let opening = if initial.source.node.empty {
    xml[initial.source.node.start:initial.source.node.opening_end - 2].to_owned() +
    ">"
  } else {
    xml[initial.source.node.start:initial.source.node.opening_end].to_owned()
  }
  let ppr = initial.source.child("pPr").map(source_xml).unwrap_or("")
  let ending = ending_paragraph.source
    .child("endParaRPr")
    .map(source_xml)
    .unwrap_or("")
  let template = replacement_properties(initial, start, leading=a != b)
  let before = paragraph_piece(initial, 0, start)
  let tail = paragraph_piece(
    ending_paragraph,
    end,
    ending_paragraph.runs
    .iter()
    .fold(init=0, (sum, run) => sum + run.text.length()),
  )
  let parts = text.split("\n").map(part => part.to_owned()).collect()
  let replacement = StringBuilder()
  for index, part in parts {
    replacement.write_string(opening)
    replacement.write_string(ppr)
    if index == 0 {
      replacement.write_string(before)
    }
    replacement.write_string(generated_text(part, prefix, template))
    if index == parts.length() - 1 {
      replacement.write_string(tail)
    }
    replacement.write_string(ending)
    replacement <+ "</\{initial.source.node.qualified}>"
  }
  let parent = initial.source.tree.nodes[initial.source.node.parent]
  (
    [
      {
        node: parent.id,
        offset: initial.source.node.start - parent.start,
        length: ending_paragraph.source.node.end - initial.source.node.start,
        xml: replacement.to_string(),
      },
    ],
    after,
  )
}

///|
pub fn Session::replace(
  self : Session,
  revision : Int,
  text : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  candidate_id~ : Int? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let object = self.editable(true)
  let candidate = candidate_id.map(id => self.gesture(revision, id))
  if candidate is Some(candidate) {
    guard candidate.kind == "text" else {
      @failure.reject("invalid-operation", "Not a text composition")
    }
  } else {
    self.check_idle()
  }
  if candidate is Some(_) && (text.contains("\n") || text.contains("\u2028")) {
    @failure.reject(
      "invalid-operation", "Composition cannot contain line breaks",
    )
  }
  let (changes, after) = if candidate is Some(_) && text.is_empty() {
    ([], self.selection)
  } else {
    text_changes(object, self.selection, text)
  }
  let original = self.slides[self.index(self.selection.slide)]
  let prepared = if changes.is_empty() {
    None
  } else {
    Some(self.prepare_fitted(original, changes, [object.id], probe, profile))
  }
  if candidate is Some(candidate) {
    self.candidate = Some({
      ..candidate,
      selection: after,
      slide: prepared.map(item => item.0).unwrap_or(original),
      edit: prepared.map(item => item.1),
    })
    self.view = None
  } else if prepared is Some((slide, edit)) {
    self.commit(slide, edit, after)
  } else {
    self.selection = after
  }
  self.query()
}

///|
pub fn Session::delete(
  self : Session,
  revision : Int,
  backward : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let object = self.editable(true)
  let old = self.selection
  let mut target = old
  if old.anchor == old.focus {
    let boundaries = @layout.grapheme_boundaries(object.text())
    let index = boundaries.search(old.focus).unwrap()
    let next = if backward { index - 1 } else { index + 1 }
    if next < 0 || next >= boundaries.length() {
      return self.query()
    }
    target = { ..old, anchor: boundaries[next], }
  }
  let (changes, after) = text_changes(object, target, "")
  if !changes.is_empty() {
    let (slide, edit) = self.prepare_fitted(
      self.slides[self.index(old.slide)],
      changes,
      [object.id],
      probe,
      profile,
    )
    self.commit(slide, edit, after)
  }
  self.query()
}

///|
pub fn Session::copy(
  self : Session,
  revision : Int,
) -> String raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard self.selection.mode == "text" else {
    @failure.reject("invalid-operation", "Plain text copy requires text mode")
  }
  let text = self.current().object(self.selection.object).text()
  text[self.selection.anchor.min(self.selection.focus):self.selection.anchor.max(
    self.selection.focus,
  )]
  .to_owned()
  .replace_all(old="\u2028", new="\n")
}
