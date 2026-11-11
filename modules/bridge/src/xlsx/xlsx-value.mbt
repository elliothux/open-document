///|
priv struct CellValueRequest {
  value : @model.Value
}

///|
impl @json.FromJson for CellValueRequest with fn from_json(input, path) {
  guard input is Object(fields) &&
    fields.length() == 2 &&
    input is { "kind": String(kind), "value": content, .. } else {
    raise @json.JsonDecodeError((path, "Invalid cell value fields"))
  }
  let value = match (kind, content) {
    ("blank", Null) => @model.Blank
    ("text", String(value)) => @model.Text(value)
    ("error", String(value)) => @model.Error(value)
    ("number", value) => {
      let number : @common.RequestNumber = @json.from_json(value, path~)
      @model.Number(number.value)
    }
    ("boolean", True) => @model.Boolean(true)
    ("boolean", False) => @model.Boolean(false)
    _ => raise @json.JsonDecodeError((path, "Invalid cell value"))
  }
  { value, }
}
