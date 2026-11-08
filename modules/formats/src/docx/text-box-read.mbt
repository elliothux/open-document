///|
fn Session::text_box_content(
  self : Session,
  tree : WordTree,
  content : Int32,
  properties : @layout.DrawingTextBoxProperties,
  linked~ : Bool = false,
) -> @layout.DrawingTextBox raise @failure.Failure {
  let root = tree.nodes[content]
  guard root.uri == word_uri &&
    root.name == "txbxContent" &&
    root.attributes.is_empty() &&
    root.text.trim().is_empty() else {
    @failure.reject(
      "unsupported-layout", "Text box requires ordinary Word paragraphs",
    )
  }
  let nodes = tree.children[content]
  let running = tree.part != self.main &&
    ["hdr", "ftr"].contains(tree.nodes[0].name)
  guard nodes.length() > 0 && nodes.length() <= 256 else {
    @failure.reject("limit-exceeded", "Text box paragraph count exceeds budget")
  }
  for paragraph in nodes {
    let node = tree.nodes[paragraph]
    guard node.uri == word_uri &&
      node.name == "p" &&
      tree.children[paragraph].all(id => {
        let child = tree.nodes[id]
        child.uri == word_uri &&
        (
          ["pPr", "r", "hyperlink", "proofErr"].contains(child.name) ||
          (linked && tree.is_bookmark(id)) ||
          (running && child.name == "fldSimple")
        )
      }) &&
      tree
      .descendants(paragraph)
      .all(id => {
        let child = tree.nodes[id]
        !["drawing", "pict", "object", "sectPr"].contains(child.name) &&
        (running || !["fldSimple", "fldChar", "instrText"].contains(child.name)) &&
        (
          child.name != "br" ||
          child.attribute("type", uri=word_uri).unwrap_or("textWrapping") ==
          "textWrapping"
        )
      }) else {
      @failure.reject(
        "unsupported-layout",
        "Text box tables fields lists and embedded objects require support",
        part=tree.part,
        offset=node.start,
      )
    }
  }
  let diagnostics : Array[String] = []
  let styles = self.styles(diagnostics)
  let values : Map[Int32, @layout.Paragraph] = Map([])
  for id in nodes {
    values[id] = self.paragraph(tree, styles, id, diagnostics, running~)
  }
  styles.apply_contextual_spacing(tree, values)
  let paragraphs = nodes.map(id => values[id])
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
      p.spans.all(s => {
        s.drawing is None &&
        (
          s.field.is_empty() ||
          (
            running &&
            ["PAGE", "NUMPAGES"].contains(
              s.field.split(":").head().unwrap().to_owned(),
            )
          )
        )
      })
    }) else {
    @failure.reject(
      "unsupported-layout",
      "Text box paragraph properties require support: " +
      diagnostics.join("; ") +
      paragraphs.map(p => p.readOnlyReason).join("; "),
    )
  }
  let bottomBorders : Map[Int32, (Double, @layout.BorderStyle)] = Map([])
  for paragraph in nodes {
    if tree.child(paragraph, "pPr").bind(p => tree.child(p, "pBdr"))
      is Some(border) &&
      tree.text_box_bottom_border(border) is Some(value) {
      bottomBorders[paragraph] = value
    }
  }
  @layout.DrawingTextBox::new(
    paragraphs,
    properties.insets,
    properties.anchor,
    properties.wrap,
    properties.clip,
    bottomBorders~,
  )
}
