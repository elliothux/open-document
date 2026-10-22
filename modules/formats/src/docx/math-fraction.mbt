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
fn WordTree::fraction_text(
  self : WordTree,
  id : Int,
) -> String raise @failure.Failure {
  let output = StringBuilder()
  let mut units = 0
  for run in self.math_children(id, ["r"]) {
    let children = self.math_children(run, ["rPr", "t"])
    let properties = children.filter(id => self.nodes[id].name == "rPr")
    guard properties.length() <= 1 else {
      @failure.reject(
        "unsupported-math", "Repeated mathematical run properties",
      )
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
          .all(ch => {
            ch.is_ascii_digit() || " +-−=.,()".contains(ch.to_string())
          })
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
  }
  output.to_string()
}

///|
fn Session::fraction_font(self : Session) -> String raise @failure.Failure {
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

///|
fn Session::read_math_fraction(
  self : Session,
  tree : WordTree,
  id : Int,
  style : @layout.TextStyle,
) -> @layout.DrawingFrame raise @failure.Failure {
  let children = tree.math_children(id, ["f"])
  guard children is [fraction] else {
    @failure.reject(
      "unsupported-math", "Mathematical expression requires fraction support",
    )
  }
  let children = tree.math_children(fraction, ["fPr", "num", "den"])
  let properties = children.filter(id => tree.nodes[id].name == "fPr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated fraction properties")
  }
  if properties is [properties] {
    let types = tree.math_children(properties, ["type"])
    guard types.is_empty() ||
      (
        types is [id] &&
        tree.nodes[id].attributes.length() == 1 &&
        tree.nodes[id].attribute("val", uri=math_uri) == Some("bar") &&
        tree.children[id].is_empty() &&
        tree.nodes[id].text.is_empty()
      ) else {
      @failure.reject(
        "unsupported-math", "Only a plain horizontal fraction is supported",
      )
    }
  }
  let num = children.filter(id => tree.nodes[id].name == "num")
  let den = children.filter(id => tree.nodes[id].name == "den")
  guard num is [num] && den is [den] else {
    @failure.reject(
      "unsupported-math", "Fraction requires one numerator and denominator",
    )
  }
  let frame : @layout.DrawingFrame = {
    width: 0,
    height: 0,
    anchor: None,
    content: Fraction(
      @layout.MathFraction::new(
        tree.fraction_text(num),
        tree.fraction_text(den),
        {
          ..style,
          font: self.fraction_font(),
          script: "baseline",
          spacing: 0,
          underline: false,
          strike: false,
          highlight: "",
        },
      ),
    ),
  }
  frame.validate()
  frame
}
