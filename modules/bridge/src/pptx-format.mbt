///|
fn pptx_table_style(
  change : Json,
) -> @pptx.TableStyleSettings raise @failure.Failure {
  guard change is { "style": style, .. } &&
    style is Object(fields) &&
    fields.length() == 7 &&
    fields
    .keys()
    .all(key => {
      [
        "id", "firstRow", "lastRow", "firstColumn", "lastColumn", "bandRows", "bandColumns",
      ].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Invalid table style settings")
  }
  {
    id: field_string(style, "id"),
    first_row: xlsx_boolean(style, "firstRow"),
    last_row: xlsx_boolean(style, "lastRow"),
    first_column: xlsx_boolean(style, "firstColumn"),
    last_column: xlsx_boolean(style, "lastColumn"),
    band_rows: xlsx_boolean(style, "bandRows"),
    band_columns: xlsx_boolean(style, "bandColumns"),
  }
}

///|
fn pptx_text_format(value : Json) -> @pptx.TextFormat raise @failure.Failure {
  guard value is Object(fields) &&
    fields
    .keys()
    .all(key => {
      [
        "font", "size", "bold", "italic", "color", "underline", "strike", "highlight",
        "script", "spacing",
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
    spacing?=if fields.contains("spacing") {
      Some(xlsx_number(value, "spacing"))
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
    script?=if fields.contains("script") {
      Some(field_string(value, "script"))
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
      [
        "left", "right", "first", "before", "after", "line", "list", "level", "rtl",
        "listFont", "listSize", "listColor", "tabs", "defaultTab",
      ].contains(key)
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
    tabs?=fields
      .get("tabs")
      .map(v => {
        if v is Null {
          None
        } else {
          guard v is Array(tabs) && tabs.length() <= 32 else {
            @failure.reject("invalid-operation", "Invalid paragraph tabs")
          }
          Some(
            tabs.map(tab => {
              guard tab is Object(values) &&
                values.length() == 2 &&
                values.contains("position") &&
                values.contains("align") else {
                @failure.reject(
                  "invalid-operation", "Invalid paragraph tab fields",
                )
              }
              @pptx.ParagraphTab::{
                position: xlsx_number(tab, "position"),
                align: field_string(tab, "align"),
              }
            }),
          )
        }
      }),
    default_tab?=fields
      .get("defaultTab")
      .map(v => {
        if v is Null {
          None
        } else {
          Some(xlsx_number(value, "defaultTab"))
        }
      }),
    rtl?=if fields.contains("rtl") {
      Some(xlsx_boolean(value, "rtl"))
    } else {
      None
    },
    left?=number("left"),
    right?=number("right"),
    first?=number("first"),
    before?=spacing("before"),
    after?=spacing("after"),
    line?=spacing("line"),
    level?=if fields.contains("level") {
      Some(field_int(value, "level"))
    } else {
      None
    },
    list?=fields.get("list").map(pptx_list_format),
    list_font?=fields
      .get("listFont")
      .map(v => {
        if v is Null {
          None
        } else {
          Some(field_string(value, "listFont"))
        }
      }),
    list_size?=fields
      .get("listSize")
      .map(v => if v is Null { None } else { Some(pptx_text_spacing(v)) }),
    list_color?=fields
      .get("listColor")
      .map(v => {
        if v is Null {
          None
        } else {
          Some(field_string(value, "listColor"))
        }
      }),
  )
}

///|
fn pptx_list_format(value : Json) -> @pptx.ListFormat raise @failure.Failure {
  guard value is Object(fields) else {
    @failure.reject("invalid-operation", "List format is required")
  }
  let kind = field_string(value, "kind")
  let keys = match kind {
    "none" => ["kind"]
    "bullet" => ["kind", "value"]
    "number" => ["kind", "value", "start"]
    _ => []
  }
  guard !keys.is_empty() && fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Unknown list format fields")
  }
  match kind {
    "none" => @pptx.NoList
    "bullet" => @pptx.Bullet(field_string(value, "value"))
    _ => @pptx.Numbered(field_string(value, "value"), field_int(value, "start"))
  }
}

///|
fn pptx_gradient_stops(
  value : Json,
) -> Array[@layout.GradientStop] raise @failure.Failure {
  guard value is { "stops": Array(stops), .. } &&
    stops.length() >= 2 &&
    stops.length() <= 32 else {
    @failure.reject("invalid-operation", "Gradients require 2..32 stops")
  }
  stops.map(stop => {
    guard stop is Object(fields) &&
      fields.length() == 3 &&
      fields.contains("position") &&
      fields.contains("opacity") &&
      fields.contains("color") else {
      @failure.reject(
        "invalid-operation", "Gradient stops require position, color and opacity",
      )
    }
    {
      position: xlsx_number(stop, "position"),
      color: field_string(stop, "color"),
      opacity: xlsx_number(stop, "opacity"),
    }
  })
}

///|
fn pptx_gradient_edit(value : Json) -> @pptx.ObjectEdit raise @failure.Failure {
  if field_string(value, "action") == "radialGradientFill" {
    @pptx.RadialGradientFill(pptx_gradient_stops(value))
  } else {
    @pptx.GradientFill(
      pptx_gradient_stops(value),
      xlsx_number(value, "angle"),
      xlsx_boolean(value, "scaled"),
    )
  }
}
