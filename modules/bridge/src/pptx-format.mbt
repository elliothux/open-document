///|
fn pptx_text_format(value : Json) -> @pptx.TextFormat raise @failure.Failure {
  guard value is Object(fields) &&
    fields
    .keys()
    .all(key => {
      [
        "font", "size", "bold", "italic", "color", "underline", "strike", "highlight",
      ].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Unknown text format fields")
  }
  @pptx.TextFormat::new(
    font?=if fields.contains("font") {
      Some(field_string(value, "font"))
    } else {
      None
    },
    size?=if fields.contains("size") {
      Some(xlsx_number(value, "size"))
    } else {
      None
    },
    bold?=if fields.contains("bold") {
      Some(xlsx_boolean(value, "bold"))
    } else {
      None
    },
    italic?=if fields.contains("italic") {
      Some(xlsx_boolean(value, "italic"))
    } else {
      None
    },
    color?=if fields.contains("color") {
      Some(field_string(value, "color"))
    } else {
      None
    },
    underline?=if fields.contains("underline") {
      Some(xlsx_boolean(value, "underline"))
    } else {
      None
    },
    strike?=if fields.contains("strike") {
      Some(xlsx_boolean(value, "strike"))
    } else {
      None
    },
    highlight?=if fields.contains("highlight") {
      Some(field_string(value, "highlight"))
    } else {
      None
    },
  )
}

///|
fn pptx_text_spacing(value : Json) -> @pptx.TextSpacing raise @failure.Failure {
  guard value is Object(fields) &&
    fields.keys().all(key => ["unit", "value"].contains(key)) else {
    @failure.reject("invalid-operation", "Unknown paragraph spacing fields")
  }
  { unit: field_string(value, "unit"), value: xlsx_number(value, "value"), }
}

///|
fn pptx_paragraph_format(
  value : Json,
) -> @pptx.ParagraphFormat raise @failure.Failure {
  guard value is Object(fields) &&
    fields
    .keys()
    .all(key => {
      ["left", "right", "first", "before", "after", "line"].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Unknown paragraph format fields")
  }
  let number = fn(key) raise @failure.Failure {
    if fields.contains(key) {
      Some(xlsx_number(value, key))
    } else {
      None
    }
  }
  let spacing = fn(key) raise @failure.Failure {
    fields.get(key).map(pptx_text_spacing)
  }
  @pptx.ParagraphFormat::new(
    left?=number("left"),
    right?=number("right"),
    first?=number("first"),
    before?=spacing("before"),
    after?=spacing("after"),
    line?=spacing("line"),
  )
}
