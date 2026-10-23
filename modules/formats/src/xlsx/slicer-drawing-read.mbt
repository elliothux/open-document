///|
let slicer_drawing_uri = "http://schemas.microsoft.com/office/drawing/2010/slicer"

///|
let drawing_compatibility_uri = "http://schemas.openxmlformats.org/markup-compatibility/2006"

///|
priv struct SlicerDrawing {
  control : SheetSlicer
  palette : SlicerPalette
  font : String
  size : Double
}

///|
fn Tree::slicer_graphic(
  self : Tree,
  frame : @xml.Node,
) -> @xml.Node? raise @failure.Failure {
  let direct = self.picture_child(frame.id, "graphicFrame")
  guard self.picture_child(
      frame.id,
      "AlternateContent",
      uri=drawing_compatibility_uri,
    )
    is Some(alternate) else {
    return direct
  }
  guard direct is None && alternate.attributes.is_empty() else {
    @failure.reject(
      "unsupported-drawing", "Ambiguous worksheet compatibility drawing",
    )
  }
  ignore(
    self.shape_children(
      alternate,
      ["Choice", "Fallback"],
      uri=drawing_compatibility_uri,
    ),
  )
  let choice = self.picture_node(
    alternate.id,
    "Choice",
    uri=drawing_compatibility_uri,
  )
  let prefix = choice.attribute("Requires").unwrap_or("")
  guard choice.attributes.length() == 1 &&
    choice.namespaces
    .iter()
    .any(binding => {
      binding.0 == prefix &&
      binding.1 == "http://schemas.microsoft.com/office/drawing/2010/main"
    }) else {
    @failure.reject(
      "unsupported-drawing", "Unsupported worksheet compatibility choice",
    )
  }
  ignore(
    self.picture_child(alternate.id, "Fallback", uri=drawing_compatibility_uri),
  )
  ignore(self.shape_children(choice, ["graphicFrame"], uri=picture_uri))
  let source = self.picture_node(choice.id, "graphicFrame")
  let (_, data) = self.sheet_graphic(source)
  guard data.attribute("uri") == Some(slicer_drawing_uri) else {
    @failure.reject(
      "unsupported-drawing", "Unsupported worksheet compatibility graphic",
    )
  }
  Some(source)
}

///|
fn Session::read_slicer_drawing(
  self : Session,
  sheet : Sheet,
  part : String,
  tree : Tree,
  frame : @xml.Node,
  source : @xml.Node,
  dimensions : Dimensions,
) -> SheetObject raise @failure.Failure {
  let (identity, data) = tree.sheet_graphic(source)
  ignore(tree.shape_children(data, ["slicer"], uri=slicer_drawing_uri))
  let node = tree.picture_node(data.id, "slicer", uri=slicer_drawing_uri)
  guard node.attributes.length() == 1 &&
    node.attribute("name") is Some(name) &&
    tree.children.get(node.id).unwrap_or([]).is_empty() else {
    @failure.reject("unsupported-drawing", "Invalid worksheet slicer identity")
  }
  let controls = self
    .read_slicers(sheet.id)
    .filter(control => control.name == decode_text(name))
  guard controls is [control] else {
    @failure.reject(
      "unsupported-drawing", "Worksheet slicer control is unavailable",
    )
  }
  let start = self.slicer_scrolls
    .get((sheet.id, control.name))
    .unwrap_or(control.start)
  let control = {
    ..control,
    start: if start < control.cache.members.length() {
      start
    } else {
      0
    },
  }
  let client = tree.picture_child(frame.id, "clientData")
  if client is Some(node) {
    guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() &&
        ["fPrintsWithSheet", "fLocksWithSheet"].contains(a.name) &&
        ["0", "1", "true", "false"].contains(a.value)
      }) else {
      @failure.reject("unsupported-drawing", "Unknown slicer client data")
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
    slicer: Some({
      control,
      palette: self.slicer_palette(control),
      font: self.normal_font,
      size: self.normal_size,
    }),
    crop: [0, 0, 0, 0],
    printable: client
    .map(node => flag(node, "fPrintsWithSheet", fallback=true))
    .unwrap_or(true),
    visible: !flag(identity, "hidden"),
  }
}
