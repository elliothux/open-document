///|
fn Axis::uniform(self : Axis, first : Int, last : Int) -> Double? {
  let size = self.size(first)
  let mut cursor = first
  for span in self.spans {
    if span.last < first {
      continue
    }
    if span.first > last {
      break
    }
    if (span.first > cursor && self.default_size != size) || span.size != size {
      return None
    }
    cursor = span.last + 1
  }
  if cursor <= last && self.default_size != size {
    None
  } else {
    Some(size)
  }
}

///|
fn Session::dimension_reason(self : Session, sheet : Sheet) -> String {
  if !self.read_only.is_empty() {
    self.read_only
  } else if sheet.locked {
    "Worksheet is protected"
  } else {
    ""
  }
}

///|
fn Sheet::row_height_changes(
  self : Sheet,
  tree : Tree,
  sizes : Map[Int, Double],
  best_fit~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let metadata : Map[Int, Array[(String, String)]] = Map([])
  for number, size in sizes {
    let values = if size == 0 {
      [("hidden", "1")]
    } else {
      [
        ("ht", size.to_string()),
        ("customHeight", if best_fit { "0" } else { "1" }),
        ("hidden", "0"),
      ]
    }
    if best_fit {
      values.retain(entry => entry.0 != "hidden")
      if self.dimensions.rows.size(number) == 0 {
        values.push(("hidden", "1"))
      }
    }
    metadata[number] = values
  }
  self.row_metadata_changes(tree, metadata)
}

///|
fn Sheet::column_width_changes(
  self : Sheet,
  tree : Tree,
  first : Int,
  last : Int,
  sizes : Array[AxisSpan],
  best_fit~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  self.column_metadata_changes(
    tree,
    first,
    last,
    sizes.map(span => {
      let attributes = if span.size == 0 {
        [("hidden", "1")]
      } else {
        [
          ("width", span.size.to_string()),
          ("customWidth", "1"),
          ("bestFit", if best_fit { "1" } else { "0" }),
          ("hidden", "0"),
        ]
      }
      (span.first, span.last, attributes)
    }),
  )
}

///|
fn Session::resize_dimensions(
  self : Session,
  sheet : String,
  first : Int,
  last : Int,
  size : Double,
  rows~ : Bool,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard first >= 1 &&
    last >= first &&
    last <= (if rows { 1048576 } else { 16384 }) &&
    !size.is_nan() &&
    !size.is_inf() &&
    size >= 0 &&
    size <= (if rows { 409.5 } else { 255.0 }) else {
    @failure.reject("invalid-operation", "Invalid row or column dimensions")
  }
  let tree = Tree::new(current.document)
  let changes = if rows {
    guard last - first < 4096 else {
      @failure.reject("limit-exceeded", "Row height edit exceeds 4096 rows")
    }
    let sizes : Map[Int, Double] = Map([])
    for axis in first..<=last {
      sizes[axis] = size
    }
    current.row_height_changes(tree, sizes)
  } else {
    current.column_width_changes(tree, first, last, [{ first, last, size, }])
  }
  let mut document = current.document
  let edits : Array[(String, @xml.Edit)] = []
  if !changes.is_empty() {
    let (next, edit) = document.edit_source(changes)
    document = next
    edits.push((current.id, edit))
  }
  if rows {
    let (next, filter_edits) = self.filter_dimension_changes(
      current, document, first, last, size,
    )
    document = next
    edits.append(filter_edits)
  }
  if document.source() == current.document.source() {
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let calculation = Calculation::build(
    sheets,
    None,
    [],
    self.date1904,
    self.workbook,
  )
  if calculation.visibility_dependent() {
    edits.append(self.cache_edits(sheets, calculation))
  }
  self.commit(sheets, self.workbook, calculation, edits, self.selection)
  self.query()
}
