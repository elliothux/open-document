///|
fn Session::decimal_symbol(self : Session) -> String raise @failure.Failure {
  for rel in self.opc.relationships() {
    if rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" {
      guard !rel.external else {
        @failure.reject(
          "unsupported-layout", "External settings are unsupported",
        )
      }
      let value = WordTree::new(self.part_xml(rel.target))
        .value(0, "decimalSymbol")
        .unwrap_or(".")
      guard value.iter().count() == 1 &&
        !value.trim().is_empty() &&
        !value.contains("\t") &&
        !value.contains("\n") else {
        @failure.reject("invalid-style", "Invalid decimal tab symbol")
      }
      return value
    }
  }
  "."
}

///|
fn Session::expand_soft_break(self : Session) -> Bool raise @failure.Failure {
  for rel in self.opc.relationships() {
    if rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" {
      guard !rel.external else {
        @failure.reject(
          "unsupported-layout", "External settings are unsupported",
        )
      }
      let tree = WordTree::new(self.part_xml(rel.target))
      if tree
        .child(0, "compat")
        .bind(id => tree.child(id, "doNotExpandShiftReturn"))
        is Some(id) {
        return match tree.nodes[id].attribute("val", uri=word_uri) {
          Some("0" | "false" | "off") => true
          _ => false
        }
      }
    }
  }
  true
}

///|
fn Session::default_tab(self : Session) -> Double raise @failure.Failure {
  for rel in self.opc.relationships() {
    if rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" {
      guard !rel.external else {
        @failure.reject(
          "unsupported-layout", "External settings are unsupported",
        )
      }
      let tree = WordTree::new(self.part_xml(rel.target))
      let value = tree.number(0, "defaultTabStop", "val").unwrap_or(720)
      guard value >= 0 && value <= 31680 else {
        @failure.reject("invalid-style", "Invalid default tab interval")
      }
      return value / 20
    }
  }
  36
}

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
      let tree = WordTree::new(self.part_xml(rel.target))
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
