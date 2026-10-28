///|
pub fn Session::insert_picture(
  self : Session,
  revision : Int32,
  width : Double,
  height : Double,
  bytes : Bytes,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard [width, height].all(value => {
    !value.is_nan() && !value.is_inf() && value >= 0.1 && value <= 14400
  }) else {
    @failure.reject("invalid-operation", "Invalid picture dimensions")
  }
  let kind = @image.type_info(bytes)
  let identity = self.next_drawing_identity()
  let resource = self.prepare_picture_resource(
    identity,
    bytes,
    (kind.0, kind.1),
  )
  let prepared = self.prepare_drawing_insertion(
    picture_markup(identity, resource.link, width, height),
  )
  self.commit_picture_resource(
    resource,
    prepared.document,
    prepared.edit.xml,
    prepared.edit.paragraphs,
    prepared.edit.after,
  )
}
