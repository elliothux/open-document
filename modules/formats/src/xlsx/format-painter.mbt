///|
fn format_numbers(
  tree : Tree,
  patches : Array[CellFormat],
) -> (Map[String, Int], Array[String]) raise @failure.Failure {
  let container = tree.one(tree.root("styleSheet").id, "numFmts")
  let nodes = container.map(node => tree.all(node.id, "numFmt")).unwrap_or([])
  let ids : Map[String, Int] = Map([])
  let used : Map[Int, Bool] = Map([])
  for node in nodes {
    let id = natural(node.attribute("numFmtId").unwrap_or(""), 65535)
    used[id] = true
    ids[node.attribute("formatCode").unwrap_or("")] = id
  }
  let additions : Array[String] = []
  let mut next = 164
  for patch in patches {
    if patch.numberFormat is Some(code) && !ids.contains(code) {
      while used.contains(next) {
        next += 1
      }
      guard next <= 65535 else {
        @failure.reject("limit-exceeded", "Number format identity exhausted")
      }
      ids[code] = next
      used[next] = true
      additions.push(
        "<od:numFmt xmlns:od=\"\{spreadsheet_uri}\" numFmtId=\"\{next}\" formatCode=\"\{escaped_attribute(code)}\"/>",
      )
    }
  }
  (ids, additions)
}

///|
/// Copies supported cell properties in source row/column order without editing the workbook.
pub fn Session::capture_format(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let (id, range) = self.selection
  let sheet = self.sheets[self.sheet_index(id)]
  let reason = self.format_reason(sheet, range)
  guard reason.is_empty() && !sheet.merges.any(merge => merge.intersects(range)) else {
    @failure.reject(
      "protected-content",
      if reason.is_empty() {
        "Merged cell format painting requires merge editing support"
      } else {
        reason
      },
    )
  }
  let rows : Array[Json] = []
  for row in range.top..<=range.bottom {
    let columns : Array[Json] = []
    for column in range.left..<=range.right {
      columns.push(
        Json::object(
          self.styles[sheet.style_at({ row, column, })].format_values(),
        ),
      )
    }
    rows.push(Json::array(columns))
  }
  Json::array(rows)
}

///|
/// Tiles a copied format rectangle over the selection, expanding a single-cell target.
pub fn Session::apply_format(
  self : Session,
  revision : Int,
  pattern : Array[Array[CellFormat]],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard pattern.length() > 0 &&
    pattern[0].length() > 0 &&
    pattern.length().to_int64() * pattern[0].length().to_int64() <= 4096L &&
    pattern.all(row => row.length() == pattern[0].length()) else {
    @failure.reject(
      "invalid-operation", "Expected a bounded rectangular cell format",
    )
  }
  for row in pattern {
    for patch in row {
      guard patch.family is Some(_) &&
        patch.size is Some(_) &&
        patch.bold is Some(_) &&
        patch.italic is Some(_) &&
        patch.color is Some(_) &&
        patch.fill is Some(_) &&
        patch.horizontal is Some(_) &&
        patch.vertical is Some(_) &&
        patch.wrap is Some(_) &&
        patch.numberFormat is Some(_) &&
        patch.left is Some(_) &&
        patch.right is Some(_) &&
        patch.top is Some(_) &&
        patch.bottom is Some(_) else {
        @failure.reject(
          "invalid-operation", "Copied cell formats require every property",
        )
      }
    }
  }
  let (_, selected) = self.selection
  let target = if selected.top == selected.bottom &&
    selected.left == selected.right {
    {
      ..selected,
      bottom: selected.top + pattern.length() - 1,
      right: selected.left + pattern[0].length() - 1,
    }
  } else {
    selected
  }
  guard target.bottom <= 1048576 && target.right <= 16384 else {
    @failure.reject(
      "invalid-operation", "Copied cell format leaves the worksheet",
    )
  }
  let sheet = self.sheets[self.sheet_index(self.selection.0)]
  guard !sheet.merges.any(merge => merge.intersects(target)) else {
    @failure.reject(
      "protected-content", "Merged cell format painting requires merge editing support",
    )
  }
  self.format_pattern(revision, pattern, target)
}
