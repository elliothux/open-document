///|
let math_uri = "http://schemas.openxmlformats.org/officeDocument/2006/math"

///|
fn WordTree::math_children(
  self : WordTree,
  id : Int,
  names : Array[String],
) -> Array[Int] raise @failure.Failure {
  let node = self.nodes[id]
  guard node.uri == math_uri &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    self.children[id].all(child => {
      self.nodes[child].uri == math_uri &&
      names.contains(self.nodes[child].name)
    }) else {
    @failure.reject(
      "unsupported-math", "Extended mathematical source requires support",
    )
  }
  self.children[id]
}

///|
fn WordTree::read_math_run(
  self : WordTree,
  id : Int,
  base : @layout.TextStyle,
) -> (String, @layout.TextStyle) raise @failure.Failure {
  let output = StringBuilder()
  let mut units = 0
  let run = id
  let node = self.nodes[run]
  let children = self.children[run]
  guard node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    children.all(id => {
      (
        self.nodes[id].uri == math_uri &&
        ["rPr", "t"].contains(self.nodes[id].name)
      ) ||
      (self.nodes[id].uri == word_uri && self.nodes[id].name == "rPr")
    }) else {
    @failure.reject(
      "unsupported-math", "Extended mathematical run requires support",
    )
  }
  let explicit_style = children.filter(id => self.nodes[id].uri == word_uri)
  guard explicit_style.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated mathematical font properties")
  }
  let current = explicit_style
    .get(0)
    .map(id => self.fraction_style(id, base))
    .unwrap_or(base)
  let properties = children.filter(id => {
    self.nodes[id].uri == math_uri && self.nodes[id].name == "rPr"
  })
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated mathematical run properties")
  }
  let upright = if properties is [properties] {
    let styles = self.math_children(properties, ["sty"])
    guard styles is [id] &&
      self.nodes[id].attributes.length() == 1 &&
      self.nodes[id].attribute("val", uri=math_uri) == Some("p") &&
      self.children[id].is_empty() &&
      self.nodes[id].text.is_empty() else {
      @failure.reject(
        "unsupported-math", "Mathematical run styling requires support",
      )
    }
    true
  } else {
    false
  }
  for child in children.filter(id => self.nodes[id].name == "t") {
    let node = self.nodes[child]
    guard self.children[child].is_empty() &&
      node.attributes.all(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" &&
        a.name == "space" &&
        a.value == "preserve"
      }) &&
      (
        upright ||
        node.text
        .iter()
        .all(ch => ch.is_ascii_digit() || " +-−=.,()".contains(ch.to_string()))
      ) else {
      @failure.reject(
        "unsupported-math", "Fraction requires plain upright or numeric run text",
      )
    }
    output.write_string(node.text)
    units += node.text.length()
    guard units <= 4096 else {
      @failure.reject("limit-exceeded", "Fraction text exceeds budget")
    }
  }
  (output.to_string(), current)
}

///|
fn Session::math_font(self : Session) -> String raise @failure.Failure {
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let fonts = tree.order.filter(id => {
      tree.nodes[id].uri == math_uri && tree.nodes[id].name == "mathFont"
    })
    guard fonts.length() <= 1 else {
      @failure.reject("unsupported-math", "Repeated mathematical font setting")
    }
    if fonts is [font] {
      guard tree.nodes[font].attribute("val", uri=math_uri) is Some(value) &&
        !value.is_empty() &&
        value.length() <= 255 else {
        @failure.reject("unsupported-math", "Invalid mathematical font setting")
      }
      return value
    }
  }
  "Cambria Math"
}
