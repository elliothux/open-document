///|
#derive(@json.FromJson)
priv struct PositionRequest {
  paragraph : @common.RequestInt
  offset : @common.RequestInt
  affinity : String
  bidiLevel : @common.RequestInt?
  frameStart : @common.RequestInt?
}

///|
fn PositionRequest::position(self : PositionRequest) -> @model.Position {
  {
    paragraph: self.paragraph.value,
    offset: self.offset.value,
    affinity: self.affinity,
    bidiLevel: self.bidiLevel.map(value => value.value),
    frameStart: self.frameStart.map(value => value.value),
  }
}

///|
#derive(@json.FromJson)
priv struct SelectionRequest {
  anchor : PositionRequest
  focus : PositionRequest
}

///|
#derive(@json.FromJson)
priv struct RevisionSelectionRequest {
  revision : @common.RequestInt
  selection : SelectionRequest
}

///|
fn SelectionRequest::selection(self : SelectionRequest) -> @model.Selection {
  { anchor: self.anchor.position(), focus: self.focus.position(), }
}

///|
fn field_selection(json : Json) -> @model.Selection raise @failure.Failure {
  guard json is { "selection": selection, .. } else {
    @failure.reject("invalid-operation", "Explicit selection is required")
  }
  let command : SelectionRequest = @common.request(selection)
  command.selection()
}

///|
fn field_position(json : Json) -> @model.Position raise @failure.Failure {
  let command : PositionRequest = @common.request(json)
  command.position()
}
