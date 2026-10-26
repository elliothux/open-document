///|
fn Session::fill_table_cell(
  self : Session,
  revision : Int,
  selection : Selection,
  color : String?,
  theme : String?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if color is Some(value) {
    guard value.length() == 6 && value.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject(
        "invalid-operation", "Cell fill requires six hexadecimal digits or null",
      )
    }
  }
  if theme is Some(slot) {
    guard color is Some(_) &&
      (
        theme_slots.contains(theme_color_name(slot)) ||
        ["text1", "text2", "background1", "background2"].contains(slot)
      ) &&
      word_theme_color_name(slot) == slot else {
      @failure.reject("invalid-operation", "Invalid cell fill theme slot")
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
    fill_theme=theme,
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
  whole_row~ : Bool = false,
  header_rows~ : Int? = None,
  border_patch~ : Map[String, TableBorderStyle?]? = None,
  fill_theme~ : String? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let row_format = whole_row || header_rows is Some(_)
  let selected = self.table_cell_range(tree, selection, notes=true, review=true)
  let grid = selected
    .map(range => range.grid)
    .unwrap_or_else(() => {
      self.table_grid(tree, selection, notes=true, review=true)
    })
  if whole_row &&
    name == "cantSplit" &&
    attributes is Some(values) &&
    (match selected {
      Some(range) =>
        grid.model.splitRows[range.top:range.bottom]
        .iter()
        .all(split => split == (values.get("val") == Some(Some("0"))))
      None =>
        grid.model.splitRows[grid.row] == (values.get("val") == Some(Some("0")))
    }) {
    return self.edit_state()
  }
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
  } else if whole_row {
    match selected {
      Some(range) => grid.rows[range.top:range.bottom].to_owned()
      None => [grid.rows[grid.row]]
    }
  } else {
    selected
    .map(range => range.cells)
    .unwrap_or_else(() => {
      grid.cells.flatten().filter(cell => grid.owners[cell] == owner)
    })
  }
  let parts = self.parts.copy()
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  if fill_theme is Some(_) ||
    (
      border_patch is Some(patch) &&
      patch.values().any(edge => edge is Some({ themeColor: Some(_), .. }))
    ) {
    let reason = self.theme_edit_reason()
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    if self.theme_part() is None {
      ignore(self.new_word_part("theme", parts, part_edits, created))
    }
  }
  let view = { ..self, parts, }
  let border_themes = if border_patch is Some(_) || name == "shd" {
    view.theme_values()
  } else {
    Map([])
  }
  for index, target in targets {
    if !whole_table && !whole_row && header_rows is None {
      tree.check_merge_cell(target, self.main, notes=true, review=true)
    }
    if tree.table_property_change(
        document,
        target,
        if header_rows is Some(_) || whole_row {
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
        } else if name == "shd" && attributes is Some(values) {
          Some(tree.table_fill_patch(target, values, fill_theme, border_themes))
        } else {
          attributes
        },
        markup=if border_patch is Some(value) {
          Some(tree.border_markup(document, target, name, value, border_themes))
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
  let (candidate, recorded, record_bytes) = self.record_table_properties(
    document,
    candidate,
    targets,
    kind=if whole_table {
      "tblPr"
    } else if row_format {
      "trPr"
    } else {
      "tcPr"
    },
  )
  let flow = view.flow_from(candidate)
  let updated = flow.tables.iter().find_first(t => t.id == grid.table).unwrap()
  if header_rows is Some(count) && updated.headerRows != count {
    @failure.reject(
      "invalid-operation", "Header boundary crosses a vertical merge",
    )
  }
  if ["tcMar", "tblCellMar", "tcBorders", "tblBorders"].contains(name) {
    check_margin_layout(
      updated,
      page_area_for_position(flow, table_start_position(updated)).0,
    )
  }
  guard updated.rows.flatten().flatten().all(p => p.readOnlyReason.is_empty()) else {
    @failure.reject(
      "protected-content", "Table properties require supported layout",
    )
  }
  let affected = grid.model.rows.flatten().flatten().map(p => p.id)
  let bytes = edit.payload_bytes() +
    record_bytes.to_int64() +
    xml_part_edit_bytes(part_edits, created).to_int64()
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
      xml: [edit, ..recorded],
      parts: part_edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: Some(selection.without_visual_hints()),
      paragraphs: affected,
      bytes: bytes.to_int(),
    },
    candidate,
    parts~,
    tracking_edit=true,
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
