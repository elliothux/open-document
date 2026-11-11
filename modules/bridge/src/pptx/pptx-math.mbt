///|
#derive(@json.FromJson)
priv struct MathEditTargetRequest {
  target : MathTargetRequest
}

///|
#derive(@json.FromJson)
priv struct MathTargetRequest {
  object : String
  revision : @common.RequestInt
  node : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct MathContentRequest {
  latex : String
  format : MathAppearanceRequest
}

///|
#derive(@json.FromJson)
priv struct MathAppearanceRequest {
  family : String
  size : @common.RequestNumber
  color : String
}

///|
#derive(@json.FromJson)
priv struct MathPositionRequest {
  position : String
}

///|
fn pptx_math_target(value : Json) -> @model.MathTarget raise @failure.Failure {
  guard value is { "target": Object(fields), .. } && fields.length() == 3 else {
    @failure.reject("invalid-operation", "Invalid equation target")
  }
  let request : MathEditTargetRequest = @common.request(value)
  let target = request.target
  {
    object: target.object,
    revision: target.revision.value,
    node: target.node.value,
  }
}

///|
fn pptx_math_edit(
  action : String,
  value : Json,
) -> @model.ObjectEdit raise @failure.Failure {
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
  if action == "deleteMath" {
    return @model.DeleteMath(pptx_math_target(value))
  }
  guard value is { "format": Object(fields), .. } && fields.length() == 3 else {
    @failure.reject("invalid-operation", "Invalid equation appearance")
  }
  let request : MathContentRequest = @common.request(value)
  let format = request.format
  let style = @layout.TextStyle::new(
    format.family,
    format.size.value,
    format.color,
  )
  match action {
    "insertMath" => {
      let frame : ObjectFrameRequest = @common.request(value)
      @model.InsertMath(
        request.latex,
        style,
        frame.x.value,
        frame.y.value,
        frame.width.value,
        frame.height.value,
      )
    }
    "appendMath" => {
      let request_position : MathPositionRequest = @common.request(value)
      let position = request_position.position
      guard position == "start" || position == "end" else {
        @failure.reject(
          "invalid-operation", "Invalid equation insertion position",
        )
      }
      @model.AppendMath(request.latex, style, position == "start")
    }
    _ => @model.UpdateMath(pptx_math_target(value), request.latex, style)
  }
}
