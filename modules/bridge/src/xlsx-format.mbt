///|
fn xlsx_cell_format(value : Json) -> @xlsx.CellFormat raise @failure.Failure {
  guard value is Object(fields) &&
    fields
    .keys()
    .all(key => {
      [
        "family", "size", "bold", "italic", "underline", "strike", "script", "color",
        "fill", "horizontal", "vertical", "wrap", "numberFormat", "left", "right",
        "top", "bottom",
      ].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Unknown cell format fields")
  }
  let string = fn(key) raise @failure.Failure {
    if fields.contains(key) {
      Some(field_string(value, key))
    } else {
      None
    }
  }
  let boolean = fn(key) raise @failure.Failure {
    if fields.contains(key) {
      Some(xlsx_boolean(value, key))
    } else {
      None
    }
  }
  let border = fn(key) raise @failure.Failure {
    if fields.get(key) is Some(value) {
      guard value is Object(edge) &&
        edge.length() == 2 &&
        edge.contains("style") &&
        edge.contains("color") else {
        @failure.reject("invalid-operation", "Invalid cell border fields")
      }
      Some(@xlsx.CellBorder::{
        style: field_string(value, "style"),
        color: field_string(value, "color"),
      })
    } else {
      None
    }
  }
  @xlsx.CellFormat::new(
    family=string("family"),
    size=if fields.contains("size") {
      Some(xlsx_number(value, "size"))
    } else {
      None
    },
    bold=boolean("bold"),
    italic=boolean("italic"),
    underline=boolean("underline"),
    strike=boolean("strike"),
    script=string("script"),
    color=string("color"),
    fill=string("fill"),
    horizontal=string("horizontal"),
    vertical=string("vertical"),
    wrap=boolean("wrap"),
    numberFormat=string("numberFormat"),
    left=border("left"),
    right=border("right"),
    top=border("top"),
    bottom=border("bottom"),
  )
}

///|
fn xlsx_format_pattern(
  value : Json,
) -> Array[Array[@xlsx.CellFormat]] raise @failure.Failure {
  guard value is Array(rows) && rows.length() > 0 && rows.length() <= 4096 else {
    @failure.reject("invalid-operation", "Expected copied cell format rows")
  }
  let mut cells = 0
  rows.map(row => {
    guard row is Array(columns) && columns.length() > 0 else {
      @failure.reject(
        "invalid-operation", "Expected copied cell format columns",
      )
    }
    cells += columns.length()
    guard cells <= 4096 else {
      @failure.reject("limit-exceeded", "Copied format exceeds 4096 cells")
    }
    columns.map(xlsx_cell_format)
  })
}

///|
fn xlsx_copied_format(
  value : Json,
) -> (Array[Array[@xlsx.CellFormat]], Array[@xlsx.Range]) raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 2 &&
    fields.get("cells") is Some(cells) &&
    fields.get("merges") is Some(Array(merges)) &&
    merges.length() <= 1024 else {
    @failure.reject(
      "invalid-operation", "Expected copied format cells and merges",
    )
  }
  let pattern = xlsx_format_pattern(cells)
  let ranges = merges.map(merge => {
    guard merge is Object(fields) &&
      fields.length() == 4 &&
      fields.keys().all(key => ["top", "left", "bottom", "right"].contains(key)) else {
      @failure.reject("invalid-operation", "Invalid copied merged range")
    }
    @xlsx.Range::{
      top: field_int(merge, "top"),
      left: field_int(merge, "left"),
      bottom: field_int(merge, "bottom"),
      right: field_int(merge, "right"),
    }
  })
  (pattern, ranges)
}
