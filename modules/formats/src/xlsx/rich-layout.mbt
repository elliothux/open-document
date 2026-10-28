///|
fn Sheet::rich_layout_sources(self : Sheet) -> Map[String, String] {
  let selected : Map[Int32, String] = Map([])
  for name, cell in self.cells {
    if cell.read_only == "Rich text cell is read-only" {
      selected[cell.node] = name
    }
  }
  let result : Map[String, String] = Map([])
  if !selected.is_empty() {
    let source = self.document.source()
    for node in self.document.nodes() {
      if selected.get(node.id) is Some(name) {
        result[name] = source[node.start:node.end].to_owned()
      }
    }
  }
  result
}

///|
fn rich_layout_spans(
  tree : Tree,
  root : @xml.Node,
  base : CellStyle,
  theme : Array[String],
  work : FormulaWork,
) -> Array[@layout.Span] raise @failure.Failure {
  ignore(rich_run_colors(tree, root, theme, work))
  let result : Array[@layout.Span] = []
  let mut units = 0
  for run in tree.all(root.id, "r") {
    work.spend()
    let properties = tree.one(run.id, "rPr")
    if properties is Some(properties) {
      conditional_node(tree, properties, [], [
        "rFont", "sz", "b", "i", "color", "family", "charset", "scheme", "u", "strike",
        "vertAlign",
      ])
      for property in tree.children.get(properties.id).unwrap_or([]) {
        if property.name != "color" {
          conditional_node(tree, property, ["val"], [])
        }
      }
    }
    let property = fn(name) raise @failure.Failure {
      properties.bind(properties => tree.one(properties.id, name))
    }
    let parts = base.font.split("|").map(part => part.to_owned()).to_array()
    let family = property("rFont")
      .bind(node => node.attribute("val"))
      .unwrap_or(parts[0])
    let size = property("sz")
      .bind(node => node.attribute("val"))
      .map(number)
      .unwrap_or(base.size)
    CellFormat::new(family=Some(family), size=Some(size)).validate()
    let bold = property("b")
      .map(node => flag(node, "val", fallback=true))
      .unwrap_or(parts.contains("bold"))
    let italic = property("i")
      .map(node => flag(node, "val", fallback=true))
      .unwrap_or(parts.contains("italic"))
    let color = property("color")
      .map(node => conditional_color(tree, node, theme))
      .unwrap_or(base.color)
    let effects = properties
      .map(node => font_decorations(tree, node))
      .unwrap_or(CellFormat::new())
      .applied(base)
    let text = decode_text(
      tree.one(run.id, "t").map(node => node.text).unwrap_or(""),
    )
    guard result.length() < 32767 && text.length() <= 32767 - units else {
      @failure.reject("limit-exceeded", "Rich cell layout exceeds budget")
    }
    units += text.length()
    work.spend(amount=text.length())
    result.push({
      node: run.id,
      text,
      style: {
        ..@layout.TextStyle::new(
          family +
          (if bold { "|bold" } else { "" }) +
          (if italic { "|italic" } else { "" }),
          size,
          color,
        ),
        underline: effects.underline,
        strike: effects.strike,
        script: effects.script,
      },
      drawing: None,
      field: "",
    })
  }
  result
}
