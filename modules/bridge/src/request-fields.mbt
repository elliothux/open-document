///|
fn field_int(json : Json, key : String) -> Int raise @failure.Failure {
  guard json is Object(fields) &&
    fields.get(key) is Some(Number(value, ..)) &&
    value >= 0.0 &&
    value <= 2147483647.0 &&
    value == value.to_int().to_double() else {
    @failure.reject("invalid-operation", "Invalid i32 field: " + key)
  }
  value.to_int()
}

///|
fn field_string(json : Json, key : String) -> String raise @failure.Failure {
  guard json is Object(fields) && fields.get(key) is Some(String(value)) else {
    @failure.reject("invalid-operation", "Invalid string field: " + key)
  }
  value
}

///|
fn xlsx_optional_string(
  json : Json,
  key : String,
) -> String? raise @failure.Failure {
  guard json is Object(fields) else {
    @failure.reject("invalid-operation", "Expected object")
  }
  match fields.get(key) {
    Some(Null) => None
    Some(String(value)) => Some(value)
    _ => @failure.reject("invalid-operation", "Expected string or null: " + key)
  }
}

///|
fn field_selection(json : Json) -> @docx.Selection raise @failure.Failure {
  guard json is { "selection": { "anchor": anchor, "focus": focus, .. }, .. } else {
    @failure.reject("invalid-operation", "Explicit selection is required")
  }
  { anchor: field_position(anchor), focus: field_position(focus), }
}

///|
fn field_position(json : Json) -> @docx.Position raise @failure.Failure {
  {
    paragraph: field_int(json, "paragraph"),
    offset: field_int(json, "offset"),
    affinity: field_string(json, "affinity"),
    bidiLevel: if json is Object(fields) && fields.contains("bidiLevel") {
      Some(field_int(json, "bidiLevel"))
    } else {
      None
    },
    frameStart: if json is Object(fields) && fields.contains("frameStart") {
      Some(field_int(json, "frameStart"))
    } else {
      None
    },
  }
}

///|
fn input_bytes(json : Json, ceiling : Int) -> Bytes raise @failure.Failure {
  let encoded = field_string(json, "bytes")
  guard encoded.length().to_int64() <= (ceiling.to_int64() + 2) / 3 * 4 else {
    @failure.reject("limit-exceeded", "Encoded byte input exceeds budget")
  }
  let bytes = @base64.decode(encoded) catch {
    _ => @failure.reject("invalid-operation", "Invalid base64 byte input")
  }
  guard bytes.length() <= ceiling else {
    @failure.reject("limit-exceeded", "Byte input exceeds budget")
  }
  bytes
}
