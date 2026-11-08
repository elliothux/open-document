///|
fn Session::shape_text(
  self : Session,
  tree : WordTree,
  shape : Int32,
  text : Int32,
  linked~ : Bool = false,
) -> @layout.DrawingTextBox raise @failure.Failure {
  let box = tree.nodes[text]
  guard box.text.trim().is_empty() &&
    box.attributes.all(a => {
      a.uri.is_empty() &&
      a.name == "id" &&
      a.value.length() <= 10 &&
      !a.value.is_empty() &&
      a.value.iter().all(c => c.is_ascii_digit())
    }) &&
    tree.children[text] is [content] &&
    tree.nodes[content].uri == word_uri &&
    tree.nodes[content].name == "txbxContent" &&
    tree.nodes[content].attributes.is_empty() &&
    tree.nodes[content].text.trim().is_empty() else {
    @failure.reject(
      "unsupported-layout", "Text box requires ordinary Word paragraphs",
    )
  }
  self.text_box_content(tree, content, tree.text_box_properties(shape), linked~)
}

///|
fn WordTree::text_box_properties(
  tree : WordTree,
  shape : Int32,
) -> @layout.DrawingTextBoxProperties raise @failure.Failure {
  let insets = [3.6, 7.2, 3.6, 7.2]
  let mut anchor = "t"
  let mut wrap = true
  let mut clip = false
  if tree.drawing_child(shape, "bodyPr", uri=word_shape_uri) is Some(body) {
    let node = tree.nodes[body]
    guard node.attributes.all(a => {
        a.uri.is_empty() &&
        (match a.name {
          "lIns" | "rIns" | "tIns" | "bIns" => true
          "anchor" => ["t", "ctr", "b"].contains(a.value)
          "wrap" => ["square", "none"].contains(a.value)
          "horzOverflow" | "vertOverflow" =>
            ["overflow", "clip"].contains(a.value)
          "rot" | "spcCol" => a.value == "0"
          "vert" => a.value == "horz"
          "numCol" => a.value == "1"
          "anchorCtr"
          | "rtlCol"
          | "fromWordArt"
          | "forceAA"
          | "spcFirstLastPara" => ["0", "false"].contains(a.value)
          "upright" => ["0", "1", "false", "true"].contains(a.value)
          _ => false
        })
      }) &&
      tree.children[body].all(id => {
        let child = tree.nodes[id]
        (child.name == "noAutofit" && child.attributes.is_empty()) ||
        (
          child.name == "prstTxWarp" &&
          child.attributes.all(a => a.uri.is_empty() && a.name == "prst")
        )
      }) else {
      @failure.reject(
        "unsupported-layout", "Text box transforms columns and autofit require support",
      )
    }
    for index, name in ["tIns", "rIns", "bIns", "lIns"] {
      if node.attribute(name) is Some(_) {
        insets[index] = drawing_number(node, name)
      }
    }
    anchor = node.attribute("anchor").unwrap_or("t")
    wrap = node.attribute("wrap").unwrap_or("square") == "square"
    let horizontal = node.attribute("horzOverflow").unwrap_or("overflow")
    let vertical = node.attribute("vertOverflow").unwrap_or("overflow")
    guard horizontal == vertical else {
      @failure.reject(
        "unsupported-layout", "Independent text box overflow axes require support",
      )
    }
    clip = vertical == "clip"
  }
  { insets, anchor, wrap, clip, }
}
