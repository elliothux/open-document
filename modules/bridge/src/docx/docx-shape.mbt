///|
#derive(@json.FromJson)
priv struct ShapeCommandRequest {
  revision : @common.RequestInt
  shape : Json
  profile : Json?
}

///|
#derive(@json.FromJson)
priv struct WordArtRequest {
  preset : String
  text : String
}

///|
#derive(@json.FromJson)
priv struct ShapeInsertRequest {
  preset : String
  text : String?
}

///|
#derive(@json.FromJson)
priv struct ShapeAppearanceRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
  fill : String
  stroke : String
  lineWidth : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct TextBoxRequest {
  insets : Array[@common.RequestNumber]
  anchor : String
  wrap : Bool
  clip : Bool
}

///|
#derive(@json.FromJson)
priv struct TextBoxEditRequest {
  id : @common.RequestInt
  properties : TextBoxRequest
}

///|
fn Context::edit_shape_command(
  self : Context,
  session : @model.Session,
  request : Json,
) -> Json raise @failure.Failure {
  let command : ShapeCommandRequest = @common.request(request)
  let revision = command.revision.value
  let shape = command.shape
  let edit : @common.ActionRequest = @common.request(shape)
  let result = match edit.action {
    "hyperlink" => drawing_hyperlink(session, revision, shape)
    "insertWordArt" => {
      let word_art : WordArtRequest = @common.request(shape)
      session.insert_word_art(
        revision,
        word_art.preset,
        word_art.text,
        probe=self.probe,
        profile=drawing_profile(command.profile),
        images=self.images,
      )
    }
    "insert" => {
      guard !(shape is { "text": Null, .. }) else {
        @failure.reject("invalid-operation", "Shape text cannot be null")
      }
      let insert : ShapeInsertRequest = @common.request(shape)
      let appearance : ShapeAppearanceRequest = @common.request(shape)
      session.insert_shape(
        revision,
        insert.preset,
        appearance.width.value,
        appearance.height.value,
        appearance.fill,
        appearance.stroke,
        appearance.lineWidth.value,
        text?=insert.text,
        probe=self.probe,
        profile=drawing_profile(command.profile),
        images=self.images,
      )
    }
    "delete" => {
      let drawing : DrawingIdRequest = @common.request(shape)
      session.delete_shape(revision, drawing.id.value)
    }
    "textBox" => {
      guard shape is { "properties": { "insets": Array(insets), .. }, .. } &&
        insets.length() == 4 else {
        @failure.reject("invalid-operation", "Text box requires four insets")
      }
      let drawing : TextBoxEditRequest = @common.request(shape)
      let text_box = drawing.properties
      session.edit_text_box(
        revision,
        drawing.id.value,
        {
          insets: text_box.insets.map(value => value.value),
          anchor: text_box.anchor,
          wrap: text_box.wrap,
          clip: text_box.clip,
        },
        probe=self.probe,
        profile=drawing_profile(command.profile),
        images=self.images,
      )
    }
    "position" =>
      self.position_drawing(session, revision, shape, command.profile)
    "properties" => {
      let drawing : DrawingIdRequest = @common.request(shape)
      let appearance : ShapeAppearanceRequest = @common.request(shape)
      session.edit_shape(
        revision,
        drawing.id.value,
        appearance.width.value,
        appearance.height.value,
        appearance.fill,
        appearance.stroke,
        appearance.lineWidth.value,
        probe=self.probe,
        profile=drawing_profile(command.profile),
        images=self.images,
      )
    }
    _ => @failure.reject("invalid-operation", "Unknown shape action")
  }
  self.clear_edit_layout(result, previous=revision)
}
