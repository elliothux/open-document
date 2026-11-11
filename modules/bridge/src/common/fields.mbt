///|
pub fn field_int(json : Json, key : String) -> Int32 raise @failure.Failure {
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
pub fn font_profile(input : Json) -> Map[String, String] raise @failure.Failure {
  guard input is Object(fields) && fields.length() <= 256 else {
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
  guard input.length() <= @layout.FontInputBytes else {
    @failure.reject("limit-exceeded", "Font input exceeds budget")
  }
  byte_input(input, @layout.FontInputBytes)
}

///|
pub fn byte_input(
  input : String,
  ceiling : Int32,
) -> Bytes raise @failure.Failure {
  guard input.length() <= ceiling else {
    @failure.reject("limit-exceeded", "Byte input exceeds budget")
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
#derive(ToJson)
priv struct SuccessResponse {
  ok : Bool
  value : Json
}

///|
#derive(ToJson)
priv struct ResponseError {
  code : String
  part : String
  offset : Int32
  message : String
}

///|
#derive(ToJson)
priv struct FailureResponse {
  ok : Bool
  error : ResponseError
}

///|
pub fn response(operation : () -> Json raise @failure.Failure) -> String {
  let result = try {
    let result : SuccessResponse = { ok: true, value: operation(), }
    ToJson::to_json(result)
  } catch {
    @failure.Failure(code~, part~, offset~, message~) => {
      let result : FailureResponse = {
        ok: false,
        error: { code, part, offset, message, },
      }
      ToJson::to_json(result)
    }
  }
  result.stringify()
}

///|
/// Wrap core-encoded JSON without parsing or serializing its payload again.
pub fn encoded_response(
  operation : () -> String raise @failure.Failure,
) -> String {
  try "{\"ok\":true,\"value\":" + operation() + "}" catch {
    @failure.Failure(..) as error => response(() => raise error)
  }
}

///|
pub fn parse_request(
  input : String,
  first~ : String = "",
  second~ : String = "",
) -> Json raise @failure.Failure {
  guard input.length() <= 100000000 &&
    first.length().to_int64() + second.length().to_int64() <= 75000000L else {
    @failure.reject("limit-exceeded", "ABI input exceeds budget")
  }
  let request = @json.parse(input) catch {
    _ => @failure.reject("invalid-operation", "Invalid request JSON")
  }
  if first.is_empty() && second.is_empty() {
    request
  } else {
    attach_request_bytes(request, first, second)
  }
}

///|
fn attach_request_bytes(
  value : Json,
  first : String,
  second : String,
) -> Json raise @failure.Failure {
  match value {
    Object(fields) if fields.length() == 1 && fields.contains("$bytes") =>
      match fields["$bytes"] {
        Number(0, ..) if !first.is_empty() => Json::string(first)
        Number(1, ..) if !second.is_empty() => Json::string(second)
        _ => @failure.reject("invalid-operation", "Invalid byte attachment")
      }
    Object(fields) => {
      for key, item in fields {
        fields[key] = attach_request_bytes(item, first, second)
      }
      value
    }
    Array(items) => {
      for index, item in items {
        items[index] = attach_request_bytes(item, first, second)
      }
      value
    }
    _ => value
  }
}

///|
#derive(ToJson)
priv struct ArchiveBudgetResponse {
  fileBytes : Int32
  entryBytes : Int32
  totalBytes : Int32
  retainedBytes : Int32
  entries : Int32
  xmlDepth : Int32
  outputBytes : Int32
}

///|
pub fn archive_budget() -> Json {
  let budget = @archive.Budget::default()
  let result : ArchiveBudgetResponse = {
    fileBytes: budget.file_bytes,
    entryBytes: budget.entry_bytes,
    totalBytes: budget.total_bytes,
    retainedBytes: budget.retained_bytes,
    entries: budget.entries,
    xmlDepth: budget.xml_depth,
    outputBytes: budget.output_bytes,
  }
  ToJson::to_json(result)
}
