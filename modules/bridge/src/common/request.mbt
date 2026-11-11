///|
/// A nonnegative i32 that rejects fractional JSON numbers before conversion.
pub struct RequestInt {
  value : Int32
}

///|
pub extend RequestInt with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for RequestInt with fn from_json(input, path) {
  guard input is Number(value, ..) &&
    value >= 0.0 &&
    value <= 2147483647.0 &&
    value == value.to_int().to_double() else {
    raise @json.JsonDecodeError((path, "Expected a nonnegative i32"))
  }
  { value: value.to_int(), }
}

///|
/// A finite JSON number; textual NaN/Infinity are never numeric input.
pub struct RequestNumber {
  value : Double
}

///|
pub extend RequestNumber with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for RequestNumber with fn from_json(input, path) {
  guard input is Number(value, ..) && !value.is_nan() && !value.is_inf() else {
    raise @json.JsonDecodeError((path, "Expected a finite JSON number"))
  }
  { value, }
}

///|
/// Require the field while accepting an explicit JSON null.
pub struct RequiredNullable[T] {
  value : T?
}

///|
pub extend RequiredNullable with @json.FromJson::{from_json}

///|
pub impl[T : @json.FromJson] @json.FromJson for RequiredNullable[T] with fn from_json(
  input,
  path,
) {
  {
    value: if input is Null {
      None
    } else {
      Some(@json.from_json(input, path~))
    },
  }
}

///|
pub struct RequestProfile {
  value : Map[String, String]
}

///|
pub extend RequestProfile with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for RequestProfile with fn from_json(input, path) {
  let value = font_profile(input) catch {
    @failure.Failure(message~, ..) =>
      raise @json.JsonDecodeError((path, message))
  }
  { value, }
}

///|
/// Keep decoding failures in the existing public error envelope.
pub fn[T : @json.FromJson] request(input : Json) -> T raise @failure.Failure {
  @json.from_json(input) catch {
    @json.JsonDecodeError((path, message)) =>
      @failure.reject(
        "invalid-operation",
        "Invalid request \{path}: \{message}",
      )
  }
}

///|
#derive(@json.FromJson)
priv struct RevisionRequest {
  revision : RequestInt
}

///|
pub fn request_revision(input : Json) -> Int32 raise @failure.Failure {
  let command : RevisionRequest = request(input)
  command.revision.value
}

///|
#derive(@json.FromJson)
pub struct OperationRequest {
  operation : String
}

///|
pub extend OperationRequest with @json.FromJson::{from_json}

///|
#derive(@json.FromJson)
pub struct ActionRequest {
  action : String
}

///|
pub extend ActionRequest with @json.FromJson::{from_json}

///|
#derive(@json.FromJson)
pub struct BytesRequest {
  bytes : String
}

///|
pub extend BytesRequest with @json.FromJson::{from_json}
