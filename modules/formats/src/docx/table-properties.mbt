///|
fn Session::fill_table_cell(
  self : Session,
  revision : Int,
  selection : Selection,
  color : String?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if color is Some(value) {
    guard value.length() == 6 && value.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject(
        "invalid-operation", "Cell fill requires six hexadecimal digits or null",
      )
    }
  }
  let color = color.map(value => value.to_lower())
  self.change_table_property(
    revision,
    selection,
    "shd",
    color.map(value => {
      Map([
        ("val", Some("clear")),
        ("color", Some("auto")),
        ("fill", Some(value)),
      ])
    }),
  )
}

///|
fn Session::change_table_property(
  self : Session,
  revision : Int,
  selection : Selection,
  name : String,
  attributes : Map[String, String?]?,
  markup~ : String? = None,
  whole_table~ : Bool = false,
  header_rows~ : Int? = None,
  border_patch~ : Map[String, @layout.BorderStyle?]? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let grid = self.table_grid(tree, selection)
  if header_rows is Some(count) {
    guard count >= 0 && count <= 1000 && count <= grid.rows.length() else {
      @failure.reject(
        "invalid-operation", "Header row count is outside the table",
      )
    }
    for row in 0..<count {
      guard grid.model.rowSpans[row].all(span => span <= count - row) else {
        @failure.reject(
          "invalid-operation", "Header boundary crosses a vertical merge",
        )
      }
    }
  }
  let owner = grid.owners[grid.cells[grid.row][grid.column]]
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  let targets = if header_rows is Some(_) {
    grid.rows
  } else if whole_table {
    [grid.table]
  } else {
    grid.cells.flatten().filter(cell => grid.owners[cell] == owner)
  }
  for index, target in targets {
    if !whole_table && header_rows is None {
      tree.check_merge_cell(target, self.main)
    }
    if tree.table_property_change(
        document,
        target,
        if header_rows is Some(_) {
          "trPr"
        } else if whole_table {
          "tblPr"
        } else {
          "tcPr"
        },
        name,
        if header_rows is Some(count) {
          if index < count {
            Some(Map([("val", Some("1"))]))
          } else {
            None
          }
        } else {
          attributes
        },
        markup=if border_patch is Some(value) {
          Some(tree.border_markup(document, target, name, value))
        } else {
          markup
        },
      )
      is Some(change) {
      changes.push(change)
    }
  }
  if changes.items.is_empty() {
    return self.edit_state()
  }
  let (candidate, edit) = document.edit_source(changes.items)
  let updated = self.flow_from(candidate).tables
    .iter()
    .find_first(t => t.id == grid.table)
    .unwrap()
  if header_rows is Some(count) && updated.headerRows != count {
    @failure.reject(
      "invalid-operation", "Header boundary crosses a vertical merge",
    )
  }
  if ["tcMar", "tblCellMar", "tcBorders", "tblBorders"].contains(name) {
    self.check_margin_layout(updated)
  }
  guard updated.rows.flatten().flatten().all(p => p.readOnlyReason.is_empty()) else {
    @failure.reject(
      "protected-content", "Table properties require supported layout",
    )
  }
  let affected = grid.model.rows.flatten().flatten().map(p => p.id)
  let bytes = edit.payload_bytes()
  guard bytes <= history_byte_limit.to_int64() else {
    @failure.reject("limit-exceeded", "Table property history exceeds budget")
  }
  let pending = if self.selection == Some(selection) {
    self.typing_format
  } else {
    None
  }
  self.commit_edit(
    {
      xml: [edit],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some(selection.without_visual_hints()),
      paragraphs: affected,
      bytes: bytes.to_int(),
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result(affected)
}

///|
fn WordTree::cell_vertical_alignment(
  self : WordTree,
  props : Int,
) -> String? raise @failure.Failure {
  guard self.child(props, "vAlign") is Some(id) else { return None }
  let node = self.nodes[id]
  let value = node.attribute("val", uri=word_uri).unwrap_or("top")
  guard self.table_children(props, "vAlign").length() == 1 &&
    self.children[id].is_empty() &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri == word_uri && a.name == "val") &&
    ["top", "center", "bottom"].contains(value) else {
    @failure.reject("unsupported-layout", "Unsupported cell vertical alignment")
  }
  Some(value)
}
