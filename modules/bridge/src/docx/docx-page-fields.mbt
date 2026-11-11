///|
priv struct BodyPageFieldCommandRequest {
  revision : @common.RequestInt
  field : BodyPageFieldRequest
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct BodyPageFieldRequest {
  code : String
}

///|
priv struct BodyFieldKindRequest {
  field : String
  format : String?
} derive(@json.FromJson)

///|
priv struct SequenceFieldRequest {
  sequence : String
  restart : @common.RequestInt?
  repeat : Bool?
  headingLevel : @common.RequestInt?
  hidden : Bool?
} derive(@json.FromJson)

///|
priv struct ReferenceFieldRequest {
  bookmark : String
  hyperlink : Bool?
  relative : Bool?
  superscript : Bool?
  numbering : String?
  separator : String?
} derive(@json.FromJson)

///|
fn sequence_field_code(
  sequence : SequenceFieldRequest,
  format : String,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  let repeat = sequence.repeat.unwrap_or(false)
  guard !repeat || sequence.restart is None else {
    raise @json.JsonDecodeError((path, "Invalid sequence restart"))
  }
  let restart = sequence.restart
    .map(value => ":restart=" + value.value.to_string())
    .unwrap_or("")
  let heading = match sequence.headingLevel {
    Some(level) => {
      guard level.value >= 1 && level.value <= 9 else {
        raise @json.JsonDecodeError((path, "Invalid sequence heading level"))
      }
      ":heading=" + level.value.to_string()
    }
    None => ""
  }
  "SEQ:" +
  sequence.sequence +
  format +
  (if repeat { ":repeat" } else { restart }) +
  heading +
  (if sequence.hidden.unwrap_or(false) { ":hidden" } else { "" })
}

///|
fn reference_field_code(
  reference : ReferenceFieldRequest,
  field : String,
  format : String,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  let numbering = match reference.numbering {
    None => ""
    Some("noContext") => ":number"
    Some("relative") => ":numberRelative"
    Some("fullContext") => ":numberFull"
    Some(_) =>
      raise @json.JsonDecodeError((path, "Invalid reference numbering mode"))
  }
  field +
  ":" +
  reference.bookmark +
  format +
  (if reference.superscript.unwrap_or(false) { ":superscript" } else { "" }) +
  numbering +
  (if reference.hyperlink.unwrap_or(false) { ":hyperlink" } else { "" }) +
  (if reference.relative.unwrap_or(false) { ":relative" } else { "" }) +
  reference.separator.map(value => ":separator=" + value).unwrap_or("")
}

///|
impl @json.FromJson for BodyPageFieldRequest with fn from_json(item, path) {
  guard item is Object(fields) && fields.values().all(value => !(value is Null)) else {
    raise @json.JsonDecodeError((path, "Invalid page field"))
  }
  let field : BodyFieldKindRequest = @json.from_json(item, path~)
  let allowed = match field.field {
    "SEQ" =>
      [
        "field", "sequence", "format", "restart", "repeat", "headingLevel", "hidden",
      ]
    "REF" =>
      ["field", "bookmark", "hyperlink", "numbering", "relative", "separator"]
    "NOTEREF" => ["field", "bookmark", "hyperlink", "relative", "superscript"]
    "PAGEREF" => ["field", "bookmark", "format", "hyperlink", "relative"]
    _ => ["field", "format"]
  }
  guard fields.keys().all(key => allowed.contains(key)) else {
    raise @json.JsonDecodeError((path, "Invalid page field fields"))
  }
  let format = field.format.map(value => ":" + value).unwrap_or("")
  let code = match field.field {
    "SEQ" => {
      let sequence : SequenceFieldRequest = @json.from_json(item, path~)
      sequence_field_code(sequence, format, path)
    }
    "REF" | "NOTEREF" | "PAGEREF" => {
      let reference : ReferenceFieldRequest = @json.from_json(item, path~)
      reference_field_code(reference, field.field, format, path)
    }
    _ => field.field + format
  }
  { code, }
}

///|
fn Context::edit_page_field(
  self : Context,
  session : @model.Session,
  request : Json,
  edit : Bool,
) -> Json raise @failure.Failure {
  let command : BodyPageFieldCommandRequest = @common.request(request)
  let revision = command.revision.value
  let code = command.field.code
  let result = if edit {
    session.edit_body_page_field(
      revision,
      field_selection(request),
      code,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
  } else {
    session.insert_body_page_field(
      revision,
      code,
      probe=self.probe,
      profile=command.profile.value,
      images=self.images,
    )
  }
  self.clear_edit_layout(result, previous=revision)
}
