///|
#derive(@json.FromJson)
priv struct ImageInsetsRequest {
  insets : Array[@common.RequestNumber]
}

///|
#derive(@json.FromJson)
priv struct ImageModeRequest {
  mode : String
}

///|
#derive(@json.FromJson)
priv struct ImageOpacityRequest {
  opacity : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct ReplaceImageRequest {
  bytes : String
  object : String
}

///|
#derive(@json.FromJson)
priv struct ImageCropRequest {
  left : @common.RequestNumber
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
}

///|
fn pptx_image_insets(change : Json) -> Array[Double] raise @failure.Failure {
  guard change is { "insets": Array(values), .. } && values.length() == 4 else {
    @failure.reject(
      "invalid-operation", "Four image destination insets are required",
    )
  }
  let command : ImageInsetsRequest = @common.request(change)
  command.insets.map(value => value.value)
}

///|
fn pptx_image_edit(
  action : String,
  change : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  match action {
    "imageFill" => {
      guard change is { "objects": objects, .. } else {
        @failure.reject(
          "invalid-operation", "A bounded object selection is required",
        )
      }
      let selection : ObjectSelectionRequest = @common.request(objects)
      let objects = selection.identities()
      let source : @common.BytesRequest = @common.request(change)
      let bytes = @common.byte_input(source.bytes, @model.ImageInputBytes)
      let request : ImageModeRequest = @common.request(change)
      @model.ImageFill(objects, bytes, request.mode)
    }
    "imageFillMode" | "imageMode" => {
      let request : ImageModeRequest = @common.request(change)
      if action == "imageFillMode" {
        @model.ImageFillMode(request.mode)
      } else {
        @model.ImageMode(request.mode)
      }
    }
    "imageInsets" => @model.ImageInsets(pptx_image_insets(change))
    "imageOpacity" => {
      let request : ImageOpacityRequest = @common.request(change)
      @model.ImageOpacity(request.opacity.value)
    }
    "replaceImage" => {
      let request : ReplaceImageRequest = @common.request(change)
      @model.ReplaceImage(
        request.object,
        @common.byte_input(request.bytes, @model.ImageInputBytes),
      )
    }
    "imageCrop" => {
      let request : ImageCropRequest = @common.request(change)
      @model.ImageCrop(
        request.left.value,
        request.top.value,
        request.right.value,
        request.bottom.value,
      )
    }
    "insertImage" => {
      let source : @common.BytesRequest = @common.request(change)
      let bytes = @common.byte_input(source.bytes, @model.ImageInputBytes)
      let request : ObjectFrameRequest = @common.request(change)
      @model.InsertImage(
        bytes,
        request.x.value,
        request.y.value,
        request.width.value,
        request.height.value,
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown image edit")
  }
}
