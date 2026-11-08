///|
fn Session::vml_text(
  self : Session,
  tree : WordTree,
  shape : Int32,
  text : Int32,
) -> @layout.DrawingTextBox raise @failure.Failure {
  let node = tree.nodes[text]
  guard node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() && ["style", "inset"].contains(a.name)
    }) &&
    tree.children[text] is [content] else {
    @failure.reject(
      "unsupported-layout", "VML text box requires ordinary Word paragraphs",
    )
  }
  let style = vml_style(node.attribute("style").unwrap_or(""), [
    "mso-next-textbox",
  ])
  if style.get("mso-next-textbox") is Some(next) {
    // LibreOffice DomainMapper_Impl ignores a next-textbox link to itself.
    guard tree.nodes[shape].attribute("id") is Some(id) && next == "#" + id else {
      @failure.reject(
        "unsupported-layout", "Linked VML text boxes require support",
      )
    }
  }
  // ONLYOFFICE CTextbox initializes left/top/right/bottom to 7.2/3.6/7.2/3.6 pt.
  let insets = [3.6, 7.2, 3.6, 7.2]
  if node.attribute("inset") is Some(raw) {
    guard raw.split(",").to_array() is [left, top, right, bottom] else {
      @failure.reject("unsupported-layout", "VML text box requires four insets")
    }
    for index, value in [top, right, bottom, left] {
      insets[index] = vml_points(value.to_owned())
    }
  }
  self.text_box_content(tree, content, {
    insets,
    anchor: "t",
    wrap: true,
    clip: false,
  })
}
