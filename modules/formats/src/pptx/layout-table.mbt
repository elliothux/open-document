///|
fn layout_table_changes(
  object : Object,
  slot : Object,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard slot.geometry is Some(geometry) &&
    geometry.width > 0 &&
    geometry.height > 0 &&
    geometry.rotation == 0 &&
    !geometry.flip_x &&
    !geometry.flip_y &&
    slot.diagnostic.is_empty() else {
    @failure.reject(
      "protected-content", "Table placeholder requires known unrotated target geometry",
    )
  }
  // Table rows retain their minimum heights and grow after wrapping at the new width.
  table_transform_changes(object, {
    ..object.geometry.unwrap(),
    x: geometry.x,
    y: geometry.y,
    width: geometry.width,
  })
}

///|
fn Slide::layout_table_fit(
  self : Slide,
  ids : Array[String],
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if ids.is_empty() {
    return []
  }
  guard probe is Some(probe) else {
    @failure.reject(
      "missing-font", "Table layout changes require a font probe and profile",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for id in ids {
    let object = self.object(id)
    guard object.table is Some(_) &&
      object.diagnostic.is_empty() &&
      object.text_reason.is_empty() else {
      @failure.reject(
        "protected-content", "Target layout introduces unsupported table content",
      )
    }
    changes.append(object.table_fit_changes(probe, profile))
  }
  changes
}
