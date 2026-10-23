///|
let timeline_drawing_uri = "http://schemas.microsoft.com/office/drawing/2012/timeslicer"

///|
priv struct TimelineDrawing {
  control : SheetTimeline
  font : String
  size : Double
  accent : String
  text : String
}

///|
fn Session::read_timeline_drawing(
  self : Session,
  sheet : Sheet,
  part : String,
  tree : Tree,
  frame : @xml.Node,
  source : @xml.Node,
  dimensions : Dimensions,
) -> SheetObject raise @failure.Failure {
  let (identity, data) = tree.sheet_graphic(source)
  ignore(tree.shape_children(data, ["timeslicer"], uri=timeline_drawing_uri))
  let node = tree.picture_node(data.id, "timeslicer", uri=timeline_drawing_uri)
  guard node.attributes.length() == 1 &&
    node.attribute("name") is Some(name) &&
    tree.children.get(node.id).unwrap_or([]).is_empty() else {
    @failure.reject("unsupported-drawing", "Unknown native timeline drawing")
  }
  guard self
    .read_timelines(sheet.id)
    .filter(control => control.name.to_lower() == decode_text(name).to_lower())
    is [control] else {
    @failure.reject(
      "unsupported-drawing", "Timeline drawing has no native view",
    )
  }
  let mut style = control.style
  if self.styles_part(self.parts) is Some(part) {
    let document = self.part_xml(part)
    if style.is_empty() {
      let defaults = document
        .nodes()
        .filter(n => n.uri == timeline_uri && n.name == "timelineStyles")
      guard defaults.length() <= 1 else {
        @failure.reject("unsupported-drawing", "Ambiguous timeline style")
      }
      style = defaults
        .get(0)
        .bind(n => n.attribute("defaultTimelineStyle"))
        .unwrap_or("TimelineStyleLight1")
    }
    guard !document
      .nodes()
      .any(n => {
        n.uri == timeline_uri &&
        n.name == "timelineStyle" &&
        n.attribute("name") == Some(style)
      }) else {
      @failure.reject(
        "unsupported-drawing", "Custom timeline styles require rendering support",
      )
    }
  }
  guard (style.is_empty() || style == "TimelineStyleLight1") &&
    control.cache.state.singleRange else {
    @failure.reject(
      "unsupported-drawing", "Timeline style or noncontiguous selection requires rendering support",
    )
  }
  let client = tree.picture_child(frame.id, "clientData")
  if client is Some(node) {
    guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() &&
        ["fPrintsWithSheet", "fLocksWithSheet"].contains(a.name) &&
        ["0", "1", "false", "true"].contains(a.value)
      }) else {
      @failure.reject("unsupported-drawing", "Unknown timeline client data")
    }
  }
  let (anchor, rect) = tree.drawing_rect(frame, dimensions)
  {
    id: identity.attribute("id").unwrap(),
    name: identity.attribute("name").unwrap_or(control.name),
    description: identity.attribute("descr").unwrap_or(control.caption),
    part,
    tree,
    frame,
    source,
    rect,
    anchor,
    media: None,
    shape: None,
    chart: None,
    chart_visibility: None,
    slicer: None,
    timeline: Some({
      control,
      font: self.normal_font,
      size: self.normal_size,
      accent: self.theme[4],
      text: self.theme[1],
    }),
    crop: [0, 0, 0, 0],
    visible: !flag(identity, "hidden"),
    printable: client
    .map(node => flag(node, "fPrintsWithSheet", fallback=true))
    .unwrap_or(true),
  }
}

///|
// Validated connection metadata has no cell dimensions; native anchor writes keep their own guard.
fn Session::timeline_extension(
  self : Session,
  current : Sheet,
  tree : Tree,
  list : @xml.Node,
) -> Bool raise @failure.Failure {
  let entries = tree.children.get(list.id).unwrap_or([])
  if entries.is_empty() ||
    !entries.any(ext => {
      ext
      .attribute("uri")
      .map(uri => uri.to_upper() == timeline_view_extension)
      .unwrap_or(false)
    }) {
    return false
  }
  for ext in entries {
    if ext.uri != spreadsheet_uri || ext.name != "ext" {
      return false
    }
    match ext.attribute("uri").unwrap_or("").to_upper() {
      uri if uri == timeline_view_extension =>
        ignore(self.read_timelines(current.id))
      uri if uri == slicer_list_extension =>
        ignore(self.read_slicers(current.id))
      uri if uri == sparkline_extension_uri =>
        if !sparkline_reason(current, self.sheets).is_empty() {
          return false
        }
      _ => return false
    }
  }
  true
}
