///|
#derive(@json.FromJson)
priv struct SheetProfileRequest {
  revision : @common.RequestInt
  sheet : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct ObjectIdRequest {
  revision : @common.RequestInt
  sheet : String
  id : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct CaptureDrawingRequest {
  revision : @common.RequestInt
  sheet : String
  objectId : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct DrawingFragmentRequest {
  revision : @common.RequestInt
  fragment : String
}

///|
#derive(@json.FromJson)
priv struct PasteDrawingRequest {
  revision : @common.RequestInt
  sheet : String
  fragment : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct SelectDrawingRequest {
  revision : @common.RequestInt
  layout : @common.RequestInt
  objectId : @common.RequiredNullable[String]
}

///|
#derive(@json.FromJson)
priv struct DrawingGestureRequest {
  revision : @common.RequestInt
  layout : @common.RequestInt
  handle : @common.RequestInt
  dx : @common.RequestNumber
  dy : @common.RequestNumber
  commit : Bool
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct DrawingViewportRequest {
  originX : @common.RequestNumber
  originY : @common.RequestNumber
  scrollX : @common.RequestNumber
  scrollY : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct SlicerGestureRequest {
  revision : @common.RequestInt
  layout : @common.RequestInt
  objectId : String
  first : @common.RequestInt
  position : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
  additive : Bool
  commit : Bool
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct TimelineGestureRequest {
  revision : @common.RequestInt
  layout : @common.RequestInt
  objectId : String
  handle : @common.RequestInt
  first : @common.RequestInt
  position : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
  commit : Bool
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct ImageKeyRequest {
  revision : @common.RequestInt
  key : String
}

///|
#derive(@json.FromJson)
priv struct ImagePixelsRequest {
  revision : @common.RequestInt
  key : String
  width : @common.RequestInt
  height : @common.RequestInt
  bytes : String
}

///|
#derive(@json.FromJson)
priv struct InsertPictureRequest {
  revision : @common.RequestInt
  sheet : String
  width : @common.RequestNumber
  height : @common.RequestNumber
  name : String
  description : String
  bytes : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct ReplacePictureRequest {
  revision : @common.RequestInt
  sheet : String
  id : String
  bytes : String
  profile : @common.RequestProfile
}

///|
priv struct PictureCrop {
  value : Array[Double]
}

///|
impl @json.FromJson for PictureCrop with fn from_json(input, path) {
  guard input is Array(values) && values.length() == 4 else {
    raise @json.JsonDecodeError((path, "Four picture crop values are required"))
  }
  let value = values.map(item => {
    guard item is Number(number, ..) else {
      raise @json.JsonDecodeError((path, "Picture crop must be numeric"))
    }
    number
  })
  { value, }
}

///|
#derive(@json.FromJson)
priv struct ObjectFrameRequest {
  anchor : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
  name : String
  description : String
}

///|
fn ObjectFrameRequest::rect(self : ObjectFrameRequest) -> @layout.Border {
  {
    x: self.x.value,
    y: self.y.value,
    width: self.width.value,
    height: self.height.value,
  }
}

///|
#derive(@json.FromJson)
priv struct PictureSettingsRequest {
  anchor : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
  name : String
  description : String
  crop : PictureCrop
}

///|
#derive(@json.FromJson)
priv struct SetPictureRequest {
  revision : @common.RequestInt
  sheet : String
  id : String
  settings : PictureSettingsRequest
  profile : @common.RequestProfile
}
