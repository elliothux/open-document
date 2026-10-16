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
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let grid = self.table_grid(tree, selection)
  let owner = grid.owners[grid.cells[grid.row][grid.column]]
  let changes : TableChanges = {
    items: [],
    bytes: 0,
    limit: self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  }
  let targets = if whole_table {
    [grid.table]
  } else {
    grid.cells.flatten().filter(cell => grid.owners[cell] == owner)
  }
  for target in targets {
    if !whole_table {
      tree.check_merge_cell(target, self.main)
    }
    if tree.table_property_change(
        document,
        target,
        if whole_table {
          "tblPr"
        } else {
          "tcPr"
        },
        name,
        attributes,
        markup~,
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
  if name == "tcMar" || name == "tblCellMar" {
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
