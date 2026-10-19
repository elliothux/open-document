///|
fn placeholder_type(kind : String) -> Bool {
  [
    "title", "body", "ctrTitle", "subTitle", "dt", "ftr", "sldNum", "hdr", "obj",
    "chart", "tbl", "clipArt", "dgm", "media", "sldImg", "pic",
  ].contains(kind)
}

///|
fn placeholder_key(
  kind : String,
  index : String,
) -> (String, Double) raise @failure.Failure {
  (
    if kind == "ctrTitle" {
      "title"
    } else {
      kind
    },
    number(index, 0, 4294967295),
  )
}

///|
fn placeholder_geometry_changes(
  object : Object,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let transform = object.source
    .child("spPr", uri=presentation_uri)
    .bind(item => item.child("xfrm"))
  if transform is Some(item) &&
    item.child("off") is Some(_) &&
    item.child("ext") is Some(_) {
    return []
  }
  guard object.geometry is Some(geometry) else {
    @failure.reject("protected-content", "Placeholder requires known geometry")
  }
  let changes = native_transform_changes(object, geometry)
  if transform is Some(transform) {
    for
      (name, value) in [
        ("rot", (geometry.rotation * 60000).round().to_int64().to_string()),
        ("flipH", if geometry.flip_x { "1" } else { "0" }),
        ("flipV", if geometry.flip_y { "1" } else { "0" }),
      ] {
      if transform.node.attribute(name) is None {
        changes.push(attribute_change(transform, name, value))
      }
    }
  }
  changes
}

///|
fn Session::placeholder_reason(self : Session, object : Object) -> String {
  try {
    let current = self.current()
    if !["sldMaster", "sldLayout"].contains(
        current.tree.document.nodes()[0].name,
      ) {
      return "Select a master or layout source"
    }
    if object.source.tree.part != current.tree.part ||
      !object.parent.is_empty() ||
      !["shape", "image"].contains(object.kind) {
      return "Select one local top-level shape or picture"
    }
    let base = self.modification_reason()
    if !base.is_empty() {
      return base
    }
    let reason = self.object_edit_reason(object, "transform")
    if !reason.is_empty() {
      return reason
    }
    let nodes = [object.source.node]
    while nodes.pop() is Some(node) {
      nodes.append(object.source.tree.children.get(node.id).unwrap_or([]))
      if node.name.has_suffix("Locks") && flag(node, "noChangeShapeType") {
        return "Placeholder definition is locked"
      }
    }
    if placeholder_node(object.source) is Some(ph) {
      let markup = ph.tree.document.source()[ph.node.start:ph.node.end]
      guard ph.node.attributes.all(a => {
          a.uri.is_empty() &&
          ["type", "idx", "sz", "orient", "hasCustomPrompt"].contains(a.name)
        }) &&
        ph.node.text.trim().is_empty() &&
        ph.tree.children.get(ph.node.id).unwrap_or([]).is_empty() &&
        !markup.contains("<!--") &&
        !markup.contains("<?") else {
        return "Unknown placeholder metadata is protected"
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::placeholder_query(self : Session, object : Object) -> Json {
  try {
    let value = placeholder(object.source)
      .map(ph => {
        guard placeholder_type(ph.0) else {
          @failure.reject("protected-content", "Unsupported placeholder type")
        }
        let result : Json = {
          "type": ph.0,
          "index": number(ph.1, 0, 4294967295),
        }
        result
      })
      .unwrap_or(Json::null())
    { "value": value, "reason": self.placeholder_reason(object) }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": message }
  }
}

///|
fn Session::placeholder_changes(
  self : Session,
  kind : String?,
  index : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects is [id] else {
    @failure.reject(
      "invalid-operation", "Placeholder definition requires one object",
    )
  }
  guard !index.is_nan() &&
    !index.is_inf() &&
    index >= 0 &&
    index <= 4294967295.0 &&
    index.round() == index &&
    kind.map(placeholder_type).unwrap_or(true) else {
    @failure.reject("invalid-operation", "Invalid placeholder definition")
  }
  let object = self.current().object(id)
  let reason = self.placeholder_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let source = object.source
  let old = placeholder_node(source)
  guard kind is Some(kind) else {
    return old
      .map(node => {
        [
          remove_slide_node(source.tree, node.node),
          ..placeholder_geometry_changes(object),
        ]
      })
      .unwrap_or([])
  }
  let value = index.to_int64().to_string()
  if placeholder(source) == Some((kind, value)) {
    return []
  }
  for node in source.tree.children.get(shape_tree(source.tree).id).unwrap_or([]) {
    if node.id == source.node.id {
      continue
    }
    if placeholder({ tree: source.tree, node, }) is Some(other) &&
      placeholder_key(other.0, other.1) == placeholder_key(kind, value) {
      @failure.reject(
        "invalid-operation", "Placeholder type and index already exist",
      )
    }
  }
  if old is Some(ph) {
    return [
      attribute_change(ph, "type", kind),
      attribute_change(ph, "idx", value),
      ..placeholder_geometry_changes(object),
    ]
  }
  let nv = source
    .child(
      if object.kind == "image" {
        "nvPicPr"
      } else {
        "nvSpPr"
      },
      uri=presentation_uri,
    )
    .bind(node => node.child("nvPr", uri=presentation_uri))
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part=source.tree.part,
        offset=-1,
        message="Missing editable placeholder properties",
      ),
    )
  [
    insertion(
      nv.node,
      "<p:ph xmlns:p=\"\{presentation_uri}\" type=\"\{kind}\" idx=\"\{value}\"/>",
    ),
  ]
}

///|
fn Session::insert_placeholder_changes(
  self : Session,
  id : String,
  kind : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  text : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = self.current().tree
  guard ["sldMaster", "sldLayout"].contains(tree.document.nodes()[0].name) else {
    @failure.reject(
      "invalid-slide", "Insert placeholders in a master or layout source",
    )
  }
  let reason = self.modification_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  guard placeholder_type(kind) &&
    @xml.valid_text(text) &&
    !text.contains("\r") &&
    text.length() <= 32767 &&
    text.split("\n").count() <= 256 &&
    text.split("\n").all(p => p.length() <= 4096) else {
    @failure.reject("invalid-operation", "Invalid placeholder type or text")
  }
  validate_object_box(x, y, width, height, false)
  let mut index = 0L
  for node in tree.children.get(shape_tree(tree).id).unwrap_or([]) {
    if placeholder({ tree, node, }) is Some(ph) {
      let existing = number(ph.1, 0, 4294967295).to_int64()
      if existing > index {
        index = existing
      }
    }
  }
  guard index < 4294967295L else {
    @failure.reject("limit-exceeded", "Placeholder indices exhausted")
  }
  index += 1
  let xml = "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"Placeholder \{kind} \{id}\"/><p:cNvSpPr/><p:nvPr><p:ph type=\"\{kind}\" idx=\"\{index}\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{(x*12700).round().to_int64()}\" y=\"\{(y*12700).round().to_int64()}\"/><a:ext cx=\"\{(width*12700).round().to_int64()}\" cy=\"\{(height*12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"rect\"/><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>\{object_text_markup(text)}</p:sp>"
  [object_insertion(tree, xml)]
}
