///|
// A flat fallback with matching coordinates can move with the native choice without losing its source.
fn SheetObject::slicer_transform_change(
  self : SheetObject,
  rect : @layout.Border,
) -> @xml.SourceChange raise @failure.Failure {
  let choice = self.tree.nodes[self.source.parent]
  let alternate = self.tree.nodes[choice.parent]
  let fallback = self.tree.picture_node(
    alternate.id,
    "Fallback",
    uri=drawing_compatibility_uri,
  )
  ignore(self.tree.shape_children(fallback, ["sp"], uri=picture_uri))
  let shape = self.tree.picture_node(fallback.id, "sp")
  let properties = self.tree.picture_node(shape.id, "spPr")
  let before = self.tree.picture_node(self.source.id, "xfrm")
  let after = self.tree.picture_node(
    properties.id,
    "xfrm",
    uri=picture_drawing_uri,
  )
  let data = self.tree.document.source()
  let off = self.tree.picture_node(before.id, "off", uri=picture_drawing_uri)
  let ext = self.tree.picture_node(before.id, "ext", uri=picture_drawing_uri)
  let expected = [(off, "x"), (off, "y"), (ext, "cx"), (ext, "cy")].map(pair => {
    picture_integer(pair.0.attribute(pair.1).unwrap_or(""))
  })
  for node in [before, after] {
    guard node.attributes.is_empty() &&
      !data[node.start:node.end].contains("<!--") &&
      !data[node.start:node.end].contains("<?") else {
      @failure.reject(
        "protected-content", "Slicer transform annotations or rotation require fallback editing support",
      )
    }
    ignore(self.tree.shape_children(node, ["off", "ext"]))
    let position = self.tree.picture_node(
      node.id,
      "off",
      uri=picture_drawing_uri,
    )
    let extent = self.tree.picture_node(node.id, "ext", uri=picture_drawing_uri)
    guard position.attributes.length() == 2 &&
      extent.attributes.length() == 2 &&
      self.tree.children.get(position.id).unwrap_or([]).is_empty() &&
      self.tree.children.get(extent.id).unwrap_or([]).is_empty() &&
      [(position, "x"), (position, "y"), (extent, "cx"), (extent, "cy")]
      .mapi((index, entry) => {
        picture_integer(entry.0.attribute(entry.1).unwrap_or("")) ==
        expected[index]
      })
      .all(value => value) else {
      @failure.reject(
        "protected-content", "Slicer fallback coordinates disagree with its frame",
      )
    }
  }
  guard before.end <= after.start else {
    @failure.reject(
      "protected-content", "Slicer fallback order requires support",
    )
  }
  {
    node: self.frame.id,
    offset: alternate.start - self.frame.start,
    length: alternate.end - alternate.start,
    xml: data[alternate.start:before.start].to_owned() +
    chart_transform(rect) +
    data[before.end:after.start].to_owned() +
    picture_transform(rect) +
    data[after.end:alternate.end].to_owned(),
  }
}
