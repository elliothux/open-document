///|
fn WordTree::check_table_format_properties(
  self : WordTree,
  properties : Int,
  change~ : Int? = None,
) -> Unit raise @failure.Failure {
  let node = self.nodes[properties]
  let source = self.source[node.start:node.end]
  guard node.uri == word_uri &&
    node.name == "tblPr" &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque table properties require review support",
    )
  }
  let names : Set[String] = Set([])
  for id in self.children[properties] {
    let child = self.nodes[id]
    guard child.uri == word_uri && !names.contains(child.name) else {
      @failure.reject(
        "protected-content", "Foreign or duplicate table properties",
      )
    }
    names.add(child.name)
    if change == Some(id) {
      continue
    }
    match child.name {
      "tblBorders" => ignore(self.read_borders(properties, "tblBorders", None))
      "tblCellMar" =>
        ignore(
          self.table_margins(id, { top: 0, right: 0, bottom: 0, left: 0, }),
        )
      "tblW" => ignore(self.preferred_table_width(id))
      "tblStyle" | "jc" | "tblLayout" | "tblInd" | "tblLook" => {
        let attributes = match child.name {
          "tblLayout" => ["type"]
          "tblInd" => ["type", "w"]
          "tblLook" =>
            [
              "val", "firstRow", "lastRow", "firstColumn", "lastColumn", "noHBand",
              "noVBand",
            ]
          _ => ["val"]
        }
        guard self.children[id].is_empty() &&
          child.text.trim().is_empty() &&
          child.attributes.all(a => {
            a.uri == word_uri && attributes.contains(a.name)
          }) else {
          @failure.reject(
            "protected-content", "Unknown table property attributes",
          )
        }
        let valid = match child.name {
          "tblStyle" =>
            !child.attribute("val", uri=word_uri).unwrap_or("").is_empty()
          "jc" =>
            ["left", "center", "right", "start", "end"].contains(
              child.attribute("val", uri=word_uri).unwrap_or("left"),
            )
          "tblLayout" =>
            ["fixed", "autofit"].contains(
              child.attribute("type", uri=word_uri).unwrap_or("autofit"),
            )
          "tblInd" =>
            child.attribute("type", uri=word_uri) == Some("dxa") &&
            child
            .attribute("w", uri=word_uri)
            .map(value => {
              match value[:] {
                ['+' | '-', .. digits] =>
                  !digits.is_empty() && digits.iter().all(c => c == '0')
                digits => !digits.is_empty() && digits.iter().all(c => c == '0')
              }
            })
            .unwrap_or(false)
          _ =>
            child.attributes.all(a => {
              if a.name == "val" {
                a.value.length() == 4 &&
                a.value.iter().all(c => c.is_ascii_hexdigit())
              } else {
                ["0", "1", "true", "false", "on", "off"].contains(a.value)
              }
            })
        }
        guard valid else {
          @failure.reject(
            "protected-content", "Unsupported table formatting value",
          )
        }
      }
      _ =>
        @failure.reject(
          "protected-content", "Unknown table formatting requires review support",
        )
    }
  }
}

///|
fn WordTree::check_table_property_revision(
  self : WordTree,
  id : Int,
) -> Int raise @failure.Failure {
  let change = self.nodes[id]
  guard change.uri == word_uri &&
    change.name == "tblPrChange" &&
    change.text.trim().is_empty() &&
    change.attributes.all(a => {
      a.uri == word_uri && ["id", "author", "date"].contains(a.name)
    }) &&
    self.nodes.get(change.parent) is Some(properties) &&
    properties.uri == word_uri &&
    properties.name == "tblPr" &&
    self.nodes.get(properties.parent) is Some(table) &&
    table.uri == word_uri &&
    table.name == "tbl" &&
    self.nodes[table.parent].uri == word_uri &&
    self.nodes[table.parent].name == "body" &&
    self.nodes[table.parent].parent == 0 &&
    self.table_children(table.id, "tblPr").length() == 1 &&
    self.children[id] is [previous] else {
    @failure.reject(
      "protected-content", "Table formatting revision requires one ordinary previous property set",
    )
  }
  ignore(comment_key(change.attribute("id", uri=word_uri).unwrap_or("")))
  self.check_table_format_properties(properties.id, change=Some(id))
  self.check_table_format_properties(previous)
  let cells = self
    .table_children(table.id, "tr")
    .map(row => self.table_children(row, "tc"))
    .flatten()
  guard !cells.is_empty() else {
    @failure.reject("protected-content", "Revision table has no cells")
  }
  for cell in cells {
    self.check_merge_cell(cell, "", notes=true, review=true)
  }
  self.child(cells[0], "p").unwrap()
}
