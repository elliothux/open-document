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
fn Session::read_inline_math(
  self : Session,
  tree : WordTree,
  id : Int,
  style : @layout.TextStyle,
) -> @layout.DrawingFrame raise @failure.Failure {
  let children = tree.math_children(id, ["f", "sSub", "sSup", "sSubSup"])
  guard children is [expression] else {
    @failure.reject(
      "unsupported-math", "Inline math requires one supported expression",
    )
  }
  if tree.nodes[expression].name == "f" {
    return self.read_math_fraction(tree, id, style)
  }
  let kind = tree.nodes[expression].name
  let names = match kind {
    "sSub" => ["e", "sub", "sSubPr"]
    "sSup" => ["e", "sup", "sSupPr"]
    _ => ["e", "sub", "sup", "sSubSupPr"]
  }
  let children = tree.math_children(expression, names)
  let properties = children.filter(id => tree.nodes[id].name == kind + "Pr")
  guard properties.length() <= 1 else {
    @failure.reject(
      "unsupported-math", "Repeated mathematical script properties",
    )
  }
  if properties is [properties] {
    ignore(tree.math_children(properties, []))
  }
  let base = self.math_base_style(style)
  let arguments : Map[String, (String, @layout.TextStyle)] = Map([])
  for name in ["e", "sub", "sup"] {
    let items = children.filter(id => tree.nodes[id].name == name)
    if names.contains(name) {
      guard items is [item] else {
        @failure.reject(
          "unsupported-math",
          "Script requires exactly one " + name + " argument",
        )
      }
      arguments[name] = tree.math_run_text(item, base)
    }
  }
  let (text, style) = arguments["e"]
  guard arguments
    .values()
    .all(value => {
      (value.1.font, value.1.size, value.1.color) ==
      (style.font, style.size, style.color)
    }) else {
    @failure.reject(
      "unsupported-math", "Mathematical scripts require uniform formatting",
    )
  }
  let frame : @layout.DrawingFrame = {
    width: 0,
    height: 0,
    anchor: None,
    content: Scripts(
      @layout.MathScripts::new(
        text,
        arguments.get("sub").map(value => value.0).unwrap_or(""),
        arguments.get("sup").map(value => value.0).unwrap_or(""),
        style,
      ),
    ),
  }
  frame.validate()
  frame
}
