///|
fn Session::animation_query(self : Session, slide : Slide) -> Json {
  { "items": read_animations(slide), "reason": self.slide_visibility_reason() } catch {
    @failure.Failure(message~, ..) => { "items": [], "reason": message }
  }
}

///|
fn Session::set_animations(
  self : Session,
  index : Int,
  items : Array[SlideAnimation],
) -> Json raise @failure.Failure {
  let original = self.slides[index]
  validate_animations(original, items)
  let previous = read_animations(original)
  if previous == items {
    return self.query()
  }
  let tree = original.tree
  let root = tree.root("sld")
  let markup = animation_markup(items, tree.part)
  let change : @xml.SourceChange = if tree.one(
      root.id,
      "timing",
      uri=presentation_uri,
    )
    is Some(node) {
    {
      node: root.id,
      offset: node.start - root.start,
      length: node.end - node.start,
      xml: markup,
    }
  } else if tree.one(root.id, "extLst", uri=presentation_uri) is Some(node) {
    { node: root.id, offset: node.start - root.start, length: 0, xml: markup, }
  } else {
    insertion(root, markup)
  }
  let (candidate, edit) = self.prepare(original, [change])
  self.commit(candidate, edit, self.selection)
  self.query()
}
