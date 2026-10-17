///|
priv struct WordTree {
  source : String
  nodes : Map[Int, @xml.Node]
  order : Array[Int]
  children : Map[Int, Array[Int]]
}

///|
fn WordTree::new(document : @xml.Document) -> WordTree {
  let nodes : Map[Int, @xml.Node] = Map([])
  let order : Array[Int] = []
  let children : Map[Int, Array[Int]] = Map([])
  for node in document.nodes() {
    nodes[node.id] = node
    order.push(node.id)
    children[node.id] = []
  }
  for id in order {
    let node = nodes[id]
    if node.parent >= 0 {
      children[node.parent].push(id)
    }
  }
  { source: document.source(), nodes, order, children, }
}

///|
fn WordTree::descendants(self : WordTree, id : Int) -> Array[Int] {
  let stack = [id]
  let result : Array[Int] = []
  while stack.pop() is Some(item) {
    result.push(item)
    let children = self.children[item]
    for i = children.length() - 1; i >= 0; i = i - 1 {
      stack.push(children[i])
    }
  }
  result
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
  fonts : FontBindings
  size : Double
  color : String
  bold : Bool
  italic : Bool
  underline : Bool
  strike : Bool
  highlight : String
  vertAlign : String
} derive(Eq)

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
  inherited~ : Bool = false,
) -> RunStyle raise @failure.Failure {
  let fonts = font_bindings(tree, id, base.fonts, inherited)
  let family = font_family(fonts.slots, "ascii", base.family, themes)
  let size = tree
    .number(id, "sz", "val")
    .map(value => value / 2)
    .unwrap_or(base.size)
  let color = theme_text_color(tree, id, base.color, themes)
  {
    family,
    fonts,
    size,
    color,
    bold: tree.character_toggle(id, "b", base.bold, inherited),
    italic: tree.character_toggle(id, "i", base.italic, inherited),
    underline: match tree.value(id, "u") {
      None => if tree.child(id, "u") is Some(_) { true } else { base.underline }
      Some("none") => false
      Some("single") => true
      Some(_) => false
    },
    strike: tree.character_toggle(id, "strike", base.strike, inherited),
    highlight: match tree.value(id, "highlight") {
      None => base.highlight
      Some(value) => {
        ignore(highlight_color(value))
        value
      }
    },
    vertAlign: match tree.value(id, "vertAlign") {
      None => base.vertAlign
      Some(value) => {
        guard ["baseline", "superscript", "subscript"].contains(value) else {
          @failure.reject("invalid-style", "Invalid vertical alignment")
        }
        value
      }
    },
  }
}

///|
fn WordTree::character_toggle(
  self : WordTree,
  id : Int,
  name : String,
  fallback : Bool,
  inherited : Bool,
) -> Bool {
  match self.child(id, name) {
    None => fallback
    Some(item) => {
      let value = self.nodes[item]
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
    tabs: tree.paragraph_tabs(id, base.tabs),
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
    rtl: if tree.child(id, "bidi") is Some(item) {
      guard tree.valid_on_off_property(item) else {
        @failure.reject("protected-content", "Unsupported paragraph direction")
      }
      !["0", "false", "off"].contains(
        tree.nodes[item].attribute("val", uri=word_uri).unwrap_or("1"),
      )
    } else {
      base.rtl
    },
    widowControl: if tree.child(id, "widowControl") is Some(item) {
      guard tree.valid_on_off_property(item) else {
        @failure.reject(
          "protected-content", "Unsupported widow-control property",
        )
      }
      !["0", "false", "off"].contains(
        tree.nodes[item].attribute("val", uri=word_uri).unwrap_or("1"),
      )
    } else {
      base.widowControl
    },
    keepNext: if tree.child(id, "keepNext") is Some(item) {
      guard tree.valid_on_off_property(item) else {
        @failure.reject("protected-content", "Unsupported keep-next property")
      }
      !["0", "false", "off"].contains(
        tree.nodes[item].attribute("val", uri=word_uri).unwrap_or("1"),
      )
    } else {
      base.keepNext
    },
    keepLines: if tree.child(id, "keepLines") is Some(item) {
      guard tree.valid_on_off_property(item) else {
        @failure.reject("protected-content", "Unsupported keep-lines property")
      }
      !["0", "false", "off"].contains(
        tree.nodes[item].attribute("val", uri=word_uri).unwrap_or("1"),
      )
    } else {
      base.keepLines
    },
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
  let themes = self.theme_values()
  let defaults : RunStyle = {
    family: "Times New Roman",
    fonts: {
      slots: Map([]),
      hint: "default",
      language: "",
      complex: false,
      rtl: false,
      bold: false,
      italic: false,
      size: 11,
    },
    size: 11,
    color: "auto",
    bold: false,
    italic: false,
    underline: false,
    strike: false,
    highlight: "none",
    vertAlign: "baseline",
  }
  let paragraph : @layout.Paragraph = {
    id: -1,
    container: 0,
    nominalSize: defaults.size,
    defaultTab: self.default_tab(),
    tabs: [],
    decimalSymbol: self.decimal_symbol(),
    expandSoftBreak: self.expand_soft_break(),
    spans: [],
    before: 0,
    after: 0,
    line: @layout.Auto(288),
    left: 0,
    right: 0,
    first: 0,
    align: "left",
    pageBreakBefore: false,
    keepLines: false,
    keepNext: false,
    widowControl: true,
    rtl: false,
    marker: None,
    readOnlyReason: "",
  }
  let path = for rel in self.relationships() {
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
  let tree = WordTree::new(self.part_xml(path.target))
  guard tree.nodes[0].uri == word_uri && tree.nodes[0].name == "styles" else {
    @failure.reject("invalid-style", "Invalid styles root", part=path.target)
  }
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
    paragraph: {
      ..paragraph,
      readOnlyReason: diagnostics.get(0).unwrap_or(""),
    },
    default_paragraph,
    themes,
  }
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
