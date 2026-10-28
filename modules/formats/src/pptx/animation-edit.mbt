///|
fn Session::animation_query(self : Session, slide : Slide) -> Json {
  {
    "items": self.read_animations(slide),
    "reason": self.slide_visibility_reason(),
  } catch {
    @failure.Failure(message~, ..) => { "items": [], "reason": message }
  }
}

///|
fn Session::set_animations(
  self : Session,
  index : Int32,
  items : Array[SlideAnimation],
) -> Json raise @failure.Failure {
  let original = self.slides[index]
  validate_animations(original, items)
  let previous = self.read_animations(original)
  if previous == items {
    return self.query()
  }
  let media = read_media_nodes(original.tree)
  for item in items {
    if item.kind.has_prefix("media") && !media.contains(item.object) {
      media[item.object] = (
        original.object(item.object).media.unwrap().kind,
        MediaPlaybackSettings::initial(),
      )
    }
  }
  let change = self.animation_change(original, items, media)
  let (candidate, edit) = self.prepare(original, [change])
  self.commit(candidate, edit, self.selection)
  self.query()
}

///|
fn Session::animation_change(
  self : Session,
  original : Slide,
  items : Array[SlideAnimation],
  media : Map[String, (String, MediaPlaybackSettings)],
) -> @xml.SourceChange raise @failure.Failure {
  let tree = original.tree
  let root = tree.root("sld")
  let markup = animation_markup(
    items,
    tree.part,
    self.width,
    self.height,
    media~,
  )
  if tree.one(root.id, "timing", uri=presentation_uri) is Some(node) {
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
}
