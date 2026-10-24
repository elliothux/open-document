///|
fn WordTree::namespace_bindings(
  self : WordTree,
  id : Int,
) -> Map[String, String] {
  let ancestors = []
  for id = id; id >= 0; id = self.nodes[id].parent {
    ancestors.push(id)
  }
  let bindings : Map[String, String] = Map([])
  for id in ancestors.rev() {
    for (prefix, uri) in self.nodes[id].namespaces {
      bindings[prefix] = uri
    }
  }
  bindings
}

///|
fn WordTree::standalone_markup(
  self : WordTree,
  document : @xml.Document,
  id : Int,
) -> String raise @failure.Failure {
  let node = self.nodes[id]
  let attributes = StringBuilder()
  for prefix, uri in self.namespace_bindings(node.parent) {
    if !node.namespaces.iter().any(binding => binding.0 == prefix) {
      let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
      attributes.write_string(" \{name}=\"" + property_attribute(uri) + "\"")
    }
  }
  let source = document.source()
  let offset = node.opening_end - (if node.empty { 2 } else { 1 })
  source[node.start:offset].to_owned() +
  attributes.to_string() +
  source[offset:node.end].to_owned()
}

///|
fn WordTree::namespace_additions(
  self : WordTree,
  id : Int,
  parent : Int,
) -> String raise @failure.Failure {
  let node = self.nodes[id]
  let destination = self.namespace_bindings(parent)
  let attributes = StringBuilder()
  for prefix, uri in self.namespace_bindings(node.parent) {
    if destination.get(prefix) != Some(uri) &&
      !node.namespaces.any(binding => binding.0 == prefix) {
      let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
      attributes.write_string(" \{name}=\"\{property_attribute(uri)}\"")
    }
  }
  attributes.to_string()
}

///|
fn Session::prepare_empty(
  self : Session,
  paragraph : Int,
  text : String,
) -> PreparedEdit raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let p = tree.nodes[paragraph]
  let run = tree.paragraph_runs(paragraph).get(0)
  let parent = run.map(id => tree.nodes[id]).unwrap_or(p)
  let prefix = parent.qualified[:parent.qualified.length() - 1].to_owned()
  let t = if text.contains("\u2028") ||
    text.contains("\t") ||
    has_region_break(text) {
    inline_markup(text, self.opc.budget.entry_bytes.min(history_byte_limit / 2))
  } else {
    let escaped = @xml.escape_text(text)
    "<\{prefix}t xml:space=\"preserve\">\{escaped}</\{prefix}t>"
  }
  let content = if run is Some(_) {
    t
  } else {
    let properties = tree.empty_run_properties(document, paragraph)
    "<\{prefix}r>\{properties}\{t}</\{prefix}r>"
  }
  let (offset, length, fragment) = if parent.empty {
    (
      parent.opening_end - parent.start - 2,
      2,
      ">\{content}</\{parent.qualified}>",
    )
  } else {
    (parent.closing_start - parent.start, 0, content)
  }
  let (candidate, xml) = document.edit_source([
    { node: parent.id, offset, length, xml: fragment, },
  ])
  let position : Position = {
    paragraph,
    offset: text.length(),
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  {
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: position, focus: position, }),
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
    document: candidate,
    typing_text: None,
    join_group: false,
  }
}

///|
fn structure_opening(node : @xml.Node) -> String raise @failure.Failure {
  let output = StringBuilder()
  output.write_string("<" + node.qualified)
  for (prefix, uri) in node.namespaces {
    let value = @xml.escape_text(uri).split("\"").join("&quot;")
    let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
    output.write_string(" \{name}=\"\{value}\"")
  }
  output.write_string(">")
  output.to_string()
}

///|
fn WordTree::empty_run_properties(
  self : WordTree,
  document : @xml.Document,
  paragraph : Int,
) -> String raise @failure.Failure {
  guard self.child(paragraph, "pPr").bind(id => self.child(id, "rPr"))
    is Some(id) else {
    return ""
  }
  let node = self.nodes[id]
  let destination = self.namespace_bindings(paragraph)
  let attributes = StringBuilder()
  for prefix, uri in self.namespace_bindings(node.parent) {
    if destination.get(prefix) != Some(uri) &&
      !node.namespaces.iter().any(binding => binding.0 == prefix) {
      let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
      attributes.write_string(" \{name}=\"" + property_attribute(uri) + "\"")
    }
  }
  let source = document.source()
  let offset = node.opening_end - (if node.empty { 2 } else { 1 })
  source[node.start:offset].to_owned() +
  attributes.to_string() +
  source[offset:node.end].to_owned()
}

///|
fn WordTree::check_structure_paragraph(
  self : WordTree,
  paragraph : Int,
  running~ : Bool = false,
  sectionBoundary~ : Bool = false,
) -> Unit raise @failure.Failure {
  for id in [paragraph] + self.paragraph_runs(paragraph, running~) {
    let node = self.nodes[id]
    let allowed = if id == paragraph {
      ["rsidR", "rsidRDefault", "rsidP", "rsidRPr", "rsidDel"]
    } else {
      ["rsidR", "rsidRPr", "rsidDel"]
    }
    guard node.attributes
      .iter()
      .all(attribute => {
        attribute.uri == word_uri && allowed.contains(attribute.name)
      }) else {
      @failure.reject(
        "protected-content", "Unknown paragraph or run attributes prevent structural editing",
      )
    }
    if self.child(id, if id == paragraph { "pPr" } else { "rPr" })
      is Some(properties) {
      guard self.children[id]
        .filter(child => {
          self.nodes[child].name == self.nodes[properties].name &&
          self.nodes[child].uri == word_uri
        })
        .length() ==
        1 else {
        @failure.reject(
          "protected-content", "Duplicate paragraph or run properties",
        )
      }
      self.check_structure_properties(properties, sectionBoundary~)
    }
  }
}

///|
fn WordTree::check_structure_properties(
  self : WordTree,
  id : Int,
  sectionBoundary~ : Bool = false,
) -> Unit raise @failure.Failure {
  let excluded = if sectionBoundary {
    self
    .child(id, "sectPr")
    .map(id => [id, ..self.descendants(id)])
    .unwrap_or([])
  } else {
    []
  }
  for id in self.descendants(id) {
    if excluded.contains(id) {
      continue
    }
    let node = self.nodes[id]
    let children = match node.name {
      "pPr" =>
        [
          "pStyle",
          "rPr",
          "spacing",
          "ind",
          "jc",
          "pageBreakBefore",
          "autoSpaceDE",
          "autoSpaceDN",
          "tabs",
          "bidi",
          "numPr",
          "outlineLvl",
          "keepLines",
          "keepNext",
          "widowControl",
          "contextualSpacing",
          ..if sectionBoundary {
            ["sectPr"]
          } else {
            []
          },
        ]
      "tabs" => ["tab"]
      "numPr" => ["ilvl", "numId"]
      "rPr" =>
        [
          "rStyle", "rFonts", "sz", "color", "b", "i", "lang", "bCs", "iCs", "szCs",
          "u", "strike", "highlight", "vertAlign", "cs", "rtl", "spacing",
        ]
      _ => []
    }
    let names : Array[String] = []
    for child in self.children[id] {
      let name = self.nodes[child].name
      guard children.contains(name) &&
        (node.name == "tabs" || !names.contains(name)) else {
        @failure.reject(
          "protected-content",
          "Duplicate or misplaced structural property: " + name,
        )
      }
      names.push(name)
    }
    guard node.text.trim().is_empty() else {
      @failure.reject("protected-content", "Structural properties contain text")
    }
    let attributes = match node.name {
      "pPr" | "rPr" | "tabs" | "numPr" => []
      "tab" => ["pos", "val", "leader"]
      "pStyle"
      | "ilvl"
      | "numId"
      | "rStyle"
      | "jc"
      | "pageBreakBefore"
      | "keepLines"
      | "keepNext"
      | "widowControl"
      | "contextualSpacing"
      | "bidi"
      | "autoSpaceDE"
      | "autoSpaceDN"
      | "outlineLvl"
      | "sz"
      | "szCs"
      | "b"
      | "i"
      | "bCs"
      | "iCs" => ["val"]
      "cs" | "rtl" => ["val"]
      "color" => ["val", "themeColor", "themeTint", "themeShade"]
      "u" | "strike" | "highlight" | "vertAlign" => ["val"]
      "spacing" =>
        if self.nodes[node.parent].name == "rPr" {
          ["val"]
        } else {
          ["before", "after", "line", "lineRule"]
        }
      "ind" => ["left", "right", "firstLine", "hanging"]
      "rFonts" =>
        [
          "ascii", "hAnsi", "eastAsia", "cs", "asciiTheme", "hAnsiTheme", "eastAsiaTheme",
          "cstheme", "hint",
        ]
      "lang" => ["val", "eastAsia", "bidi"]
      _ =>
        @failure.reject(
          "protected-content",
          "Unknown structural property: " + node.qualified,
        )
    }
    guard node.uri == word_uri &&
      node.attributes
      .iter()
      .all(attribute => {
        attribute.uri == word_uri && attributes.contains(attribute.name)
      }) else {
      @failure.reject(
        "protected-content",
        "Unknown structural attribute: " + node.qualified,
      )
    }
    if ["autoSpaceDE", "autoSpaceDN", "bidi", "cs", "rtl"].contains(node.name) {
      guard self.valid_on_off_property(id) else {
        @failure.reject(
          "protected-content",
          "Invalid script spacing property: " + node.qualified,
        )
      }
    }
    if node.name == "tabs" && !self.valid_tabs(id) {
      @failure.reject("protected-content", "Unsupported tab stop properties")
    }
    if node.name == "numPr" && !self.valid_numbering_properties(id) {
      @failure.reject("protected-content", "Invalid numbering properties")
    }
    if node.name == "outlineLvl" {
      ignore(self.outline_level(node.parent))
    }
  }
}

///|
fn WordTree::continuation_properties(
  self : WordTree,
  document : @xml.Document,
  paragraph : Int,
) -> String raise @failure.Failure {
  let source = document.source()
  let properties = self.child(paragraph, "pPr")
  let page_break = "<od:pageBreakBefore xmlns:od=\"\{word_uri}\" od:val=\"0\"/>"
  if properties is Some(id) {
    self.check_structure_properties(id, sectionBoundary=true)
    let node = self.nodes[id]
    let fields = self.children[id].filter(child => {
      !["pageBreakBefore", "sectPr"].contains(self.nodes[child].name)
    })
    let markup = fields.map(child => {
      let field = self.nodes[child]
      source[field.start:field.end].to_owned()
    })
    let index = for index, child in fields {
      if self.nodes[child].name != "pStyle" {
        break index
      }
    } nobreak {
      fields.length()
    }
    markup.insert(index, page_break)
    structure_opening(node) + markup.join("") + "</\{node.qualified}>"
  } else {
    "<od:pPr xmlns:od=\"\{word_uri}\">\{page_break}</od:pPr>"
  }
}

///|
fn WordTree::check_editable_paragraph(
  self : WordTree,
  paragraph : Int,
  part~ : String,
  pictures~ : Bool = false,
  fields~ : Bool = false,
  math~ : Bool = false,
  notes~ : Bool = false,
) -> Unit raise @failure.Failure {
  guard self.nodes.contains(paragraph) &&
    self.nodes[paragraph].uri == word_uri &&
    self.nodes[paragraph].name == "p" else {
    @failure.reject(
      "invalid-position",
      "Unknown paragraph",
      part~,
      offset=paragraph,
    )
  }
  let parent = self.nodes[paragraph].parent
  guard !self.contents.contains(paragraph) else {
    @failure.reject(
      "protected-content",
      "Table of contents results require a table of contents update",
      part~,
      offset=paragraph,
    )
  }
  guard !self.field_spans.contains(paragraph) else {
    @failure.reject(
      "protected-content",
      "Cross-paragraph field results require field editing",
      part~,
      offset=paragraph,
    )
  }
  let in_body = parent >= 0 &&
    self.nodes[parent].uri == word_uri &&
    self.nodes[parent].name == "body"
  let in_cell = parent >= 0 &&
    self.nodes[parent].uri == word_uri &&
    self.nodes[parent].name == "tc" &&
    self.nodes[parent].parent >= 0 &&
    self.nodes[self.nodes[parent].parent].name == "tr" &&
    self.nodes[self.nodes[parent].parent].uri == word_uri
  let row = if in_cell { self.nodes[parent].parent } else { -1 }
  let table = if row >= 0 { self.nodes[row].parent } else { -1 }
  let body = if table >= 0 { self.nodes[table].parent } else { -1 }
  let supported_cell = in_cell &&
    table >= 0 &&
    body >= 0 &&
    self.nodes[table].uri == word_uri &&
    self.nodes[table].name == "tbl" &&
    self.nodes[body].uri == word_uri &&
    self.nodes[body].name == "body"
  let text_box = self.text_box_drawing(paragraph)
  guard in_body || supported_cell || text_box is Some(_) else {
    @failure.reject(
      "protected-content",
      "Paragraph is inside a protected container",
      part~,
      offset=paragraph,
    )
  }
  if text_box is Some(drawing) {
    guard !self.shape_locked(drawing, "noTextEdit") &&
      !self.shape_locked(drawing, "noSelect") else {
      @failure.reject("protected-content", "Text box text editing is locked")
    }
  }
  for id in self.descendants(paragraph) {
    let node = self.nodes[id]
    guard node.uri != word_uri ||
      (node.name != "pPrChange" && node.name != "rPrChange") else {
      @failure.reject(
        "protected-content",
        "Paragraph contains tracked properties",
        part~,
        offset=paragraph,
      )
    }
  }
  let runs : Array[Int] = []
  if fields {
    ignore(self.simple_page_fields(paragraph))
  }
  for child in self.children[paragraph] {
    let node = self.nodes[child]
    if math &&
      node.uri == math_uri &&
      ["oMath", "oMathPara"].contains(node.name) {
      continue
    }
    if fields && node.uri == word_uri && node.name == "fldSimple" {
      continue
    }
    if node.uri == word_uri && node.name == "pPr" {
      continue
    }
    if self.is_bookmark(child) {
      self.check_bookmark_marker(child)
      continue
    }
    if self.is_comment_marker(child) {
      self.check_comment_marker(child)
      continue
    }
    if node.uri == word_uri && node.name == "hyperlink" {
      self.check_hyperlink(child)
      runs.append(
        self.children[child].filter(id => {
          self.nodes[id].uri == word_uri && self.nodes[id].name == "r"
        }),
      )
      continue
    }
    guard node.uri == word_uri && node.name == "r" else {
      @failure.reject(
        "protected-content",
        "Paragraph contains protected markup: " + node.qualified,
        part~,
        offset=paragraph,
      )
    }
    runs.push(child)
  }
  for child in runs {
    for content in self.children[child] {
      let node = self.nodes[content]
      if note_reference(node) {
        guard notes &&
          self.nodes[node.parent].parent == paragraph &&
          self.children[content].is_empty() &&
          node.text.trim().is_empty() &&
          node.attributes.all(a => a.uri == word_uri && a.name == "id") else {
          @failure.reject(
            "protected-content", "This command does not support these note references",
          )
        }
        ignore(note_key(node.attribute("id", uri=word_uri).unwrap_or("")))
        continue
      }
      guard node.uri == word_uri &&
        (
          node.name == "rPr" ||
          node.name == "t" ||
          (pictures && node.name == "drawing") ||
          node.name == "br" ||
          node.name == "cr" ||
          node.name == "tab" ||
          node.name == "lastRenderedPageBreak" ||
          node.name == "commentReference"
        ) else {
        @failure.reject(
          "protected-content",
          "Run contains protected markup: " + node.qualified,
          part~,
          offset=paragraph,
        )
      }
      if node.name == "commentReference" {
        self.check_comment_marker(content)
      }
      if node.name == "br" || node.name == "cr" || node.name == "tab" {
        guard self.children[content].is_empty() &&
          node.text.trim().is_empty() &&
          ["textWrapping", "page", "column"].contains(
            node.attribute("type", uri=word_uri).unwrap_or("textWrapping"),
          ) &&
          node.attribute("clear", uri=word_uri).unwrap_or("none") == "none" &&
          node.attributes
          .iter()
          .all(attribute => {
            node.name == "br" &&
            attribute.uri == word_uri &&
            ["type", "clear"].contains(attribute.name)
          }) else {
          @failure.reject(
            "protected-content",
            "Unsupported inline break prevents editing",
            part~,
            offset=paragraph,
          )
        }
      }
      if node.name == "t" {
        guard self.children[content].is_empty() else {
          @failure.reject(
            "protected-content",
            "Text contains nested markup",
            part~,
            offset=paragraph,
          )
        }
      }
    }
  }
}
