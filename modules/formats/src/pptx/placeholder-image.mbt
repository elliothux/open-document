///|
fn Session::image_replacement_reason(self : Session, object : Object) -> String {
  if object.kind == "image" {
    return self.image_reason(object, false)
  }
  try {
    let reason = self.appearance_reason(object)
    if !reason.is_empty() {
      return reason
    }
    guard object.kind == "shape" &&
      object.parent.is_empty() &&
      placeholder(object.source) is Some(("pic" | "obj", _)) else {
      return "Select a local picture or an empty picture/content placeholder"
    }
    guard object.text().is_empty() && object.text_reason.is_empty() else {
      return "Placeholder text must be empty before inserting a picture"
    }
    let source = object.source
    let xml = source_xml(source)
    guard source.node.attributes.is_empty() &&
      !xml.contains("<!--") &&
      !xml.contains("<?") &&
      source.tree.children
      .get(source.node.id)
      .unwrap_or([])
      .all(node => {
        node.uri == presentation_uri &&
        ["nvSpPr", "spPr", "style", "txBody"].contains(node.name)
      }) else {
      return "Unknown placeholder markup is protected"
    }
    guard source.child("nvSpPr", uri=presentation_uri) is Some(nv) &&
      nv.child("cNvSpPr", uri=presentation_uri) is Some(shape) &&
      nv.child("cNvPr", uri=presentation_uri) is Some(_) &&
      nv.child("nvPr", uri=presentation_uri) is Some(_) &&
      source.child("spPr", uri=presentation_uri) is Some(_) else {
      return "Missing editable placeholder properties"
    }
    guard nv.node.attributes.is_empty() &&
      shape.node.attributes.is_empty() &&
      shape.tree.children.get(shape.node.id).unwrap_or([]).is_empty() &&
      nv.tree.children
      .get(nv.node.id)
      .unwrap_or([])
      .all(node => {
        node.uri == presentation_uri &&
        ["cNvPr", "cNvSpPr", "nvPr"].contains(node.name)
      }) else {
      return "Locked or extended placeholder properties are protected"
    }
    let transform = self.object_edit_reason(object, "transform")
    if !transform.is_empty() {
      return transform
    }
    guard object.geometry is Some(g) && g.width > 0 && g.height > 0 else {
      return "Placeholder requires known positive geometry"
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::selected_image_replacement(
  self : Session,
) -> Object raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Picture replacement requires one object",
    )
  }
  let object = self.current().object(self.selection.object)
  let reason = self.image_replacement_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  object
}

///|
fn placeholder_image_change(
  object : Object,
  link : String,
  pixel_width : Int,
  pixel_height : Int,
) -> @xml.SourceChange raise @failure.Failure {
  let geometry = object.geometry.unwrap()
  let mut width = (pixel_width.to_double() * 0.75).max(72 / 25.4)
  let mut height = (pixel_height.to_double() * 0.75).max(72 / 25.4)
  // ONLYOFFICE addImages centers a contained picture and avoids enlarging small inputs.
  if width >= geometry.width || height >= geometry.height {
    let scale = (geometry.width / width).min(geometry.height / height)
    width = (width * scale).max(5 * 72 / 25.4)
    height = (height * scale).max(5 * 72 / 25.4)
  }
  let fitted = {
    ..geometry,
    x: geometry.x + (geometry.width - width) / 2,
    y: geometry.y + (geometry.height - height) / 2,
    width,
    height,
  }
  let source = object.source
  let (document, _) = source.tree.document.edit_source(
    native_transform_changes(object, fitted),
  )
  let markup = fn(item : Ref) raise @failure.Failure {
    source.tree.standalone_markup(document, item.node.id)
  }
  let nv = source.child("nvSpPr", uri=presentation_uri).unwrap()
  let common = markup(nv.child("cNvPr", uri=presentation_uri).unwrap())
  let application = markup(nv.child("nvPr", uri=presentation_uri).unwrap())
  let properties = markup(source.child("spPr", uri=presentation_uri).unwrap())
  let style = source
    .child("style", uri=presentation_uri)
    .map(markup)
    .unwrap_or("")
  let parent = source.tree.nodes[source.node.parent]
  {
    node: parent.id,
    offset: source.node.start - parent.start,
    length: source.node.end - source.node.start,
    xml: "<p:pic xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><p:nvPicPr>\{common}<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr>\{application}</p:nvPicPr><p:blipFill><a:blip r:embed=\"\{link}\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>\{properties}\{style}</p:pic>",
  }
}
