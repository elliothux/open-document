///|
let drawing2010_uri = "http://schemas.microsoft.com/office/drawing/2010/main"

///|
fn Tree::drawing_extension(
  self : Tree,
  extension : @xml.Node,
  uri : String,
  name : String,
) -> @xml.Node? {
  if extension.uri == picture_drawing_uri &&
    extension.name == "ext" &&
    extension.attributes.length() == 1 &&
    extension.attribute("uri").map(value => value.to_upper()) == Some(uri) &&
    extension.text.trim().is_empty() &&
    self.children.get(extension.id).unwrap_or([]) is [payload] &&
    payload.uri == drawing2010_uri &&
    payload.name == name {
    Some(payload)
  } else {
    None
  }
}

///|
fn Tree::picture_compression_metadata(self : Tree, blip : @xml.Node) -> Bool {
  match self.children.get(blip.id).unwrap_or([]) {
    [] => true
    [list] =>
      list.uri == picture_drawing_uri &&
      list.name == "extLst" &&
      list.attributes.is_empty() &&
      list.text.trim().is_empty() &&
      self.children.get(list.id).unwrap_or([]) is [extension] &&
      self.drawing_extension(
        extension, "{28A0092B-C50C-407E-A947-70E740481C1C}", "useLocalDpi",
      )
      is Some(dpi) &&
      dpi.attributes.length() == 1 &&
      [Some("0"), Some("false")].contains(dpi.attribute("val")) &&
      dpi.text.trim().is_empty() &&
      self.children.get(dpi.id).unwrap_or([]).is_empty()
    _ => false
  }
}

///|
fn Tree::check_hidden_drawing_paint(
  self : Tree,
  properties : @xml.Node,
) -> Unit raise @failure.Failure {
  guard self.picture_child(properties.id, "extLst", uri=picture_drawing_uri)
    is Some(list) else {
    return
  }
  let extensions = self.children.get(list.id).unwrap_or([])
  let rel_uri = relationship_uri[:relationship_uri.length() - 1].to_owned()
  guard list.attributes.is_empty() &&
    list.text.trim().is_empty() &&
    extensions.length() <= 2 &&
    (
      extensions.length() != 2 ||
      extensions[0].attribute("uri").map(value => value.to_upper()) !=
      extensions[1].attribute("uri").map(value => value.to_upper())
    ) &&
    extensions.all(extension => {
      self.drawing_extension(
        extension, "{909E8E84-426E-40DD-AFC4-6F175D3DCCD1}", "hiddenFill",
      )
      is Some(_) ||
      self.drawing_extension(
        extension, "{91240B29-F687-4F45-9708-019B960494DF}", "hiddenLine",
      )
      is Some(_)
    }) &&
    self.document
    .nodes()
    .all(node => {
      node.start < list.start ||
      node.end > list.end ||
      node.attributes.all(attribute => attribute.uri != rel_uri)
    }) else {
    @failure.reject("unsupported-drawing", "Unknown worksheet paint extensions")
  }
}
