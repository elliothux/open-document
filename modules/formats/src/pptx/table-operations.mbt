///|
fn Session::check_table_operation(
  self : Session,
  object : Object,
  range : TableRange,
  operation : String,
) -> Unit raise @failure.Failure {
  let table = object.table.unwrap()
  if operation == "merge" {
    guard range.multiple() else {
      @failure.reject("invalid-operation", "Select multiple cells to merge")
    }
    let mut paragraphs = 0
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        let cell = table.rows[row].cells[column]
        if !cell.owner() {
          continue
        }
        paragraphs += cell.paragraphs.length()
        if cell.source.child("txBody").bind(body => body.child("lstStyle"))
          is Some(style) {
          guard style.node.attributes.is_empty() &&
            style.tree.children.get(style.node.id).unwrap_or([]).is_empty() else {
            @failure.reject(
              "protected-content", "Cell-local list styles require materialization before merging",
            )
          }
        }
      }
    }
    guard paragraphs <= 256 else {
      @failure.reject("limit-exceeded", "Merged cell paragraphs exceed budget")
    }
    return
  }
  if operation == "unmerge" {
    guard range.owners == 1 &&
      (range.top != range.bottom || range.left != range.right) else {
      @failure.reject("invalid-operation", "Select one merged cell to unmerge")
    }
    return
  }
  let rows = operation.contains("Row")
  let insert = operation.has_prefix("insert")
  let first = if rows { range.top } else { range.left }
  let last = if rows { range.bottom } else { range.right }
  let amount = last - first + 1
  let current_count = if rows {
    table.rows.length()
  } else {
    table.widths.length()
  }
  if !insert && amount == current_count {
    let reason = self.object_edit_reason(object, "delete")
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    return
  }
  let count = current_count + (if insert { amount } else { -amount })
  guard count <= (if rows { 1000 } else { 63 }) &&
    count * (if rows { table.widths.length() } else { table.rows.length() }) <=
    4096 else {
    @failure.reject("limit-exceeded", "Table dimensions exceed budget")
  }
  let at = if operation.has_suffix("Before") { first } else { last + 1 }
  for row, item in table.rows {
    for column, cell in item.cells {
      if !cell.owner() {
        continue
      }
      let start = if rows { row } else { column }
      let end = start +
        (if rows { cell.row_span } else { cell.column_span }) -
        1
      guard !insert || start >= at || at > end else {
        @failure.reject(
          "protected-content", "Cannot insert through an existing merged cell",
        )
      }
      guard insert ||
        start > last ||
        end < first ||
        (start >= first && end <= last) else {
        @failure.reject(
          "protected-content", "Select complete merged rows or columns before deleting",
        )
      }
    }
  }
}

///|
fn Session::table_operation_reason(
  self : Session,
  object : Object,
  range : TableRange,
  operation : String,
) -> String {
  try {
    self.check_table_operation(object, range, operation)
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}
