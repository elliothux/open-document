///|
pub fn field_int(json : Json, key : String) -> Int raise @failure.Failure {
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
pub fn field_string(json : Json, key : String) -> String raise @failure.Failure {
  guard json is Object(fields) && fields.get(key) is Some(String(value)) else {
    @failure.reject("invalid-operation", "Invalid string field: " + key)
  }
  value
}

///|
pub fn optional_string(
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
pub fn input_bytes(json : Json, ceiling : Int) -> Bytes raise @failure.Failure {
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

///|
pub fn field_number(
  request : Json,
  field : String,
) -> Double raise @failure.Failure {
  guard request is Object(fields) &&
    fields.get(field) is Some(Number(value, ..)) &&
    !value.is_nan() &&
    !value.is_inf() else {
    @failure.reject("invalid-operation", "Invalid numeric field: " + field)
  }
  value
}

///|
pub fn field_boolean(
  request : Json,
  field : String,
) -> Bool raise @failure.Failure {
  guard request is Object(fields) else {
    @failure.reject("invalid-operation", "Expected request object")
  }
  match fields.get(field) {
    Some(True) => true
    Some(False) => false
    _ => @failure.reject("invalid-operation", "Invalid boolean field: " + field)
  }
}

///|
pub fn font_profile(
  request : Json,
) -> Map[String, String] raise @failure.Failure {
  guard request is { "profile": Object(fields), .. } && fields.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "Explicit bounded font profile is required",
    )
  }
  let profile : Map[String, String] = Map([])
  for key, value in fields {
    guard value is String(identity) &&
      key.length() <= 256 &&
      identity.length() <= 256 else {
      @failure.reject("invalid-operation", "Invalid font profile")
    }
    profile[key] = identity
  }
  profile
}

///|
pub fn font_input_bytes(input : String) -> Bytes raise @failure.Failure {
  guard input.length() <= 33554432 else {
    @failure.reject("limit-exceeded", "Font input exceeds budget")
  }
  Bytes::makei(input.length(), i => {
    let value = input[i].to_int()
    guard value <= 255 else {
      @failure.reject("invalid-operation", "Invalid byte input")
    }
    value.to_byte()
  })
}

///|
pub fn response(operation : () -> Json raise @failure.Failure) -> String {
  let result : Json = { "ok": true, "value": operation() } catch {
    @failure.Failure(code~, part~, offset~, message~) =>
      {
        "ok": false,
        "error": {
          "code": code,
          "part": part,
          "offset": offset,
          "message": message,
        },
      }
  }
  result.stringify()
}

///|
pub fn parse_request(input : String) -> Json raise @failure.Failure {
  guard input.length() <= 100000000 else {
    @failure.reject("limit-exceeded", "ABI input exceeds budget")
  }
  @json.parse(input) catch {
    _ => @failure.reject("invalid-operation", "Invalid request JSON")
  }
}

///|
pub fn archive_budget() -> Json {
  let budget = @archive.Budget::default()
  {
    "fileBytes": budget.file_bytes,
    "entryBytes": budget.entry_bytes,
    "totalBytes": budget.total_bytes,
    "retainedBytes": budget.retained_bytes,
    "entries": budget.entries,
    "xmlDepth": budget.xml_depth,
    "outputBytes": budget.output_bytes,
  }
}
