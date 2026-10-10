///|
fn Session::additive_spacing(self : Session) -> Bool raise @failure.Failure {
  for rel in self.opc.relationships() {
    if rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" {
      guard !rel.external else {
        @failure.reject(
          "unsupported-layout", "External settings are unsupported",
        )
      }
      let tree = WordTree::new(self.opc.xml(rel.target))
      if tree
        .child(0, "compat")
        .bind(id => tree.child(id, "doNotUseHTMLParagraphAutoSpacing"))
        is Some(id) {
        return match tree.nodes[id].attribute("val", uri=word_uri) {
          Some("0" | "false" | "off") => false
          _ => true
        }
      }
      return false
    }
  }
  // Missing settings retain the fixed LibreOffice profile's additive default.
  true
}
