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
fn list_edit(request : Json) -> @docx.ListEdit raise @failure.Failure {
  guard request is { "change": Object(fields) as change, .. } else {
    @failure.reject("invalid-operation", "Invalid list edit")
  }
  let action = field_string(change, "action")
  let allowed = match action {
    "create" => ["action", "format"]
    "apply" => ["action", "id", "level"]
    "remove" => ["action"]
    "restart" => ["action", "start"]
    "level" => ["action", "increase"]
    _ => @failure.reject("invalid-operation", "Invalid list edit action")
  }
  guard fields.length() == allowed.length() &&
    fields.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid list edit fields")
  }
  match action {
    "create" => @docx.Create(field_string(change, "format"))
    "apply" => @docx.Apply(field_int(change, "id"), field_int(change, "level"))
    "remove" => @docx.Remove
    "level" =>
      match fields.get("increase") {
        Some(True) => @docx.Level(true)
        Some(False) => @docx.Level(false)
        _ =>
          @failure.reject("invalid-operation", "Invalid list level direction")
      }
    _ => @docx.Restart(field_int(change, "start"))
  }
}

///|
fn list_level_format(
  request : Json,
) -> @docx.ListLevelFormat raise @failure.Failure {
  guard request is { "definition": Object(fields) as definition, .. } &&
    fields
    .keys()
    .all(key => {
      [
        "format", "pattern", "start", "restart", "align", "suffix", "left", "first",
        "character",
      ].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Invalid list level fields")
  }
  @docx.ListLevelFormat::new(
    field_string(definition, "format"),
    field_string(definition, "pattern"),
    start=field_int(definition, "start"),
    restart=match fields.get("restart") {
      Some(Null) => None
      Some(_) => Some(field_int(definition, "restart"))
      None => @failure.reject("invalid-operation", "Missing restart rule")
    },
    align=field_string(definition, "align"),
    suffix=field_string(definition, "suffix"),
    left=format_number(fields, "left"),
    first=format_number(fields, "first"),
    character=character_format({
      "format": fields.get("character").unwrap_or({}),
    }),
  )
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
    "style", "family", "size", "color", "bold", "italic", "underline", "strike",
    "highlight", "vertAlign",
  ])
  @docx.CharacterFormat::new(
    style=format_string(fields, "style"),
    family=format_string(fields, "family"),
    size=format_number(fields, "size"),
    color=format_string(fields, "color"),
    bold=format_boolean(fields, "bold"),
    italic=format_boolean(fields, "italic"),
    underline=format_boolean(fields, "underline"),
    strike=format_boolean(fields, "strike"),
    highlight=format_string(fields, "highlight"),
    vertAlign=format_string(fields, "vertAlign"),
  )
}

///|
fn paragraph_format(
  request : Json,
) -> @docx.ParagraphFormat raise @failure.Failure {
  let fields = format_fields(request, [
    "style", "align", "before", "after", "left", "right", "first", "line", "tabs",
    "pageBreakBefore", "rtl", "keepLines", "keepNext", "widowControl",
  ])
  @docx.ParagraphFormat::new(
    style=format_string(fields, "style"),
    align=format_string(fields, "align"),
    rtl=format_boolean(fields, "rtl"),
    before=format_number(fields, "before"),
    after=format_number(fields, "after"),
    left=format_number(fields, "left"),
    right=format_number(fields, "right"),
    first=format_number(fields, "first"),
    tabs=match fields.get("tabs") {
      None => @docx.Keep
      Some(Null) => @docx.Clear
      Some(Array(values)) => {
        guard values.length() <= 64 else {
          @failure.reject("limit-exceeded", "Too many tab stops")
        }
        @docx.Set(
          values.map(value => {
            guard value is Object(fields) &&
              fields
              .keys()
              .all(key => ["position", "align", "leader"].contains(key)) &&
              value
              is {
                "position": Number(position, ..),
                "align": String(align),
                ..
              } else {
              @failure.reject("invalid-operation", "Invalid tab stop")
            }
            let leader = match fields.get("leader") {
              None => "none"
              Some(String(value)) => value
              _ => @failure.reject("invalid-operation", "Invalid tab leader")
            }
            { position, align, leader, }
          }),
        )
      }
      _ => @failure.reject("invalid-operation", "Invalid tab stops")
    },
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
    keepLines=format_boolean(fields, "keepLines"),
    keepNext=format_boolean(fields, "keepNext"),
    widowControl=format_boolean(fields, "widowControl"),
  )
}
