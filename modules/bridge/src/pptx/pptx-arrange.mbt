///|
priv struct DuplicateRequest {
  dx : @common.RequestNumber
  dy : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct RotationRequest {
  angle : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct FlipRequest {
  axis : String
} derive(@json.FromJson)

///|
priv struct LayerRequest {
  order : String
} derive(@json.FromJson)

///|
priv struct AlignObjectsRequest {
  alignment : String
  relativeTo : String
} derive(@json.FromJson)

///|
priv struct DistributeObjectsRequest {
  axis : String
  relativeTo : String
} derive(@json.FromJson)

///|
fn pptx_arrange(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  match action {
    "duplicate" => {
      let request : DuplicateRequest = @common.request(change)
      @model.Duplicate(request.dx.value, request.dy.value)
    }
    "rotate" => {
      let request : RotationRequest = @common.request(change)
      @model.Rotate(request.angle.value)
    }
    "flip" => {
      let request : FlipRequest = @common.request(change)
      match request.axis {
        "horizontal" => @model.Flip(true)
        "vertical" => @model.Flip(false)
        _ => @failure.reject("invalid-operation", "Unknown flip axis")
      }
    }
    "layer" => {
      let request : LayerRequest = @common.request(change)
      @model.Layer(request.order)
    }
    "align" => {
      let request : AlignObjectsRequest = @common.request(change)
      @model.Align(request.alignment, request.relativeTo)
    }
    "distribute" => {
      let request : DistributeObjectsRequest = @common.request(change)
      @model.Distribute(request.axis, request.relativeTo)
    }
    _ => @failure.reject("invalid-operation", "Unknown arrangement edit")
  }
}
