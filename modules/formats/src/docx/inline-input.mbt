///|
fn has_region_break(text : String) -> Bool {
  text.contains("\u000b") || text.contains("\u000c")
}

///|
fn valid_inline_input(text : String) -> Bool {
  @xml.valid_text(
    text.replace_all(old="\u000b", new="").replace_all(old="\u000c", new=""),
  ) &&
  !text.contains("\r")
}

///|
fn WordTree::check_region_break_input(
  self : WordTree,
  paragraph : Int,
  text : String,
) -> Unit raise @failure.Failure {
  if !has_region_break(text) {
    return
  }
  let node = self.nodes
    .get(paragraph)
    .unwrap_or_error(
      @failure.Failure(
        code="invalid-position",
        part="",
        offset=paragraph,
        message="Unknown paragraph",
      ),
    )
  guard self.nodes.get(node.parent) is Some(parent) &&
    parent.uri == word_uri &&
    ["body", "tc"].contains(parent.name) else {
    @failure.reject(
      "protected-content", "Page or column break insertion requires a body or table-cell paragraph",
    )
  }
}

///|
fn inline_content(
  text : String,
  opening : String,
  closing : String,
  limit : Int,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  let part = StringBuilder()
  let mut units = 0
  for ch in text {
    if ch == '\u2028' || ch == '\t' || ch == '\u000b' || ch == '\u000c' {
      let escaped = @xml.escape_text(part.to_string())
      part.reset()
      let tag = if ch == '\t' { "tab" } else { "br" }
      let kind = match ch {
        '\u000b' => " od:type=\"column\""
        '\u000c' => " od:type=\"page\""
        _ => ""
      }
      let frame = closing +
        "<od:\{tag} xmlns:od=\"\{word_uri}\"\{kind}/>" +
        opening
      guard escaped.length() + frame.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Inline source fragment exceeds budget",
        )
      }
      out.write_string(escaped)
      out.write_string(frame)
      units += escaped.length() + frame.length()
    } else {
      part.write_char(ch)
    }
  }
  let escaped = @xml.escape_text(part.to_string())
  guard escaped.length() <= limit - units else {
    @failure.reject("limit-exceeded", "Inline source fragment exceeds budget")
  }
  out.write_string(escaped)
  out.to_string()
}

///|
fn inline_markup(text : String, limit : Int) -> String raise @failure.Failure {
  let opening = "<od:t xmlns:od=\"\{word_uri}\" xml:space=\"preserve\">"
  let closing = "</od:t>"
  let content = inline_content(text, opening, closing, limit)
  guard opening.length() + closing.length() <= limit - content.length() else {
    @failure.reject("limit-exceeded", "Inline source fragment exceeds budget")
  }
  opening + content + closing
}

///|
fn Session::edit_inline_text(
  self : Session,
  document : @xml.Document,
  replacements : Map[Int, String],
  source~ : Array[@xml.SourceChange] = [],
  object_offsets~ : Map[Int, Int] = Map([]),
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let plain : Map[Int, String] = Map([])
  let changes = source.copy()
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let original = document.source()
  let tree = WordTree::new(document)
  let mut units = 0
  for id, text in replacements {
    let node = document.node(id)
    if ["fldSimple", "oMath"].contains(node.name) {
      let items = paragraph_object_text_changes(
        tree,
        document,
        id,
        text,
        object_offsets.get(id),
        limit - units,
      )
      for item in items {
        units += item.xml.length()
        guard units <= limit else {
          @failure.reject("limit-exceeded", "Field text source exceeds budget")
        }
        changes.push(item)
      }
      continue
    }
    let paragraph = tree.run_paragraph(node.parent)
    self.check_text_box_paragraph(tree, paragraph)
    tree.check_region_break_input(paragraph, text)
    if node.name == "drawing" {
      let items = self.drawing_text_changes(
        tree,
        id,
        text,
        object_offsets.get(id),
        limit - units,
      )
      for item in items {
        units += item.xml.length()
        guard units <= limit else {
          @failure.reject(
            "limit-exceeded", "Picture text source exceeds budget",
          )
        }
        changes.push(item)
      }
      continue
    }
    if node.name == "t" &&
      !text.contains("\u2028") &&
      !text.contains("\t") &&
      !has_region_break(text) {
      plain[id] = text
      continue
    }
    tree.check_editable_paragraph(
      paragraph,
      part=self.main,
      pictures=true,
      fields=true,
      math=true,
    )
    self.check_native_drawings(tree, paragraph)
    guard node.attributes
      .iter()
      .all(attribute => {
        (
          node.name == "t" &&
          attribute.uri == "http://www.w3.org/XML/1998/namespace" &&
          attribute.name == "space"
        ) ||
        (
          node.name == "br" &&
          attribute.uri == word_uri &&
          ["type", "clear"].contains(attribute.name)
        )
      }) &&
      !original[node.start:node.end].contains("<!--") &&
      !original[node.start:node.end].contains("<?") else {
      @failure.reject(
        "protected-content", "Unknown inline markup prevents replacement",
      )
    }
    let xml = inline_markup(text, limit - units)
    units += xml.length()
    let parent = document.node(node.parent)
    changes.push({
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml,
    })
  }
  document.edit_text(plain, source=changes)
}

///|
fn WordTree::split_control_input(
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
  let source = document.source()
  guard !source[node.start:node.end].contains("<!--") &&
    !source[node.start:node.end].contains("<?") else {
    @failure.reject(
      "protected-content", "Unknown inline markup prevents paragraph split",
    )
  }
  let properties = self
    .child(run.id, "rPr")
    .map(id => {
      let node = self.nodes[id]
      source[node.start:node.end].to_owned()
    })
    .unwrap_or("")
  let (link_opening, link_closing) = self.hyperlink_frame(document, run.id)
  let frame = "</\{run.qualified}>\{link_closing}</\{p.qualified}>" +
    structure_opening(p) +
    self.continuation_properties(document, paragraph) +
    link_opening +
    structure_opening(run) +
    properties
  guard frame.length().to_int64() * (parts.length() - 1).to_int64() <=
    limit.to_int64() else {
    @failure.reject(
      "limit-exceeded", "Paragraph source fragment exceeds budget",
    )
  }
  let out = StringBuilder()
  let mut units = 0
  for i, part in parts {
    if i > 0 {
      out.write_string(frame)
      units += frame.length()
    }
    let text = (if i == 0 { inline_text(node)[:offset].to_owned() } else { "" }) +
      part +
      (if i + 1 == parts.length() { tail } else { "" })
    let xml = inline_markup(text, limit - units)
    out.write_string(xml)
    units += xml.length()
  }
  [
    {
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: out.to_string(),
    },
  ]
}
