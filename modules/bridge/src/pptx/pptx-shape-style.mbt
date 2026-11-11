///|
#derive(@json.FromJson)
priv struct LineEndEditRequest {
  side : String
  end : Json
}

///|
#derive(@json.FromJson)
priv struct LineEndRequest {
  kind : String
  width : String
  length : String
}

///|
#derive(@json.FromJson)
priv struct StrokeCapRequest {
  cap : Json
}

///|
#derive(@json.FromJson)
priv struct StrokeJoinRequest {
  join : Json
}

///|
#derive(@json.FromJson)
priv struct MiterLimitRequest {
  miterLimit : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct StrokeDashRequest {
  dash : Json
}

///|
#derive(@json.FromJson)
priv struct ShapeAdjustmentRequest {
  name : String
  value : Json
}

///|
#derive(@json.FromJson)
priv struct ShapeTypeRequest {
  preset : String
}

///|
#derive(@json.FromJson)
priv struct PaintColorRequest {
  color : Json
}

///|
#derive(@json.FromJson)
priv struct StrokeWidthRequest {
  width : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct PaintOpacityRequest {
  opacity : @common.RequestNumber
}

///|
fn paint_string(value : Json) -> String? raise @failure.Failure {
  if value is Null {
    None
  } else {
    Some(@common.request(value))
  }
}

///|
fn pptx_shape_style(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  match action {
    "lineEnd" => {
      guard change is Object(fields) && fields.length() == 3 else {
        @failure.reject(
          "invalid-operation", "Line end side and value are required",
        )
      }
      let request : LineEndEditRequest = @common.request(change)
      guard request.side == "head" || request.side == "tail" else {
        @failure.reject("invalid-operation", "Unknown line end side")
      }
      let end : @model.LineEnd? = match request.end {
        Null => None
        Object(fields) as value if fields.length() == 3 => {
          let end : LineEndRequest = @common.request(value)
          Some({ kind: end.kind, width: end.width, length: end.length, })
        }
        _ => @failure.reject("invalid-operation", "Unknown line end fields")
      }
      @model.StrokeEnd(request.side == "head", end)
    }
    "strokeCap" => {
      let request : StrokeCapRequest = @common.request(change)
      @model.StrokeCap(paint_string(request.cap))
    }
    "strokeJoin" => {
      let request : StrokeJoinRequest = @common.request(change)
      let join = paint_string(request.join)
      let limit = if join == Some("miter") {
        let request : MiterLimitRequest = @common.request(change)
        request.miterLimit.value
      } else {
        8
      }
      @model.StrokeJoin(join, limit)
    }
    "strokeDash" => {
      let request : StrokeDashRequest = @common.request(change)
      @model.StrokeDash(paint_string(request.dash))
    }
    "shapeAdjustment" => {
      let request : ShapeAdjustmentRequest = @common.request(change)
      let value = if request.value is Null {
        None
      } else {
        let value : @common.RequestNumber = @common.request(request.value)
        Some(value.value)
      }
      @model.ShapeAdjustment(request.name, value)
    }
    "shapeType" => {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid shape type fields")
      }
      let request : ShapeTypeRequest = @common.request(change)
      @model.ShapeType(request.preset)
    }
    "fill" | "stroke" => {
      let request : PaintColorRequest = @common.request(change)
      let color = paint_string(request.color)
      if action == "fill" {
        @model.Fill(color)
      } else {
        let width : StrokeWidthRequest = @common.request(change)
        @model.Stroke(color, width.width.value)
      }
    }
    "fillOpacity" | "strokeOpacity" => {
      let request : PaintOpacityRequest = @common.request(change)
      if action == "fillOpacity" {
        @model.FillOpacity(request.opacity.value)
      } else {
        @model.StrokeOpacity(request.opacity.value)
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown shape style edit")
  }
}
