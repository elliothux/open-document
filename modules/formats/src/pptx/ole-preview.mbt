///|
fn read_ole_preview(
  opc : @opc.Package,
  frame : Object,
  parts : Map[String, @xml.Document],
) -> Object raise @failure.Failure {
  let data = frame.source.child("graphic").bind(g => g.child("graphicData"))
  guard frame.source.node.name == "graphicFrame" &&
    data is Some(data) &&
    data.node.attribute("uri") ==
    Some("http://schemas.openxmlformats.org/presentationml/2006/ole") else {
    return frame
  }
  guard frame.shadow.map(s => s.alpha == 0).unwrap_or(true) &&
    frame.geometry is Some(_) &&
    frame.diagnostic == "Unsupported object geometry: graphicFrame/rect" else {
    @failure.reject("unsupported-style", "Unsupported OLE preview frame")
  }
  let mc = "http://schemas.openxmlformats.org/markup-compatibility/2006"
  let container = if data.child("AlternateContent", uri=mc) is Some(alternate) {
    alternate
    .child("Fallback", uri=mc)
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-style",
        message="OLE preview requires a stored fallback",
        part=frame.source.tree.part,
        offset=-1,
      ),
    )
  } else {
    data
  }
  let object = container
    .child("oleObj", uri=presentation_uri)
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-style",
        message="Missing OLE preview object",
        part=frame.source.tree.part,
        offset=-1,
      ),
    )
  guard object.child("link", uri=presentation_uri) is Some(_) ||
    object.child("embed", uri=presentation_uri) is Some(_) else {
    @failure.reject("unsupported-style", "Unsupported OLE object source")
  }
  // Linked workbooks remain inert; only the internal stored preview is read.
  let picture = object
    .child("pic", uri=presentation_uri)
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-style",
        message="Missing stored OLE picture",
        part=frame.source.tree.part,
        offset=-1,
      ),
    )
  let fill = picture
    .child("blipFill", uri=presentation_uri)
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-style",
        message="Missing OLE picture fill",
        part=frame.source.tree.part,
        offset=-1,
      ),
    )
  let shape = picture.child("spPr", uri=presentation_uri)
  guard shape is Some(shape) &&
    shape.tree.children
    .get(shape.node.id)
    .unwrap_or([])
    .all(n => n.uri == drawing_uri && ["xfrm", "prstGeom"].contains(n.name)) &&
    shape.child("xfrm") is Some(transform) &&
    transform.node.attributes.is_empty() &&
    frame.source.child("xfrm", uri=presentation_uri) is Some(outer) else {
    @failure.reject(
      "unsupported-style", "OLE preview effects or transform require support",
    )
  }
  for (node, key) in [("off", "x"), ("off", "y"), ("ext", "cx"), ("ext", "cy")] {
    guard transform.child(node).bind(n => n.node.attribute(key)) ==
      outer.child(node).bind(n => n.node.attribute(key)) else {
      @failure.reject(
        "unsupported-style", "Separate OLE picture placement requires support",
      )
    }
  }
  guard shape.child("prstGeom").bind(p => p.node.attribute("prst")) ==
    Some("rect") &&
    shape.child("custGeom") is None &&
    fill.child("srcRect") is None &&
    fill.child("tile") is None &&
    fill
    .child("stretch")
    .bind(s => s.child("fillRect"))
    .map(s => s.node.attributes.is_empty())
    .unwrap_or(false) else {
    @failure.reject(
      "unsupported-style", "OLE picture crop or geometry requires support",
    )
  }
  let blip = fill
    .child("blip")
    .unwrap_or_error(
      @failure.Failure(
        code="unsupported-style",
        message="Missing OLE picture data",
        part=frame.source.tree.part,
        offset=-1,
      ),
    )
  guard blip.tree.children.get(blip.node.id).unwrap_or([]).is_empty() &&
    blip.node.attributes.all(a => a.uri == relationship_uri && a.name == "embed") else {
    @failure.reject(
      "unsupported-style", "OLE picture effects or external source require support",
    )
  }
  let target = relationship_target(
    opc,
    frame.source.tree.part,
    blip.node.attribute("embed", uri=relationship_uri).unwrap_or(""),
    relationship_uri + "/image",
    parts,
  ).unwrap_or_error(
    @failure.Failure(
      code="unsupported-style",
      message="OLE preview requires an internal image",
      part=frame.source.tree.part,
      offset=-1,
    ),
  )
  let file = @image.read_emf(opc.read(target))
  guard file.image_keys().is_empty() else {
    @failure.reject(
      "unsupported-image", "PPTX metafile bitmaps require resource exposure",
    )
  }
  let reason = "Stored OLE previews are read-only"
  {
    ..frame,
    kind: "ole",
    metafile: Some(file),
    diagnostic: "",
    read_only: if frame.read_only.is_empty() ||
      frame.read_only == frame.diagnostic {
      reason
    } else {
      frame.read_only
    },
    text_reason: reason,
  }
}
