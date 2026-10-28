///|
fn pptx_math_edit(value : Json) -> @model.ObjectEdit raise @failure.Failure {
  let action = field_string(value, "action")
  let keys = match action {
    "insertMath" => ["action", "latex", "format", "x", "y", "width", "height"]
    "appendMath" => ["action", "latex", "format", "position"]
    "updateMath" => ["action", "target", "latex", "format"]
    "deleteMath" => ["action", "target"]
    _ => @failure.reject("invalid-operation", "Unknown equation action")
  }
  guard value is Object(fields) &&
    fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Invalid equation fields")
  }
  let target = fn() raise @failure.Failure {
    guard fields.get("target") is Some(Object(target)) &&
      target.length() == 3 &&
      target.keys().all(key => ["object", "revision", "node"].contains(key)) else {
      @failure.reject("invalid-operation", "Invalid equation target")
    }
    let value = Json::object(target)
    let result : @model.MathTarget = {
      object: field_string(value, "object"),
      revision: field_int(value, "revision"),
      node: field_int(value, "node"),
    }
    result
  }
  if action == "deleteMath" {
    return @model.DeleteMath(target())
  }
  guard fields.get("format") is Some(Object(format)) &&
    format.length() == 3 &&
    format.keys().all(key => ["family", "size", "color"].contains(key)) else {
    @failure.reject("invalid-operation", "Invalid equation appearance")
  }
  let format = Json::object(format)
  let style = @layout.TextStyle::new(
    field_string(format, "family"),
    field_number(format, "size"),
    field_string(format, "color"),
  )
  let latex = field_string(value, "latex")
  match action {
    "insertMath" =>
      @model.InsertMath(
        latex,
        style,
        field_number(value, "x"),
        field_number(value, "y"),
        field_number(value, "width"),
        field_number(value, "height"),
      )
    "appendMath" => {
      let position = field_string(value, "position")
      guard ["start", "end"].contains(position) else {
        @failure.reject(
          "invalid-operation", "Invalid equation insertion position",
        )
      }
      @model.AppendMath(latex, style, position == "start")
    }
    _ => @model.UpdateMath(target(), latex, style)
  }
}
