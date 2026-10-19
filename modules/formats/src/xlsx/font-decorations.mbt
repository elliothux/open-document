///|
fn font_decorations(
  tree : Tree,
  font : @xml.Node,
) -> CellFormat raise @failure.Failure {
  let underline = tree
    .one(font.id, "u")
    .map(node => {
      conditional_node(tree, node, ["val"], [])
      let value = node.attribute("val").unwrap_or("single")
      guard ["none", "single"].contains(value) else {
        @failure.reject("protected-content", "Unsupported cell underline")
      }
      value == "single"
    })
  let strike = tree
    .one(font.id, "strike")
    .map(node => {
      conditional_node(tree, node, ["val"], [])
      flag(node, "val", fallback=true)
    })
  let script = tree
    .one(font.id, "vertAlign")
    .map(node => {
      conditional_node(tree, node, ["val"], [])
      let value = node.attribute("val").unwrap_or("")
      guard ["baseline", "superscript", "subscript"].contains(value) else {
        @failure.reject(
          "protected-content", "Unsupported cell vertical alignment",
        )
      }
      value
    })
  CellFormat::new(underline~, strike~, script~)
}

///|
fn CellStyle::text_style(self : CellStyle) -> @layout.TextStyle {
  {
    ..@layout.TextStyle::new(self.font, self.size, self.color),
    underline: self.underline,
    strike: self.strike,
    script: self.script,
  }
}
