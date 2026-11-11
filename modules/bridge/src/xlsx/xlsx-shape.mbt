///|
#derive(@json.FromJson)
priv struct ShapeInsetsRequest {
  left : @common.RequestNumber
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct ShapeSettingsRequest {
  kind : String
  anchor : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
  name : String
  description : String
  fill : @common.RequiredNullable[String]
  stroke : @common.RequiredNullable[String]
  lineWidth : @common.RequestNumber
  text : String
  font : String
  bold : Bool
  italic : Bool
  size : @common.RequestNumber
  color : String
  wrap : Bool
  align : String
  vertical : String
  insets : ShapeInsetsRequest
}

///|
fn ShapeSettingsRequest::settings(
  self : ShapeSettingsRequest,
) -> @model.ShapeSettings {
  {
    kind: self.kind,
    anchor: self.anchor,
    rect: {
      x: self.x.value,
      y: self.y.value,
      width: self.width.value,
      height: self.height.value,
    },
    name: self.name,
    description: self.description,
    fill: self.fill.value,
    stroke: self.stroke.value,
    line_width: self.lineWidth.value,
    text: self.text,
    font: self.font,
    bold: self.bold,
    italic: self.italic,
    size: self.size.value,
    color: self.color,
    wrap: self.wrap,
    align: self.align,
    vertical: self.vertical,
    insets: [
      self.insets.left.value,
      self.insets.top.value,
      self.insets.right.value,
      self.insets.bottom.value,
    ],
  }
}

///|
#derive(@json.FromJson)
priv struct InsertShapeRequest {
  revision : @common.RequestInt
  sheet : String
  kind : String
  width : @common.RequestNumber
  height : @common.RequestNumber
  text : String
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct SetShapeRequest {
  revision : @common.RequestInt
  sheet : String
  id : String
  settings : ShapeSettingsRequest
  profile : @common.RequestProfile
}

///|
let shape_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "shapesXlsx": (context, session, input) => {
    let command : SheetProfileRequest = @common.request(input)
    session.shapes(
      command.revision.value,
      command.sheet,
      context.probe,
      command.profile.value,
    )
  },
  "insertShapeXlsx": (context, session, input) => {
    let command : InsertShapeRequest = @common.request(input)
    session.insert_shape(
      command.revision.value,
      command.sheet,
      command.kind,
      command.width.value,
      command.height.value,
      command.text,
      context.probe,
      command.profile.value,
    )
  },
  "setShapeXlsx": (context, session, input) => {
    let command : SetShapeRequest = @common.request(input)
    session.set_shape(
      command.revision.value,
      command.sheet,
      command.id,
      command.settings.settings(),
      context.probe,
      command.profile.value,
    )
  },
  "deleteShapeXlsx": (context, session, input) => {
    let command : ObjectIdRequest = @common.request(input)
    session.delete_shape(
      command.revision.value,
      command.sheet,
      command.id,
      context.probe,
      command.profile.value,
    )
  },
}
