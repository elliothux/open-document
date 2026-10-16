///|
fn xlsx_cell_format(value : Json) -> @xlsx.CellFormat raise @failure.Failure {
  guard value is Object(fields) &&
    fields
    .keys()
    .all(key => {
      [
        "family", "size", "bold", "italic", "color", "fill", "horizontal", "vertical",
        "wrap", "numberFormat", "left", "right", "top", "bottom",
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
