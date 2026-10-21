///|
fn Session::shape_text(
  self : Session,
  tree : WordTree,
  shape : Int,
  text : Int,
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
  let nodes = tree.children[content]
  guard nodes.length() > 0 && nodes.length() <= 256 else {
    @failure.reject("limit-exceeded", "Text box paragraph count exceeds budget")
  }
  for paragraph in nodes {
    let node = tree.nodes[paragraph]
    guard node.uri == word_uri &&
      node.name == "p" &&
      tree.children[paragraph].all(id => {
        let child = tree.nodes[id]
        child.uri == word_uri && ["pPr", "r"].contains(child.name)
      }) &&
      tree
      .descendants(paragraph)
      .all(id => {
        let child = tree.nodes[id]
        ![
          "drawing", "pict", "object", "numPr", "sectPr", "fldSimple", "fldChar",
          "instrText",
        ].contains(child.name) &&
        (
          child.name != "br" ||
          child.attribute("type", uri=word_uri).unwrap_or("textWrapping") ==
          "textWrapping"
        )
      }) else {
      @failure.reject(
        "unsupported-layout", "Text box tables fields lists and embedded objects require support",
      )
    }
  }
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
          | "upright"
          | "fromWordArt"
          | "forceAA"
          | "spcFirstLastPara" => ["0", "false"].contains(a.value)
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
  let diagnostics : Array[String] = []
  let styles = self.styles(diagnostics)
  let paragraphs = nodes.map(id => self.paragraph(tree, styles, id, diagnostics))
  let units = paragraphs
    .iter()
    .flat_map(p => p.spans.iter())
    .fold(init=0, (sum, span) => sum + span.text.length())
  guard units <= 32767 else {
    @failure.reject("limit-exceeded", "Text box exceeds text budget")
  }
  guard paragraphs.all(p => {
    p.spans.iter().fold(init=0, (sum, span) => sum + span.text.length()) <= 4096
  }) else {
    @failure.reject("limit-exceeded", "Text box paragraph exceeds text budget")
  }
  guard diagnostics.is_empty() &&
    paragraphs.all(p => {
      p.readOnlyReason.is_empty() &&
      !p.pageBreakBefore &&
      p.marker is None &&
      p.spans.all(s => s.drawing is None && s.field.is_empty())
    }) else {
    @failure.reject(
      "unsupported-layout", "Text box paragraph properties require support",
    )
  }
  @layout.DrawingTextBox::new(paragraphs, insets, anchor, wrap, clip)
}
