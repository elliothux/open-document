///|
fn WordTree::diagnose_properties(
  self : WordTree,
  id : Int,
  part : String,
  diagnostics : Array[String],
) -> Unit {
  let supported = match self.nodes[id].name {
    "pPr" =>
      [
        "pStyle", "rPr", "spacing", "ind", "jc", "pageBreakBefore", "autoSpaceDE",
        "autoSpaceDN", "tabs",
      ]
    "rPr" =>
      [
        "rStyle", "rFonts", "sz", "color", "b", "i", "lang", "bCs", "iCs", "szCs",
        "u", "strike", "highlight", "vertAlign",
      ]
    "sectPr" => ["pgSz", "pgMar", "headerReference", "cols", "docGrid"]
    "tcPr" => ["tcW", "shd", "gridSpan", "vMerge"]
    "tblPr" =>
      [
        "tblStyle", "tblW", "jc", "tblBorders", "tblCellMar", "tblLook", "tblInd",
      ]
    "trPr" => ["trHeight"]
    _ => return
  }
  fn report(
    part : String,
    feature : String,
    diagnostics : Array[String],
  ) -> Unit {
    let message = "unsupported-layout:" + part + ":" + feature
    if !diagnostics.contains(message) {
      diagnostics.push(message)
    }
  }
  for child in self.children[id] {
    let feature = self.nodes[child]
    let inactive = match feature.name {
      "tabs" => self.valid_tabs(child)
      // The fixed Writer DOCX importer preserves these flags without applying them.
      "autoSpaceDE" | "autoSpaceDN" => self.valid_script_spacing_property(child)
      "u" =>
        self.children[child].is_empty() &&
        feature.text.trim().is_empty() &&
        ["none", "single"].contains(
          feature.attribute("val", uri=word_uri).unwrap_or("single"),
        ) &&
        feature.attributes
        .iter()
        .all(attribute => attribute.uri == word_uri && attribute.name == "val")
      "tblInd" =>
        self.children[child].is_empty() &&
        feature.text.is_empty() &&
        feature.attribute("type", uri=word_uri) == Some("dxa") &&
        (match feature.attribute("w", uri=word_uri) {
          Some(value) =>
            match value[:] {
              ['+' | '-', .. digits] =>
                !digits.is_empty() && digits.iter().all(c => c == '0')
              digits => !digits.is_empty() && digits.iter().all(c => c == '0')
            }
          None => false
        }) &&
        feature.attributes
        .iter()
        .all(attribute => {
          attribute.uri == word_uri && ["w", "type"].contains(attribute.name)
        })
      "cols" =>
        self.children[child].is_empty() &&
        feature.attribute("num", uri=word_uri).unwrap_or("1") == "1" &&
        ["1", "true", "on"].contains(
          feature.attribute("equalWidth", uri=word_uri).unwrap_or("1"),
        ) &&
        feature.attributes
        .iter()
        .all(attribute => {
          attribute.uri == word_uri &&
          ["num", "equalWidth", "space", "sep"].contains(attribute.name)
        })
      "docGrid" =>
        self.children[child].is_empty() &&
        feature.attribute("type", uri=word_uri).unwrap_or("default") ==
        "default" &&
        feature.attributes
        .iter()
        .all(attribute => {
          attribute.uri == word_uri &&
          ["type", "linePitch", "charSpace"].contains(attribute.name)
        })
      _ => true
    }
    if feature.uri != word_uri || !supported.contains(feature.name) || !inactive {
      report(part, feature.qualified, diagnostics)
    }
    if feature.name == "spacing" {
      for
        name in [
          "beforeAutospacing", "afterAutospacing", "beforeLines", "afterLines",
        ] {
        if feature.attribute(name, uri=word_uri) is Some(_) {
          report(part, "w:spacing/@w:" + name, diagnostics)
        }
      }
    }
    if feature.name == "rPr" {
      self.diagnose_properties(child, part, diagnostics)
    }
  }
}

///|
fn WordTree::valid_script_spacing_property(self : WordTree, id : Int) -> Bool {
  let node = self.nodes[id]
  node.uri == word_uri &&
  self.children[node.parent]
  .iter()
  .filter(child => {
    self.nodes[child].uri == word_uri && self.nodes[child].name == node.name
  })
  .count() ==
  1 &&
  self.children[id].is_empty() &&
  node.text.trim().is_empty() &&
  node.attributes
  .iter()
  .all(attribute => attribute.uri == word_uri && attribute.name == "val") &&
  ["0", "1", "true", "false", "on", "off"].contains(
    node.attribute("val", uri=word_uri).unwrap_or("1"),
  )
}
