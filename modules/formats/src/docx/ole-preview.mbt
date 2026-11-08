///|
fn Session::ole_preview(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> @layout.DrawingFrame raise @failure.Failure {
  let vml = "urn:schemas-microsoft-com:vml"
  let office = "urn:schemas-microsoft-com:office:office"
  let root = tree.nodes[id]
  guard root.uri == word_uri &&
    root.name == "object" &&
    root.text.trim().is_empty() &&
    root.attributes.all(a => {
      a.uri == word_uri && ["dxaOrig", "dyaOrig"].contains(a.name)
    }) else {
    @failure.reject(
      "unsupported-layout", "Extended embedded object requires support",
    )
  }
  let children = tree.children[id]
  guard children is [definition, shape, payload] &&
    tree.nodes[definition].uri == vml &&
    tree.nodes[definition].name == "shapetype" &&
    tree.nodes[shape].uri == vml &&
    tree.nodes[shape].name == "shape" &&
    tree.nodes[payload].uri == office &&
    tree.nodes[payload].name == "OLEObject" else {
    @failure.reject(
      "unsupported-layout", "Embedded object requires one stored preview",
    )
  }
  let source = tree.nodes[definition]
  let formulae = tree
    .descendants(definition)
    .filter(item => tree.nodes[item].uri == vml && tree.nodes[item].name == "f")
  guard source.attribute("spt", uri=office) == Some("75") &&
    source.attribute("coordsize") == Some("21600,21600") &&
    source.attribute("path") == Some("m@4@5l@4@11@9@11@9@5xe") &&
    source.attribute("filled") == Some("f") &&
    source.attribute("stroked") == Some("f") &&
    formulae.map(item => tree.nodes[item].attribute("eqn").unwrap_or("")) ==
    [
      "if lineDrawn pixelLineWidth 0", "sum @0 1 0", "sum 0 0 @1", "prod @2 1 2",
      "prod @3 21600 pixelWidth", "prod @3 21600 pixelHeight", "sum @0 0 1", "prod @6 1 2",
      "prod @7 21600 pixelWidth", "sum @8 21600 0", "prod @7 21600 pixelHeight",
      "sum @10 21600 0",
    ] else {
    @failure.reject(
      "unsupported-layout", "Embedded preview geometry requires support",
    )
  }
  let object = tree.nodes[payload]
  let picture = tree.nodes[shape]
  guard object.attribute("Type") == Some("Embed") &&
    [Some("Icon"), Some("Content")].contains(object.attribute("DrawAspect")) &&
    object.attribute("ShapeID") == picture.attribute("id") &&
    picture.attribute("type") ==
    source.attribute("id").map(value => "#" + value) &&
    picture.attributes.all(a => {
      (a.uri.is_empty() && ["id", "type", "style"].contains(a.name)) ||
      (a.uri == office && a.name == "ole")
    }) &&
    tree.children[shape] is [image] &&
    tree.nodes[image].uri == vml &&
    tree.nodes[image].name == "imagedata" &&
    tree.children[image].is_empty() else {
    @failure.reject(
      "unsupported-layout", "Embedded object has no ordinary inline preview",
    )
  }
  let styles : Map[String, Double] = Map([])
  for declaration in picture.attribute("style").unwrap_or("").split(";") {
    if declaration.trim().is_empty() {
      continue
    }
    let pieces = declaration.split(":").to_array()
    guard pieces is [name, value] &&
      ["width", "height"].contains(name.trim().to_owned()) &&
      !styles.contains(name.trim().to_owned()) &&
      value.trim().has_suffix("pt") else {
      @failure.reject(
        "unsupported-layout", "Embedded preview placement requires support",
      )
    }
    let raw = value.trim()
    let length = @string.parse_double(raw[:raw.length() - 2]) catch {
      _ =>
        @failure.reject("invalid-image", "Invalid embedded preview dimensions")
    }
    guard length > 0 && length <= 14400 && !length.is_nan() else {
      @failure.reject("invalid-image", "Invalid embedded preview dimensions")
    }
    styles[name.trim().to_owned()] = length
  }
  guard styles.get("width") is Some(width) &&
    styles.get("height") is Some(height) else {
    @failure.reject("invalid-image", "Missing embedded preview dimensions")
  }
  let preview_id = tree.nodes[image]
    .attribute("id", uri=running_rel_uri)
    .unwrap_or("")
  let payload_id = object.attribute("id", uri=running_rel_uri).unwrap_or("")
  let relations = self.relationships()
  guard relations.filter(rel => rel.owner == self.main && rel.id == payload_id)
    is [stored] &&
    !stored.external &&
    stored.kind == running_rel_uri + "/oleObject" &&
    self.opc.names.contains(stored.target.to_lower()) else {
    @failure.reject(
      "protected-content", "Embedded object requires an internal stored payload",
    )
  }
  let preview = self.image_reference(self.main, preview_id)
  guard !preview.external else {
    @failure.reject(
      "protected-content", "External object previews require supplied resources",
    )
  }
  let file = @image.read_emf(self.image_bytes(preview_id))
  guard !file
    .image_keys()
    .any(key => relations.any(rel => rel.owner == self.main && rel.id == key)) else {
    @failure.reject(
      "protected-content", "Decoded preview identity conflicts with a document relationship",
    )
  }
  let result : @layout.DrawingFrame = {
    width,
    height,
    effectExtent: (0, 0, 0, 0),
    anchor: None,
    content: @layout.Metafile(file),
  }
  result.validate()
  result
}

///|
fn Session::ole_preview_image(
  self : Session,
  key : String,
) -> Bytes raise @failure.Failure {
  let tree = WordTree::new(self.document())
  for id in tree.order {
    if tree.nodes[id].uri == word_uri && tree.nodes[id].name == "object" {
      let frame = self.ole_preview(tree, id)
      if frame.content is @layout.Metafile(file) {
        for command in file.commands {
          if command is @layout.Bitmap(identity, _, width, height, rgba) &&
            identity == key {
            return @image.encode_png(width, height, rgba)
          }
        }
      }
    }
  }
  @failure.reject("missing-image", "Unknown decoded metafile image")
}
