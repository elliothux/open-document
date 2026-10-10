///|
fn WordTree::diagnose_properties(
  self : WordTree,
  id : Int,
  part : String,
  diagnostics : Array[String],
) -> Unit {
  let supported = match self.nodes[id].name {
    "pPr" => ["pStyle", "rPr", "spacing", "ind", "jc", "pageBreakBefore"]
    "rPr" =>
      [
        "rStyle", "rFonts", "sz", "color", "b", "i", "lang", "bCs", "iCs", "szCs",
      ]
    "sectPr" => ["pgSz", "pgMar", "headerReference"]
    "tcPr" => ["tcW", "shd", "gridSpan", "vMerge"]
    "tblPr" => ["tblStyle", "tblW", "jc", "tblBorders", "tblCellMar", "tblLook"]
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
    if feature.uri != word_uri || !supported.contains(feature.name) {
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
