///|
priv struct TableRange {
  top : Int
  bottom : Int
  left : Int
  right : Int
  owners : Int
}

///|
fn TableRange::multiple(self : TableRange) -> Bool {
  self.owners > 1
}

///|
fn DrawingTable::range(
  self : DrawingTable,
  selection : Selection,
) -> TableRange raise @failure.Failure {
  let (ar, ac) = self.cell_at(
    if selection.mode == "text" {
      selection.anchor
    } else {
      0
    },
  )
  let (fr, fc) = self.cell_at(
    if selection.mode == "text" {
      selection.focus
    } else {
      0
    },
  )
  let a = self.rows[ar].cells[ac]
  let f = self.rows[fr].cells[fc]
  let mut top = ar.min(fr)
  let mut bottom = (ar + a.row_span - 1).max(fr + f.row_span - 1)
  let mut left = ac.min(fc)
  let mut right = (ac + a.column_span - 1).max(fc + f.column_span - 1)
  let mut changed = true
  while changed {
    changed = false
    for row in top..<=bottom {
      for column in left..<=right {
        let (r, c) = self.owners[row][column]
        let cell = self.rows[r].cells[c]
        let next = (
          top.min(r),
          bottom.max(r + cell.row_span - 1),
          left.min(c),
          right.max(c + cell.column_span - 1),
        )
        if next != (top, bottom, left, right) {
          top = next.0
          bottom = next.1
          left = next.2
          right = next.3
          changed = true
        }
      }
    }
  }
  let mut owners = 0
  for row in top..<=bottom {
    for column in left..<=right {
      if self.rows[row].cells[column].owner() {
        owners += 1
      }
    }
  }
  { top, bottom, left, right, owners, }
}

///|
fn DrawingTable::cell_at(
  self : DrawingTable,
  position : Int,
) -> (Int, Int) raise @failure.Failure {
  let mut offset = 0
  for row, item in self.rows {
    for column, cell in item.cells {
      if !cell.owner() {
        continue
      }
      let length = cell.paragraphs.fold(init=-1, (sum, p) => {
        sum + paragraph_length(p) + 1
      })
      if position <= offset + length {
        return (row, column)
      }
      offset += length + 1
    }
  }
  @failure.reject("invalid-position", "Position exceeds table text")
}

///|
fn DrawingTable::cell_offset(
  self : DrawingTable,
  row : Int,
  column : Int,
) -> Int {
  let (row, column) = self.owners[row][column]
  let mut offset = 0
  for r, item in self.rows {
    for c, cell in item.cells {
      if !cell.owner() {
        continue
      }
      if r == row && c == column {
        return offset
      }
      offset += cell.paragraphs.fold(init=0, (sum, p) => {
        sum + paragraph_length(p) + 1
      })
    }
  }
  abort("Table cell must exist")
}

///|
fn Session::table_position(
  self : Session,
  object : Object,
  selection : Selection,
) -> (Int, Int, String) raise @failure.Failure {
  let table = object.table.unwrap()
  let (row, column) = if selection.mode == "text" {
    table.cell_at(selection.focus)
  } else {
    (0, 0)
  }
  let reason = if !self.current().read_only.is_empty() {
    self.current().read_only
  } else if object.read_only !=
    "Table object transforms and structure are not yet editable" {
    object.read_only
  } else if !object.text_reason.is_empty() {
    object.text_reason
  } else if object.source.tree.document
    .nodes()
    .any(node => {
      node.uri == presentation_uri &&
      node.name == "spTgt" &&
      node.attribute("spid").map(source_identity) ==
      object.source
      .child("nvGraphicFramePr", uri=presentation_uri)
      .bind(nv => nv.child("cNvPr", uri=presentation_uri))
      .bind(nv => nv.node.attribute("id"))
      .map(source_identity) &&
      !object.source.tree.children.get(node.id).unwrap_or([]).is_empty()
    }) {
    "Table structure changes require remapping its animation subtargets"
  } else {
    ""
  }
  (row, column, reason)
}

///|
fn Session::table_query(self : Session) -> Json raise @failure.Failure {
  let selection = self.candidate
    .map(candidate => candidate.selection)
    .unwrap_or(self.selection)
  guard selection.objects.length() == 1 else { return Json::null() }
  let object = self.current().object(selection.object)
  guard object.table is Some(table) else { return Json::null() }
  let (row, column, reason) = self.table_position(object, selection)
  let range = table.range(selection)
  let operations : Map[String, Json] = Map([])
  for
    operation in [
      "insertRowBefore", "insertRowAfter", "deleteRow", "insertColumnBefore", "insertColumnAfter",
      "deleteColumn", "merge", "unmerge",
    ] {
    operations[operation] = Json(
      if reason.is_empty() {
        self.table_operation_reason(object, range, operation)
      } else {
        reason
      },
    )
  }
  {
    "object": object.id,
    "rows": table.rows.length(),
    "columns": table.widths.length(),
    "row": row,
    "column": column,
    "firstRow": range.top,
    "lastRow": range.bottom,
    "firstColumn": range.left,
    "lastColumn": range.right,
    "reason": reason,
    "operations": Json(operations),
  }
}
