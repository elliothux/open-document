///|
#derive(@json.FromJson)
priv struct TextInsetsRequest {
  left : @common.RequestNumber
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct TextAnchorRequest {
  anchor : String
}

///|
#derive(@json.FromJson)
priv struct TextWrapRequest {
  wrap : Bool
}

///|
#derive(@json.FromJson)
priv struct TextFitRequest {
  fit : String
}

///|
#derive(@json.FromJson)
priv struct TextUprightRequest {
  upright : Bool
}

///|
#derive(@json.FromJson)
priv struct TextDirectionRequest {
  direction : String
}

///|
#derive(@json.FromJson)
priv struct TextColumnsRequest {
  columns : @common.RequestInt
  gap : @common.RequestNumber
  rtl : Bool
}

///|
fn pptx_text_frame(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  match action {
    "textInsets" => {
      let request : TextInsetsRequest = @common.request(change)
      @model.TextInsets(
        request.left.value,
        request.top.value,
        request.right.value,
        request.bottom.value,
      )
    }
    "textAnchor" => {
      let request : TextAnchorRequest = @common.request(change)
      @model.TextAnchor(request.anchor)
    }
    "textWrap" => {
      let request : TextWrapRequest = @common.request(change)
      @model.TextWrap(request.wrap)
    }
    "textFit" => {
      let request : TextFitRequest = @common.request(change)
      @model.TextFit(request.fit)
    }
    "textUpright" => {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid upright text fields")
      }
      let request : TextUprightRequest = @common.request(change)
      @model.TextUpright(request.upright)
    }
    "textRotation" => {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid text rotation fields")
      }
      let request : RotationRequest = @common.request(change)
      @model.TextRotation(request.angle.value)
    }
    "textDirection" => {
      guard change is Object(fields) && fields.length() == 2 else {
        @failure.reject("invalid-operation", "Invalid text direction fields")
      }
      let request : TextDirectionRequest = @common.request(change)
      @model.TextDirection(request.direction)
    }
    "textColumns" => {
      guard change is Object(fields) && fields.length() == 4 else {
        @failure.reject("invalid-operation", "Invalid text column fields")
      }
      let request : TextColumnsRequest = @common.request(change)
      @model.TextColumns(request.columns.value, request.gap.value, request.rtl)
    }
    _ => @failure.reject("invalid-operation", "Unknown text frame action")
  }
}
