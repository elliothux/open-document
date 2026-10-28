///|
fn bookmark_edit(request : Json) -> @model.BookmarkEdit raise @failure.Failure {
  guard request is { "change": Object(fields) as change, .. } else {
    @failure.reject("invalid-operation", "Invalid bookmark command")
  }
  let action = field_string(change, "action")
  let allowed = match action {
    "create" => ["action", "name", "selection"]
    "rename" => ["action", "name", "replacement"]
    "remove" | "goTo" => ["action", "name"]
    _ => @failure.reject("invalid-operation", "Unknown bookmark command")
  }
  guard fields.length() == allowed.length() &&
    fields.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid bookmark fields")
  }
  let name = field_string(change, "name")
  match action {
    "create" => @model.CreateBookmark(name, field_selection(change))
    "rename" => @model.RenameBookmark(name, field_string(change, "replacement"))
    "goTo" => @model.GoToBookmark(name)
    _ => @model.RemoveBookmark(name)
  }
}

///|
fn edit_docx_format(
  session : @model.Session,
  request : Json,
  operation : String,
  revision : Int32,
  probe : @layout.TextProbe,
  images : @layout.Images,
) -> Json raise @failure.Failure {
  match operation {
    "editBookmark" => session.edit_bookmark(revision, bookmark_edit(request))
    "editDocxComment" =>
      session.edit_comment(revision, docx_comment_edit(request))
    "setHyperlink" =>
      session.set_hyperlink(
        revision,
        field_selection(request),
        field_hyperlink_target(request),
        text=field_hyperlink_text(request),
      )
    "setCharacterFormat" =>
      session.set_character_format(
        revision,
        field_selection(request),
        character_format(request),
        probe~,
        profile=font_profile(request),
        images~,
      )
    _ =>
      session.set_paragraph_format(
        revision,
        field_selection(request),
        paragraph_format(request),
        probe~,
        profile=font_profile(request),
        images~,
      )
  }
}

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
fn field_hyperlink_target(request : Json) -> String? raise @failure.Failure {
  guard request is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid hyperlink request")
  }
  match fields.get("target") {
    Some(Null) => None
    Some(String(target)) => Some(target)
    _ => @failure.reject("invalid-operation", "Invalid hyperlink target")
  }
}

///|
fn field_hyperlink_text(request : Json) -> String? raise @failure.Failure {
  guard request is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid hyperlink request")
  }
  match fields.get("text") {
    None => None
    Some(String(text)) => Some(text)
    _ => @failure.reject("invalid-operation", "Invalid hyperlink display text")
  }
}

///|
fn list_edit(request : Json) -> @model.ListEdit raise @failure.Failure {
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
    "create" => @model.Create(field_string(change, "format"))
    "apply" => @model.Apply(field_int(change, "id"), field_int(change, "level"))
    "remove" => @model.Remove
    "level" =>
      match fields.get("increase") {
        Some(True) => @model.Level(true)
        Some(False) => @model.Level(false)
        _ =>
          @failure.reject("invalid-operation", "Invalid list level direction")
      }
    _ => @model.Restart(field_int(change, "start"))
  }
}

///|
fn list_level_format(
  request : Json,
) -> @model.ListLevelFormat raise @failure.Failure {
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
  @model.ListLevelFormat::new(
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
) -> @model.FormatChange[String] raise @failure.Failure {
  match fields.get(key) {
    None => @model.Keep
    Some(Null) => @model.Clear
    Some(String(value)) => @model.Set(value)
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
) -> @model.FormatChange[Double] raise @failure.Failure {
  match fields.get(key) {
    None => @model.Keep
    Some(Null) => @model.Clear
    Some(Number(value, ..)) => @model.Set(value)
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
) -> @model.FormatChange[Bool] raise @failure.Failure {
  match fields.get(key) {
    None => @model.Keep
    Some(Null) => @model.Clear
    Some(True) => @model.Set(true)
    Some(False) => @model.Set(false)
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
) -> @model.CharacterFormat raise @failure.Failure {
  let fields = format_fields(request, [
    "style", "family", "size", "color", "bold", "italic", "underline", "strike",
    "highlight", "vertAlign", "spacing",
  ])
  @model.CharacterFormat::new(
    style=format_string(fields, "style"),
    family=format_string(fields, "family"),
    size=format_number(fields, "size"),
    spacing=format_number(fields, "spacing"),
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
) -> @model.ParagraphFormat raise @failure.Failure {
  let fields = format_fields(request, [
    "style", "align", "before", "after", "left", "right", "first", "line", "tabs",
    "pageBreakBefore", "rtl", "keepLines", "keepNext", "widowControl",
  ])
  @model.ParagraphFormat::new(
    style=format_string(fields, "style"),
    align=format_string(fields, "align"),
    rtl=format_boolean(fields, "rtl"),
    before=format_number(fields, "before"),
    after=format_number(fields, "after"),
    left=format_number(fields, "left"),
    right=format_number(fields, "right"),
    first=format_number(fields, "first"),
    tabs=match fields.get("tabs") {
      None => @model.Keep
      Some(Null) => @model.Clear
      Some(Array(values)) => {
        guard values.length() <= 64 else {
          @failure.reject("limit-exceeded", "Too many tab stops")
        }
        @model.Set(
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
      None => @model.Keep
      Some(Null) => @model.Clear
      Some({ "rule": String(rule), "value": Number(value, ..), .. } as line) => {
        guard line is Object(values) && values.length() == 2 else {
          @failure.reject("invalid-operation", "Invalid line spacing fields")
        }
        @model.Set(
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

///|
fn Context::edit_docx_style(
  self : Context,
  session : @model.Session,
  request : Json,
  operation : String,
) -> Json raise @failure.Failure {
  guard request is { "format": Object(fields) as format, .. } &&
    fields
    .keys()
    .all(key => {
      (if operation == "updateStyle" {
        ["character", "paragraph", "name", "basedOn", "reset"]
      } else {
        ["character", "paragraph"]
      }).contains(key)
    }) &&
    format is { "character": character, "paragraph": paragraph, .. } else {
    @failure.reject("invalid-operation", "Invalid copied format")
  }
  let revision = field_int(request, "revision")
  let result = if operation == "updateStyle" {
    let name = match fields.get("name") {
      Some(String(name)) => Some(name)
      None => None
      _ => @failure.reject("invalid-operation", "Invalid style name")
    }
    session.update_style(
      revision,
      field_string(request, "key"),
      character_format({ "format": character }),
      paragraph_format({ "format": paragraph }),
      name~,
      based_on=format_string(fields, "basedOn"),
      reset=match fields.get("reset") {
        None => false
        Some(True) => true
        _ => @failure.reject("invalid-operation", "Invalid style reset flag")
      },
    )
  } else {
    session.apply_format(
      revision,
      field_selection(request),
      character_format({ "format": character }),
      paragraph_format({ "format": paragraph }),
      probe=self.probe,
      profile=font_profile(request),
      images=self.images,
    )
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
