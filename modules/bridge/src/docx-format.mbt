///|
fn format_fields(
  request : Json,
  allowed : Array[String],
) -> Map[String, Json] raise @failure.Failure {
  guard request is { "format": Object(fields), .. } &&
    fields.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid formatting properties")
  }
  fields
}

///|
fn format_string(
  fields : Map[String, Json],
  key : String,
) -> @docx.FormatChange[String] raise @failure.Failure {
  match fields.get(key) {
    None => @docx.Keep
    Some(Null) => @docx.Clear
    Some(String(value)) => @docx.Set(value)
    _ =>
      @failure.reject(
        "invalid-operation",
        "Expected string formatting property: " + key,
      )
  }
}

///|
fn format_number(
  fields : Map[String, Json],
  key : String,
) -> @docx.FormatChange[Double] raise @failure.Failure {
  match fields.get(key) {
    None => @docx.Keep
    Some(Null) => @docx.Clear
    Some(Number(value, ..)) => @docx.Set(value)
    _ =>
      @failure.reject(
        "invalid-operation",
        "Expected numeric formatting property: " + key,
      )
  }
}

///|
fn format_boolean(
  fields : Map[String, Json],
  key : String,
) -> @docx.FormatChange[Bool] raise @failure.Failure {
  match fields.get(key) {
    None => @docx.Keep
    Some(Null) => @docx.Clear
    Some(True) => @docx.Set(true)
    Some(False) => @docx.Set(false)
    _ =>
      @failure.reject(
        "invalid-operation",
        "Expected boolean formatting property: " + key,
      )
  }
}

///|
fn character_format(
  request : Json,
) -> @docx.CharacterFormat raise @failure.Failure {
  let fields = format_fields(request, [
    "family", "size", "color", "bold", "italic",
  ])
  @docx.CharacterFormat::new(
    family=format_string(fields, "family"),
    size=format_number(fields, "size"),
    color=format_string(fields, "color"),
    bold=format_boolean(fields, "bold"),
    italic=format_boolean(fields, "italic"),
  )
}

///|
fn paragraph_format(
  request : Json,
) -> @docx.ParagraphFormat raise @failure.Failure {
  let fields = format_fields(request, [
    "align", "before", "after", "left", "right", "first", "line", "pageBreakBefore",
  ])
  @docx.ParagraphFormat::new(
    align=format_string(fields, "align"),
    before=format_number(fields, "before"),
    after=format_number(fields, "after"),
    left=format_number(fields, "left"),
    right=format_number(fields, "right"),
    first=format_number(fields, "first"),
    line=match fields.get("line") {
      None => @docx.Keep
      Some(Null) => @docx.Clear
      Some({ "rule": String(rule), "value": Number(value, ..), .. } as line) => {
        guard line is Object(values) && values.length() == 2 else {
          @failure.reject("invalid-operation", "Invalid line spacing fields")
        }
        @docx.Set(
          match rule {
            "auto" => @layout.Auto(value)
            "exact" => @layout.Exact(value)
            "atLeast" => @layout.AtLeast(value)
            _ =>
              @failure.reject("invalid-operation", "Invalid line spacing rule")
          },
        )
      }
      _ => @failure.reject("invalid-operation", "Invalid line spacing")
    },
    pageBreakBefore=format_boolean(fields, "pageBreakBefore"),
  )
}
