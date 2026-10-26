///|
fn WordTree::diagnose_properties(
  self : WordTree,
  id : Int,
  part : String,
  diagnostics : Array[String],
) -> Unit {
  if self.nodes[id].uri != word_uri || self.index_markers.contains(id) {
    return
  }
  let supported = match self.nodes[id].name {
    "pPr" =>
      [
        "pStyle", "rPr", "spacing", "ind", "jc", "pageBreakBefore", "autoSpaceDE",
        "autoSpaceDN", "tabs", "bidi", "numPr", "outlineLvl", "keepLines", "keepNext",
        "widowControl", "contextualSpacing", "sectPr",
      ]
    "rPr" =>
      [
        "rStyle", "rFonts", "sz", "color", "b", "i", "lang", "bCs", "iCs", "szCs",
        "u", "strike", "highlight", "vertAlign", "cs", "rtl", "spacing",
      ]
    "sectPr" =>
      [
        "pgSz", "pgMar", "pgBorders", "headerReference", "footerReference", "titlePg",
        "cols", "docGrid", "pgNumType", "footnotePr", "endnotePr", "type",
      ]
    "tcPr" =>
      ["tcW", "shd", "gridSpan", "vMerge", "vAlign", "tcMar", "tcBorders"]
    "tblPr" =>
      [
        "tblStyle", "tblW", "jc", "tblBorders", "tblCellMar", "tblLook", "tblInd",
        "tblLayout",
      ]
    "trPr" => ["gridAfter", "trHeight", "tblHeader", "cantSplit"]
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
    if feature.uri == word_uri && feature.name == "tcPrChange" {
      if (try {
          ignore(self.check_cell_property_revision(child))
          true
        } catch {
          @failure.Failure(..) => false
        }) {
        continue
      }
    }
    if feature.uri == word_uri && feature.name == "tblPrChange" {
      if (try {
          ignore(self.check_table_property_revision(child))
          true
        } catch {
          @failure.Failure(..) => false
        }) {
        continue
      }
    }
    if feature.uri == word_uri && feature.name == "trPrChange" {
      if (try {
          ignore(self.check_row_property_revision(child))
          true
        } catch {
          @failure.Failure(..) => false
        }) {
        continue
      }
    }
    if self.is_row_revision(child) {
      if (try {
          ignore(self.check_row_revision(child))
          true
        } catch {
          @failure.Failure(..) => false
        }) {
        continue
      }
    }
    if self.is_paragraph_revision(child) {
      if (try {
          ignore(self.check_paragraph_revision(child))
          true
        } catch {
          @failure.Failure(..) => false
        }) {
        continue
      }
    }
    if feature.uri == word_uri &&
      ["rPrChange", "pPrChange"].contains(feature.name) {
      let supported = try {
        ignore(self.check_property_revision(child))
        true
      } catch {
        @failure.Failure(..) => false
      }
      if supported {
        continue
      }
    }
    let inactive = match feature.name {
      "type" =>
        self.children[child].is_empty() &&
        feature.text.trim().is_empty() &&
        feature.attributes.all(a => a.uri == word_uri && a.name == "val") &&
        ["nextPage", "oddPage", "evenPage", "continuous"].contains(
          feature.attribute("val", uri=word_uri).unwrap_or("nextPage"),
        ) &&
        self.children[id]
        .filter(s => {
          self.nodes[s].uri == word_uri && self.nodes[s].name == "type"
        })
        .length() ==
        1
      "tblLayout" =>
        self.children[child].is_empty() &&
        feature.text.trim().is_empty() &&
        [Some("fixed"), Some("autofit"), None].contains(
          feature.attribute("type", uri=word_uri),
        ) &&
        feature.attributes
        .iter()
        .all(a => a.uri == word_uri && a.name == "type")
      "tabs" => self.valid_tabs(child)
      "pgNumType" =>
        try {
          ignore(self.page_numbering(Some(id)))
          true
        } catch {
          @failure.Failure(..) => false
        }
      "titlePg"
      | "bidi"
      | "cs"
      | "rtl"
      | "tblHeader"
      | "cantSplit"
      | "keepLines"
      | "keepNext"
      | "widowControl"
      | "contextualSpacing" => self.valid_on_off_property(child)
      "numPr" => self.valid_numbering_properties(child)
      "outlineLvl" =>
        try {
          ignore(self.outline_level(id))
          true
        } catch {
          @failure.Failure(..) => false
        }
      // The fixed Writer DOCX importer preserves these flags without applying them.
      "autoSpaceDE" | "autoSpaceDN" => self.valid_on_off_property(child)
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
        try {
          ignore(self.page_columns(Some(id)))
          true
        } catch {
          @failure.Failure(..) => false
        }
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
fn WordTree::valid_on_off_property(self : WordTree, id : Int) -> Bool {
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
