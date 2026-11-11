///|
#derive(@json.FromJson)
priv struct PlacementRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
  rotation : @common.RequestNumber
}

///|
fn PlacementRequest::placement(self : PlacementRequest) -> @model.PdfPlacement {
  {
    x: self.x.value,
    y: self.y.value,
    width: self.width.value,
    height: self.height.value,
    rotation: self.rotation.value,
  }
}

///|
#derive(@json.FromJson)
priv struct CropWindowRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
}

///|
fn CropWindowRequest::crop(self : CropWindowRequest) -> @model.PdfImageCrop {
  {
    x: self.x.value,
    y: self.y.value,
    width: self.width.value,
    height: self.height.value,
  }
}
