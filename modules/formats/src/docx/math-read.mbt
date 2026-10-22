///|
fn Session::math_base_style(
  self : Session,
  style : @layout.TextStyle,
) -> @layout.TextStyle raise @failure.Failure {
  {
    ..style,
    font: self.math_font(),
    script: "baseline",
    spacing: 0,
    underline: false,
    strike: false,
    highlight: "",
  }
}

///|
priv struct MathRead {
  base : @layout.TextStyle
  mut style : @layout.TextStyle?
  mut nodes : Int
  mut units : Int
}

///|
fn MathRead::node(self : MathRead, depth : Int) -> Unit raise @failure.Failure {
  self.nodes += 1
  guard depth <= 16 && self.nodes <= 256 else {
    @failure.reject("limit-exceeded", "Math exceeds depth 16 or 256 nodes")
  }
}

///|
fn MathRead::sequence(
  self : MathRead,
  tree : WordTree,
  id : Int,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  let children = tree.math_children(id, [
    "r", "f", "sSub", "sSup", "sSubSup", "rad",
  ])
  guard !children.is_empty() else {
    @failure.reject("unsupported-math", "Math argument is empty")
  }
  guard children.length() <= 256 else {
    @failure.reject("limit-exceeded", "Math row exceeds 256 children")
  }
  let terms : Array[@layout.MathExpression] = []
  let child_depth = if children.length() > 1 {
    self.node(depth)
    depth + 1
  } else {
    depth
  }
  for child in children {
    let term = self.term(tree, child, child_depth)
    match (terms.last(), term) {
      (Some(Text(before)), Text(after)) =>
        terms[terms.length() - 1] = Text(before + after)
      _ => terms.push(term)
    }
  }
  if terms is [term] {
    term
  } else {
    Row(ReadOnlyArray::from_array(terms))
  }
}

///|
fn MathRead::term(
  self : MathRead,
  tree : WordTree,
  id : Int,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  self.node(depth)
  let kind = tree.nodes[id].name
  if kind == "rad" {
    return self.radical(tree, id, depth)
  }
  if kind == "r" {
    let (text, current) = tree.read_math_run(id, self.base)
    self.units += text.length()
    guard self.units <= 4096 else {
      @failure.reject("limit-exceeded", "Math exceeds 4096 UTF-16 units")
    }
    guard self.style
      .map(style => {
        (style.font, style.size, style.color) ==
        (current.font, current.size, current.color)
      })
      .unwrap_or(true) else {
      @failure.reject(
        "unsupported-math", "Math requires uniform run formatting",
      )
    }
    self.style = Some(current)
    return Text(text)
  }
  let names = match kind {
    "f" => ["fPr", "num", "den"]
    "sSub" => ["sSubPr", "e", "sub"]
    "sSup" => ["sSupPr", "e", "sup"]
    _ => ["sSubSupPr", "e", "sub", "sup"]
  }
  let children = tree.math_children(id, names)
  let properties = children.filter(id => tree.nodes[id].name == kind + "Pr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated math properties")
  }
  if properties is [properties] {
    let types = tree.math_children(
      properties,
      if kind == "f" {
        ["type"]
      } else {
        []
      },
    )
    guard types.is_empty() ||
      (
        types is [id] &&
        tree.nodes[id].attributes.length() == 1 &&
        tree.nodes[id].attribute("val", uri=math_uri) == Some("bar") &&
        tree.children[id].is_empty() &&
        tree.nodes[id].text.is_empty()
      ) else {
      @failure.reject(
        "unsupported-math", "Only horizontal fractions are supported",
      )
    }
  }
  let arguments : Map[String, @layout.MathExpression] = Map([])
  for name in names.filter(name => !name.has_suffix("Pr")) {
    let items = children.filter(id => tree.nodes[id].name == name)
    guard items is [item] else {
      @failure.reject(
        "unsupported-math",
        "Math requires exactly one " + name + " argument",
      )
    }
    arguments[name] = self.sequence(tree, item, depth + 1)
  }
  if kind == "f" {
    Fraction(arguments["num"], arguments["den"])
  } else {
    Scripts(arguments["e"], arguments.get("sub"), arguments.get("sup"))
  }
}

///|
fn MathRead::radical(
  self : MathRead,
  tree : WordTree,
  id : Int,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  let children = tree.math_children(id, ["radPr", "deg", "e"])
  let properties = children.filter(id => tree.nodes[id].name == "radPr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated radical properties")
  }
  let mut hidden = false
  if properties is [properties] {
    let flags = tree.math_children(properties, ["degHide"])
    guard flags.length() <= 1 else {
      @failure.reject("unsupported-math", "Repeated radical degree visibility")
    }
    if flags is [flag] {
      let node = tree.nodes[flag]
      let value = node.attribute("val", uri=math_uri).unwrap_or("1")
      guard tree.children[flag].is_empty() &&
        node.text.is_empty() &&
        node.attributes.length() <= 1 &&
        node.attributes.all(a => a.uri == math_uri && a.name == "val") &&
        ["1", "true", "on", "0", "false", "off"].contains(value) else {
        @failure.reject("unsupported-math", "Invalid radical degree visibility")
      }
      hidden = ["1", "true", "on"].contains(value)
    }
  }
  let degree = children.filter(id => tree.nodes[id].name == "deg")
  let base = children.filter(id => tree.nodes[id].name == "e")
  guard degree is [degree] && base is [base] else {
    @failure.reject(
      "unsupported-math", "Radical requires exactly one degree and base",
    )
  }
  let degree = if hidden {
    ignore(tree.math_children(degree, []))
    None
  } else {
    Some(self.sequence(tree, degree, depth + 1))
  }
  Root(degree, self.sequence(tree, base, depth + 1))
}

///|
fn Session::read_inline_math(
  self : Session,
  tree : WordTree,
  id : Int,
  style : @layout.TextStyle,
) -> @layout.DrawingFrame raise @failure.Failure {
  let reader : MathRead = {
    base: self.math_base_style(style),
    style: None,
    nodes: 0,
    units: 0,
  }
  let expression = reader.sequence(tree, id, 0)
  let frame : @layout.DrawingFrame = {
    width: 0,
    height: 0,
    anchor: None,
    content: Math(
      @layout.MathFormula::new(expression, reader.style.unwrap_or(reader.base)),
    ),
  }
  frame.validate()
  frame
}
