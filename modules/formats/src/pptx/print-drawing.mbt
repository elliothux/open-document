///|
/// Returns the same committed pages as PDF without changing the editing layout.
pub fn Session::print_drawing(
  self : Session,
  revision : Int32,
  all : Bool,
  hidden : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
) -> Json raise @failure.Failure {
  let document = self.print_layout(revision, all, hidden, probe, profile)
  drawing_batch(
    document,
    self.revision,
    self.image_keys(all, hidden),
    probe,
    images,
  )
}

///|
/// Lists the resources used by one committed slide, master, or layout.
pub fn Session::preview_keys(
  self : Session,
  revision : Int32,
  part : String,
) -> Array[String] raise @failure.Failure {
  self.check_revision(revision)
  self.source_slide(part).image_keys()
}

///|
/// Paints a committed slide, master, or layout without updating editing geometry.
pub fn Session::preview_drawing(
  self : Session,
  revision : Int32,
  part : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let slide = self.source_slide(part)
  let (page, _, _) = paint_slide(
    slide,
    self.width,
    self.height,
    probe,
    profile,
    self.tile_sizes(slide),
  )
  guard page.primitives.length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Slide preview primitives exceed budget")
  }
  let document : @layout.PositionedDocument = {
    pages: [page],
    fonts: probe.font_info(),
    links: [],
  }
  drawing_batch(document, revision, slide.image_keys(), probe, images)
}

///|
fn drawing_batch(
  document : @layout.PositionedDocument,
  revision : Int32,
  keys : Array[String],
  probe : @layout.TextProbe,
  images : @layout.Images,
) -> Json raise @failure.Failure {
  let resources : Array[String] = []
  for key in keys {
    let identity = images.get(key).identity
    if !resources.contains(identity) {
      resources.push(identity)
    }
  }
  {
    "revision": revision,
    "regions": document.drawing(images, glyph_raster=FractionalGlyphs),
    "outlines": probe.outline_resources(),
    "images": resources,
  }
}
