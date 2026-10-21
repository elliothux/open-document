///|
fn Session::order_drawing(
  self : Session,
  sheet : String,
  id : String,
  direction : String,
) -> Json raise @failure.Failure {
  guard ["front", "back", "forward", "backward"].contains(direction) &&
    id.length() <= 10 else {
    @failure.reject(
      "invalid-operation", "Invalid worksheet picture layer command",
    )
  }
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard self.font_context is Some((probe, profile)) else {
    @failure.reject(
      "missing-font", "Measure worksheet picture anchors with an explicit font profile before arranging",
    )
  }
  let dimensions = self.resolved_dimensions(current, probe, profile)
  let pictures = self.sheet_objects(current, dimensions)
  let index = for index, picture in pictures {
    if picture.id == id {
      break index
    }
  } nobreak {
    @failure.reject("invalid-operation", "Worksheet picture no longer exists")
  }
  let picture = pictures[index]
  picture.check_change(false)
  let target = match direction {
    "front" => pictures.length() - 1
    "back" => 0
    "forward" => (index + 1).min(pictures.length() - 1)
    _ => (index - 1).max(0)
  }
  if target == index {
    return self.query()
  }
  let frame = picture.frame
  let peer = pictures[target].frame
  let parent = picture.tree.nodes[frame.parent]
  let (document, edit) = picture.tree.document.edit_source([
    sheet_node_removal(picture.tree, frame),
    {
      node: parent.id,
      offset: (if target > index { peer.end } else { peer.start }) -
      parent.start,
      length: 0,
      xml: picture.tree.document.source()[frame.start:frame.end].to_owned(),
    },
  ])
  let parts = self.parts.copy()
  parts[picture.part] = document
  let candidate = { ..self, parts, }
  ignore(candidate.sheet_pictures(current, dimensions))
  self.commit(
    self.sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(picture.part, edit)],
    self.selection,
    parts~,
    drawing_selection=Some((sheet, id)),
  )
  self.query()
}
