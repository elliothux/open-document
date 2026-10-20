///|
fn ink_shape_markup(id : String, stroke : ShowInkStroke) -> String {
  let points = stroke.points.copy()
  if points is [(x, y)] {
    points.push((x + 0.01, y))
  }
  let left = points.fold(init=points[0].0, (v, p) => v.min(p.0))
  let top = points.fold(init=points[0].1, (v, p) => v.min(p.1))
  let right = points.fold(init=left, (v, p) => v.max(p.0))
  let bottom = points.fold(init=top, (v, p) => v.max(p.1))
  let x = (left * 12700).floor().to_int64()
  let y = (top * 12700).floor().to_int64()
  // A positive frame keeps horizontal strokes and dots editable with existing handles.
  let width = ((right * 12700).ceil().to_int64() - x).max(1270)
  let height = ((bottom * 12700).ceil().to_int64() - y).max(1270)
  let path = points
    .mapi((index, p) => {
      let command = if index == 0 { "moveTo" } else { "lnTo" }
      "<a:\{command}><a:pt x=\"\{(p.0 * 12700).round().to_int64() - x}\" y=\"\{(p.1 * 12700).round().to_int64() - y}\"/></a:\{command}>"
    })
    .join("")
  "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"Ink \{id}\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{x}\" y=\"\{y}\"/><a:ext cx=\"\{width}\" cy=\"\{height}\"/></a:xfrm><a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l=\"l\" t=\"t\" r=\"r\" b=\"b\"/><a:pathLst><a:path w=\"\{width}\" h=\"\{height}\" fill=\"none\">\{path}</a:path></a:pathLst></a:custGeom><a:noFill/><a:ln w=\"\{(stroke.width * 12700).round().to_int64()}\" cap=\"rnd\"><a:solidFill><a:srgbClr val=\"\{stroke.color}\"/></a:solidFill><a:round/></a:ln></p:spPr></p:sp>"
}

///|
fn Session::save_show_ink(self : Session) -> Json raise @failure.Failure {
  self.check_candidate_idle()
  guard self.showing is Some(show) else {
    @failure.reject("show-required", "Start the slideshow first")
  }
  guard show.ink_draft is None else {
    @failure.reject(
      "invalid-operation", "Finish or cancel the active ink stroke",
    )
  }
  guard self.source_view is None else {
    @failure.reject(
      "invalid-operation", "Save slideshow ink in the slide editing view",
    )
  }
  let slides = self.slides.copy()
  let reserved = self.reserved_object_identities()
  let mut next = self.object_sequence
  let edits : Array[(String, @xml.Edit)] = []
  for index, slide in self.slides {
    let strokes = show.ink.get(index).unwrap_or([])
    if strokes.is_empty() {
      continue
    }
    guard slide.read_only.is_empty() else {
      @failure.reject("protected-content", slide.read_only)
    }
    let markup = StringBuilder()
    for stroke in strokes {
      while reserved.contains(next.to_string()) {
        next += 1
      }
      guard next <= 4294967295L else {
        @failure.reject("limit-exceeded", "Object identities exhausted")
      }
      markup.write_string(ink_shape_markup(next.to_string(), stroke))
      reserved[next.to_string()] = true
      next += 1
    }
    let (candidate, edit) = self.prepare(slide, [
      object_insertion(slide.tree, markup.to_string()),
    ])
    slides[index] = candidate
    edits.push((slide.tree.part, edit))
  }
  if !edits.is_empty() {
    self.commit_slides(self.main, slides, edits, self.selection)
    self.object_sequence = next
  }
  self.showing = None
  self.invalidate_show_frame()
  self.show_drawing = None
  self.show_state(None)
}
