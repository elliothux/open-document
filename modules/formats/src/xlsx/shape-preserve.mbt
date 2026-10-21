///|
fn SheetObject::check_shape_source(
  self : SheetObject,
) -> Unit raise @failure.Failure {
  let tree = self.tree
  let nv = tree.picture_node(self.source.id, "nvSpPr")
  let raw = tree.document.source()[self.frame.start:self.frame.end]
  guard !raw.contains("<!--") && !raw.contains("<?") else {
    @failure.reject(
      "protected-content", "Shape source annotations require preservation support",
    )
  }
  for node in tree.document.nodes() {
    if node.start < self.frame.start ||
      node.end > self.frame.end ||
      (node.start >= nv.start && node.end <= nv.end) ||
      node.name == "clientData" {
      continue
    }
    let allowed = match node.name {
      "twoCellAnchor" => ["editAs"]
      "pos" | "off" => ["x", "y"]
      "ext" => ["cx", "cy"]
      "prstGeom" => ["prst"]
      "ln" => ["w"]
      "srgbClr" | "schemeClr" => ["val"]
      "sysClr" => ["val", "lastClr"]
      "bodyPr" => ["lIns", "tIns", "rIns", "bIns", "wrap", "anchor", "rtlCol"]
      "pPr" => ["algn"]
      "rPr" | "defRPr" | "endParaRPr" => ["sz", "b", "i", "dirty"]
      "latin" => ["typeface"]
      _ => []
    }
    guard ![
        "pos", "off", "ext", "col", "row", "colOff", "rowOff", "srgbClr", "schemeClr",
        "sysClr", "noFill", "latin", "t", "avLst", "lstStyle", "noAutofit",
      ].contains(node.name) ||
      tree.children.get(node.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "protected-content", "Shape source extensions require preservation support",
      )
    }
    guard node.attributes.all(a => {
      (a.uri.is_empty() && allowed.contains(a.name)) ||
      (
        node.name == "t" &&
        a.uri == "http://www.w3.org/XML/1998/namespace" &&
        a.name == "space" &&
        ["preserve", "default"].contains(a.value)
      )
    }) else {
      @failure.reject(
        "protected-content", "Shape source attributes require preservation support",
      )
    }
  }
}

///|
fn SheetObject::check_shape_locks(
  self : SheetObject,
  shape : SheetShape,
) -> Unit raise @failure.Failure {
  let previous = self.shape.unwrap()
  for node in self.tree.document.nodes() {
    if node.start < self.source.start ||
      node.end > self.source.end ||
      node.name != "spLocks" {
      continue
    }
    guard (
        !flag(node, "noChangeShapeType") ||
        (previous.preset == shape.preset && previous.text_box == shape.text_box)
      ) &&
      (
        !flag(node, "noTextEdit") ||
        previous.text_source() == shape.text_source()
      ) else {
      @failure.reject(
        "protected-content", "Worksheet shape text or preset is locked",
      )
    }
  }
}
