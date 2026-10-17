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
