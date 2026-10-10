///|
priv struct WordTree {
  nodes : ReadOnlyArray[@xml.Node]
  children : Array[Array[Int]]
}

///|
fn WordTree::new(document : @xml.Document) -> WordTree {
  let nodes = document.nodes()
  let children = Array::makei(nodes.length(), _ => [])
  for id, node in nodes {
    if node.parent >= 0 {
      children[node.parent].push(id)
    }
  }
  { nodes, children, }
}

///|
fn WordTree::child(self : WordTree, parent : Int, name : String) -> Int? {
  for id in self.children[parent] {
    if self.nodes[id].uri == word_uri && self.nodes[id].name == name {
      return Some(id)
    }
  }
  None
}

///|
fn WordTree::value(self : WordTree, parent : Int, name : String) -> String? {
  self
  .child(parent, name)
  .bind(id => self.nodes[id].attribute("val", uri=word_uri))
}

///|
fn WordTree::number(
  self : WordTree,
  parent : Int,
  name : String,
  attribute : String,
) -> Double? raise @failure.Failure {
  match
    self
    .child(parent, name)
    .bind(id => self.nodes[id].attribute(attribute, uri=word_uri)) {
    None => None
    Some(value) => {
      let number = @string.parse_int(value[:]).to_double() catch {
        _ =>
          @failure.reject(
            "invalid-style",
            "Invalid numeric Word property: " + name,
          )
      }
      Some(number)
    }
  }
}

///|
priv struct RunStyle {
  family : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
}

///|
fn RunStyle::key(self : RunStyle) -> String {
  self.family +
  (if self.bold { "|bold" } else { "" }) +
  (if self.italic { "|italic" } else { "" })
}

///|
fn RunStyle::text_color(
  self : RunStyle,
  background : String,
) -> String raise @failure.Failure {
  if self.color != "auto" {
    return self.color
  }
  fn channel(
    background : String,
    offset : Int,
  ) -> Double raise @failure.Failure {
    let value = (@string.parse_int(background[offset:offset + 2], base=16).to_double() /
    255) catch {
      _ =>
        @failure.reject("invalid-style", "Invalid automatic color background")
    }
    if value <= 0.04045 {
      value / 12.92
    } else {
      @math.pow((value + 0.055) / 1.055, 2.4)
    }
  }
  let luminance = channel(background, 0) * 0.2126 +
    channel(background, 2) * 0.7152 +
    channel(background, 4) * 0.0722
  // Automatic text uses the fixed reference profile's dark-background cutoff.
  if luminance * 255 < 88 {
    "ffffff"
  } else {
    "000000"
  }
}

///|
fn run_properties(
  tree : WordTree,
  id : Int,
  base : RunStyle,
  themes : Map[String, String],
  inherited? : Bool = false,
) -> RunStyle raise @failure.Failure {
  let mut family = base.family
  if tree.child(id, "rFonts") is Some(fonts) {
    if tree.nodes[fonts].attribute("asciiTheme", uri=word_uri) is Some(theme) {
      guard themes.get(theme) is Some(value) else {
        @failure.reject("invalid-style", "Missing theme font: " + theme)
      }
      family = value
    } else {
      family = tree.nodes[fonts]
        .attribute("ascii", uri=word_uri)
        .unwrap_or(family)
    }
  }
  let size = tree
    .number(id, "sz", "val")
    .map(value => value / 2)
    .unwrap_or(base.size)
  let color = tree.value(id, "color").unwrap_or(base.color)
  guard color == "auto" ||
    (color.length() == 6 && color.iter().all(ch => ch.is_ascii_hexdigit())) else {
    @failure.reject("invalid-style", "Invalid text color")
  }
  fn toggle(
    tree : WordTree,
    id : Int,
    name : String,
    fallback : Bool,
    inherited : Bool,
  ) -> Bool {
    match tree.child(id, name) {
      None => fallback
      Some(item) => {
        let value = tree.nodes[item]
          .attribute("val", uri=word_uri)
          .unwrap_or("true")
        let enabled = value != "0" && value != "false" && value != "off"
        if inherited {
          if enabled {
            !fallback
          } else {
            fallback
          }
        } else {
          enabled
        }
      }
    }
  }
  {
    family,
    size,
    color,
    bold: toggle(tree, id, "b", base.bold, inherited),
    italic: toggle(tree, id, "i", base.italic, inherited),
  }
}

///|
fn paragraph_properties(
  tree : WordTree,
  id : Int,
  base : @layout.Paragraph,
) -> @layout.Paragraph raise @failure.Failure {
  let (inherited_rule, inherited_value) = match base.line {
    @layout.Auto(value) => ("auto", value)
    @layout.Exact(value) => ("exact", value)
    @layout.AtLeast(value) => ("atLeast", value)
  }
  let rule = tree
    .child(id, "spacing")
    .bind(node => tree.nodes[node].attribute("lineRule", uri=word_uri))
    .unwrap_or(inherited_rule)
  let value = tree.number(id, "spacing", "line").unwrap_or(inherited_value)
  let line = match rule {
    "auto" => @layout.Auto(value)
    "exact" => @layout.Exact(value)
    "atLeast" => @layout.AtLeast(value)
    _ => @failure.reject("invalid-style", "Unknown line spacing rule")
  }
  {
    ..base,
    before: tree
    .number(id, "spacing", "before")
    .map(value => value / 20)
    .unwrap_or(base.before),
    after: tree
    .number(id, "spacing", "after")
    .map(value => value / 20)
    .unwrap_or(base.after),
    line,
    left: tree
    .number(id, "ind", "left")
    .map(value => value / 20)
    .unwrap_or(base.left),
    right: tree
    .number(id, "ind", "right")
    .map(value => value / 20)
    .unwrap_or(base.right),
    first: tree
    .number(id, "ind", "firstLine")
    .map(value => value / 20)
    .unwrap_or(
      tree
      .number(id, "ind", "hanging")
      .map(value => -value / 20)
      .unwrap_or(base.first),
    ),
    align: tree.value(id, "jc").unwrap_or(base.align),
    pageBreakBefore: if tree.child(id, "pageBreakBefore") is Some(item) {
      match tree.nodes[item].attribute("val", uri=word_uri) {
        Some("0" | "false" | "off") => false
        _ => true
      }
    } else {
      base.pageBreakBefore
    },
  }
}

///|
priv struct Styles {
  tree : WordTree?
  part : String
  ids : Map[String, Int]
  defaults : RunStyle
  paragraph : @layout.Paragraph
  default_paragraph : String?
  themes : Map[String, String]
}

///|
fn Session::styles(
  self : Session,
  diagnostics : Array[String],
) -> Styles raise @failure.Failure {
  let themes = self.theme_fonts()
  let defaults : RunStyle = {
    family: "Times New Roman",
    size: 11,
    color: "auto",
    bold: false,
    italic: false,
  }
  let paragraph : @layout.Paragraph = {
    id: -1,
    spans: [],
    before: 0,
    after: 0,
    line: @layout.Auto(288),
    left: 0,
    right: 0,
    first: 0,
    align: "left",
    pageBreakBefore: false,
  }
  let path = for rel in self.opc.relationships() {
    if rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" {
      break Some(rel)
    }
  } nobreak {
    None
  }
  guard path is Some(path) else {
    return {
      tree: None,
      part: "",
      ids: Map([]),
      defaults,
      paragraph,
      default_paragraph: None,
      themes,
    }
  }
  guard !path.external else {
    @failure.reject("unsupported-layout", "External styles are unsupported")
  }
  let tree = WordTree::new(self.opc.xml(path.target))
  let ids : Map[String, Int] = Map([])
  let mut default_paragraph = None
  for id in tree.children[0] {
    let node = tree.nodes[id]
    if node.uri == word_uri &&
      node.name == "style" &&
      node.attribute("styleId", uri=word_uri) is Some(key) {
      guard ids.get(key) is None else {
        @failure.reject("invalid-style", "Duplicate style ID")
      }
      ids[key] = id
      if node.attribute("default", uri=word_uri) is Some("1" | "true") &&
        node.attribute("type", uri=word_uri) == Some("paragraph") {
        default_paragraph = Some(key)
      }
    }
  }
  let mut defaults = defaults
  let mut paragraph = paragraph
  if tree.child(0, "docDefaults") is Some(doc_defaults) {
    if tree.child(doc_defaults, "rPrDefault").bind(id => tree.child(id, "rPr"))
      is Some(id) {
      defaults = run_properties(tree, id, defaults, themes)
      tree.diagnose_properties(id, path.target, diagnostics)
    }
    if tree.child(doc_defaults, "pPrDefault").bind(id => tree.child(id, "pPr"))
      is Some(id) {
      paragraph = paragraph_properties(tree, id, paragraph)
      tree.diagnose_properties(id, path.target, diagnostics)
    }
  }
  {
    tree: Some(tree),
    part: path.target,
    ids,
    defaults,
    paragraph,
    default_paragraph,
    themes,
  }
}

///|
fn Session::theme_fonts(
  self : Session,
) -> Map[String, String] raise @failure.Failure {
  let result : Map[String, String] = Map([])
  for rel in self.opc.relationships() {
    if rel.owner != self.main ||
      rel.kind !=
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" {
      continue
    }
    guard !rel.external else {
      @failure.reject("unsupported-layout", "External themes are unsupported")
    }
    let tree = WordTree::new(self.opc.xml(rel.target))
    for id, node in tree.nodes {
      if node.uri == "http://schemas.openxmlformats.org/drawingml/2006/main" &&
        node.name == "latin" &&
        node.parent >= 0 &&
        node.attribute("typeface") is Some(family) {
        let kind = tree.nodes[node.parent].name
        if kind == "majorFont" || kind == "minorFont" {
          let prefix = if kind == "majorFont" { "major" } else { "minor" }
          result[prefix + "Ascii"] = family
          result[prefix + "HAnsi"] = family
        }
      }
      ignore(id)
    }
  }
  result
}

///|
fn Styles::chain(
  self : Styles,
  key : String,
  diagnostics : Array[String],
) -> Array[Int] raise @failure.Failure {
  let result = []
  let mut current = Some(key)
  while current is Some(key) {
    guard self.tree is Some(tree) && self.ids.get(key) is Some(id) else {
      @failure.reject("invalid-style", "Unknown style: " + key)
    }
    guard result.length() < 64 && !result.contains(id) else {
      @failure.reject("invalid-style", "Cyclic or over-deep style inheritance")
    }
    result.push(id)
    for child in tree.children[id] {
      tree.diagnose_properties(child, self.part, diagnostics)
      if tree.nodes[child].name == "tblStylePr" {
        let message = "unsupported-layout:" +
          self.part +
          ":" +
          tree.nodes[child].qualified
        if !diagnostics.contains(message) {
          diagnostics.push(message)
        }
      }
    }
    current = tree.value(id, "basedOn")
  }
  result.rev()
}
