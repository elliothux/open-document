///|
priv struct CellFormatRequest {
  value : @model.CellFormat
}

///|
impl @json.FromJson for CellFormatRequest with fn from_json(value, path) {
  guard value is Object(fields) &&
    fields.values().all(field => !(field is Null)) &&
    fields
    .keys()
    .all(key => {
      [
        "family", "size", "bold", "italic", "underline", "strike", "script", "color",
        "fill", "horizontal", "vertical", "wrap", "numberFormat", "left", "right",
        "top", "bottom", "locked", "formulaHidden", "indent", "shrinkToFit", "textRotation",
      ].contains(key)
    }) else {
    raise @json.JsonDecodeError((path, "Invalid cell format fields"))
  }
  for key in ["left", "right", "top", "bottom"] {
    if fields.get(key) is Some(value) {
      guard value is Object(edge) &&
        edge.length() == 2 &&
        edge.contains("style") &&
        edge.contains("color") else {
        raise @json.JsonDecodeError(
          (path.add_key(key), "Invalid cell border fields"),
        )
      }
    }
  }
  if fields.get("size") is Some(value) {
    let _ : @common.RequestNumber = @json.from_json(
      value,
      path=path.add_key("size"),
    )
  }
  for key in ["indent", "textRotation"] {
    if fields.get(key) is Some(value) {
      let _ : @common.RequestInt = @json.from_json(
        value,
        path=path.add_key(key),
      )
    }
  }
  { value: @json.from_json(value, path~), }
}

///|
fn xlsx_cell_format(value : Json) -> @model.CellFormat raise @failure.Failure {
  let request : CellFormatRequest = @common.request(value)
  request.value
}

///|
fn xlsx_format_pattern(
  value : Json,
) -> Array[Array[@model.CellFormat]] raise @failure.Failure {
  guard value is Array(rows) &&
    rows.length() > 0 &&
    rows.length() <= @model.CellFragmentCells else {
    @failure.reject("invalid-operation", "Expected copied cell format rows")
  }
  let mut cells = 0
  rows.map(row => {
    guard row is Array(columns) && columns.length() > 0 else {
      @failure.reject(
        "invalid-operation", "Expected copied cell format columns",
      )
    }
    guard columns.length() <= @model.CellFragmentCells - cells else {
      @failure.reject(
        "limit-exceeded",
        "Copied format exceeds \{@model.CellFragmentCells} cells",
      )
    }
    cells += columns.length()
    columns.map(xlsx_cell_format)
  })
}

///|
fn copied_merge_items(value : Json) -> Array[Json] raise @failure.Failure {
  guard value is Array(merges) && merges.length() <= @model.CellFragmentMerges else {
    @failure.reject("invalid-operation", "Expected bounded copied merges")
  }
  merges
}

///|
fn xlsx_copied_format(
  value : Json,
) -> (Array[Array[@model.CellFormat]], Array[@model.Range]) raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 2 &&
    fields.get("cells") is Some(cells) &&
    fields.get("merges") is Some(raw_merges) else {
    @failure.reject(
      "invalid-operation", "Expected copied format cells and merges",
    )
  }
  let merges = copied_merge_items(raw_merges)
  (xlsx_format_pattern(cells), merges.map(copied_range))
}
