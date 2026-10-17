///|
fn Session::image_mode_reason(self : Session, object : Object) -> String {
  let reason = self.image_reason(object, false)
  if !reason.is_empty() {
    return reason
  }
  try {
    let fill = object.source.child("blipFill", uri=presentation_uri).unwrap()
    ignore(shape_image_source(fill, implicit_stretch=true))
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::set_image_mode(
  self : Session,
  mode : String,
) -> Json raise @failure.Failure {
  check_image_fill_mode(mode)
  let object = self.editable(false)
  let reason = self.image_mode_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if mode == "stretch" {
    let geometry = object.geometry.unwrap()
    check_image_crop_bounds(geometry.width, geometry.height, object.crop)
  }
  if (if object.tile is Some(_) { "tile" } else { "stretch" }) == mode {
    return self.query()
  }
  let fill = object.source.child("blipFill", uri=presentation_uri).unwrap()
  let (candidate, edit) = self.prepare(self.current(), [
    image_fill_mode_change(fill, mode),
  ])
  self.commit(candidate, edit, self.selection)
  self.query()
}
