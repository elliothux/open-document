///|
#derive(@json.FromJson)
priv struct BookmarkNameRequest {
  name : String
}

///|
#derive(@json.FromJson)
priv struct BookmarkRenameRequest {
  name : String
  replacement : String
}

///|
fn bookmark_edit(change : Json) -> @model.BookmarkEdit raise @failure.Failure {
  guard change is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid bookmark command")
  }
  let command : @common.ActionRequest = @common.request(change)
  let action = command.action
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
  let bookmark : BookmarkNameRequest = @common.request(change)
  match action {
    "create" => @model.CreateBookmark(bookmark.name, field_selection(change))
    "rename" => {
      let rename : BookmarkRenameRequest = @common.request(change)
      @model.RenameBookmark(rename.name, rename.replacement)
    }
    "goTo" => @model.GoToBookmark(bookmark.name)
    _ => @model.RemoveBookmark(bookmark.name)
  }
}

///|
fn format_fields(
  format : Json,
  allowed : Array[String],
) -> Map[String, Json] raise @failure.Failure {
  guard format is Object(fields) &&
    fields.keys().all(key => allowed.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid formatting properties")
  }
  fields
}

///|
#derive(@json.FromJson)
priv struct ListCreateRequest {
  format : String
}

///|
#derive(@json.FromJson)
priv struct ListApplyRequest {
  id : @common.RequestInt
  level : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct ListDirectionRequest {
  increase : Bool
}

///|
#derive(@json.FromJson)
priv struct ListRestartRequest {
  start : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct ListLevelFormatRequest {
  format : String
  pattern : String
  start : @common.RequestInt
  restart : @common.RequiredNullable[@common.RequestInt]
  align : String
  suffix : String
}

///|
fn list_edit(change : Json) -> @model.ListEdit raise @failure.Failure {
  guard change is Object(fields) else {
    @failure.reject("invalid-operation", "Invalid list edit")
  }
  let command : @common.ActionRequest = @common.request(change)
  let action = command.action
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
    "create" => {
      let command : ListCreateRequest = @common.request(change)
      @model.Create(command.format)
    }
    "apply" => {
      let command : ListApplyRequest = @common.request(change)
      @model.Apply(command.id.value, command.level.value)
    }
    "remove" => @model.Remove
    "level" => {
      let command : ListDirectionRequest = @common.request(change)
      @model.Level(command.increase)
    }
    _ => {
      let command : ListRestartRequest = @common.request(change)
      @model.Restart(command.start.value)
    }
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
  let command : ListLevelFormatRequest = @common.request(definition)
  @model.ListLevelFormat::new(
    command.format,
    command.pattern,
    start=command.start.value,
    restart=command.restart.value.map(index => index.value),
    align=command.align,
    suffix=command.suffix,
    left=format_number(fields, "left"),
    first=format_number(fields, "first"),
    character=character_format(fields.get("character").unwrap_or({})),
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
  format : Json,
) -> @model.CharacterFormat raise @failure.Failure {
  let fields = format_fields(format, [
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
  format : Json,
) -> @model.ParagraphFormat raise @failure.Failure {
  let fields = format_fields(format, [
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
        guard values.length() <= @layout.TabStopCount else {
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
#derive(@json.FromJson)
priv struct UpdateStyleRequest {
  revision : @common.RequestInt
  key : String
}

///|
fn Context::edit_docx_style(
  self : Context,
  session : @model.Session,
  request : Json,
  update : Bool,
) -> Json raise @failure.Failure {
  guard request is { "format": Object(fields) as format, .. } &&
    fields
    .keys()
    .all(key => {
      (if update {
        ["character", "paragraph", "name", "basedOn", "reset"]
      } else {
        ["character", "paragraph"]
      }).contains(key)
    }) &&
    format is { "character": character, "paragraph": paragraph, .. } else {
    @failure.reject("invalid-operation", "Invalid copied format")
  }
  let (revision, result) = if update {
    let command : UpdateStyleRequest = @common.request(request)
    let revision = command.revision.value
    let name = match fields.get("name") {
      Some(String(name)) => Some(name)
      None => None
      _ => @failure.reject("invalid-operation", "Invalid style name")
    }
    let result = session.update_style(
      revision,
      command.key,
      character_format(character),
      paragraph_format(paragraph),
      name~,
      based_on=format_string(fields, "basedOn"),
      reset=match fields.get("reset") {
        None => false
        Some(True) => true
        _ => @failure.reject("invalid-operation", "Invalid style reset flag")
      },
    )
    (revision, result)
  } else {
    let command : FormatSelectionRequest = @common.request(request)
    let revision = command.revision.value
    let result = session.apply_format(
      revision,
      command.selection.selection(),
      character_format(character),
      paragraph_format(paragraph),
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
    (revision, result)
  }
  self.clear_edit_layout(result, previous=revision)
}
