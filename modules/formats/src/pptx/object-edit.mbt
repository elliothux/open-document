///|
pub(all) enum ObjectEdit {
  Insert(String, Double, Double, Double, Double, String)
  Remove
  Duplicate(Double, Double)
  Rotate(Double)
  Flip(Bool)
  Layer(String)
}

///|
fn Session::next_object_identity(
  self : Session,
) -> String raise @failure.Failure {
  let reserved : Map[String, Bool] = Map([])
  // Original cached trees also reserve identities of deleted imported objects.
  for
    tree in [
      ..self.cache.values().to_array(),
      ..self.slides.map(slide => slide.tree),
    ] {
    for node in tree.document.nodes() {
      if node.uri == presentation_uri && node.name == "cNvPr" {
        reserved[source_identity(node.attribute("id").unwrap_or(""))] = true
      }
    }
  }
  let mut next = self.object_sequence
  while reserved.contains(next.to_string()) {
    next += 1
  }
  guard next <= 4294967295L else {
    @failure.reject("limit-exceeded", "Object identities exhausted")
  }
  next.to_string()
}

///|
fn Session::object_edit_reason(
  self : Session,
  object : Object,
  action : String,
) -> String {
  let duplicate = action == "duplicate"
  try {
    if !object.read_only.is_empty() {
      return object.read_only
    }
    let slide = self.slides[self.index(object.source.tree.part)]
    if !slide.read_only.is_empty() {
      return slide.read_only
    }
    guard ["sp", "pic"].contains(object.source.node.name) &&
      object.source.node.parent == shape_tree(slide.tree).id else {
      return "Only local top-level shapes and pictures support this operation"
    }
    if ["rotate", "arrange"].contains(action) &&
      object.source.child("spPr", uri=presentation_uri) is None {
      return "Missing editable shape properties"
    }
    if duplicate && placeholder(object.source) is Some(_) {
      return "Duplicating inherited placeholders is not supported yet"
    }
    let target = object.source.node
    let tree = object.source.tree
    let mut identity = ""
    for node in tree.document.nodes() {
      let inside = node.start >= target.start && node.end <= target.end
      if inside {
        if node.uri == presentation_uri && node.name == "cNvPr" {
          identity = source_identity(node.attribute("id").unwrap_or(""))
        }
        if node.name.has_suffix("Locks") &&
          flag(
            node,
            match action {
              "duplicate" => "noCopy"
              "delete" => "noDelete"
              "rotate" => "noRot"
              _ => ""
            },
          ) {
          return "Object operation is locked: " + action
        }
        if duplicate &&
          (
            node.name == "extLst" ||
            ![presentation_uri, drawing_uri].contains(node.uri)
          ) {
          return "Unknown object extensions prevent duplication"
        }
      }
    }
    if action == "delete" {
      for rel in self.relationships() {
        if rel.owner == tree.part &&
          ![
            relationship_uri + "/slideLayout",
            relationship_uri + "/notesSlide",
            relationship_uri + "/image",
            relationship_uri + "/hyperlink",
          ].contains(rel.kind) {
          return "Slide relationship references require object deletion support"
        }
      }
      for node in tree.document.nodes() {
        if node.start >= target.start && node.end <= target.end {
          continue
        }
        for attribute in node.attributes {
          if ["spid", "spId", "shapeId", "shapeIdRef"].contains(attribute.name) ||
            (["stCxn", "endCxn"].contains(node.name) && attribute.name == "id") {
            if source_identity(attribute.value) == identity {
              return "Referenced objects require connector or timing updates before deletion"
            }
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn object_insertion(
  tree : Tree,
  markup : String,
) -> @xml.SourceChange raise @failure.Failure {
  let parent = shape_tree(tree)
  if tree.one(parent.id, "extLst", uri=presentation_uri) is Some(node) {
    {
      node: parent.id,
      offset: node.start - parent.start,
      length: 0,
      xml: markup,
    }
  } else {
    insertion(parent, markup)
  }
}

///|
fn validate_object_box(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  line : Bool,
) -> Unit raise @failure.Failure {
  guard [x, y, width, height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 14400
    }) &&
    (
      (width >= 0.1 && height >= 0.1) ||
      (line && width >= 0 && height >= 0 && width + height >= 0.1)
    ) else {
    @failure.reject("invalid-transform", "Invalid object position or size")
  }
}

///|
fn object_text_markup(text : String) -> String raise @failure.Failure {
  let style = "<a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:latin typeface=\"Arial\"/>"
  let out = StringBuilder()
  out.write_string(
    "<p:txBody><a:bodyPr wrap=\"square\" anchor=\"t\"><a:noAutofit/></a:bodyPr><a:lstStyle/>",
  )
  for paragraph in text.split("\n") {
    out.write_string("<a:p><a:pPr><a:buNone/></a:pPr>")
    for index, segment in paragraph.split("\u2028").to_array() {
      if index > 0 {
        out.write_string("<a:br/>")
      }
      if !segment.is_empty() {
        out.write_string(
          "<a:r><a:rPr sz=\"1800\">\{style}</a:rPr><a:t xml:space=\"preserve\">\{@xml.escape_text(segment.to_owned())}</a:t></a:r>",
        )
      }
    }
    out.write_string("<a:endParaRPr sz=\"1800\">\{style}</a:endParaRPr></a:p>")
  }
  out.write_string("</p:txBody>")
  out.to_string()
}

///|
pub fn Session::edit_objects(
  self : Session,
  revision : Int,
  change : ObjectEdit,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let original = self.current()
  guard original.read_only.is_empty() else {
    @failure.reject("protected-content", original.read_only)
  }
  let mut issued : String? = None
  let (changes, after) = match change {
    Insert(kind, x, y, width, height, text) => {
      guard ["text", "rect", "ellipse", "line"].contains(kind) &&
        @xml.valid_text(text) &&
        !text.contains("\r") &&
        text.length() <= 32767 &&
        text.split("\n").count() <= 256 &&
        text.split("\n").all(p => p.length() <= 4096) &&
        (kind != "line" || text.is_empty()) else {
        @failure.reject("invalid-operation", "Invalid object kind or text")
      }
      validate_object_box(x, y, width, height, kind == "line")
      let id = self.next_object_identity()
      issued = Some(id)
      let text_box = kind == "text"
      let preset = if text_box { "rect" } else { kind }
      let fill = if text_box || kind == "line" {
        "<a:noFill/>"
      } else {
        "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>"
      }
      let stroke = if text_box {
        "<a:noFill/>"
      } else {
        "<a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill>"
      }
      let body = if kind == "line" { "" } else { object_text_markup(text) }
      let markup = "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"\{kind} \{id}\"/><p:cNvSpPr txBox=\"\{if text_box { 1 } else { 0 }}\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(width * 12700).round().to_int64()}\" cy=\"\{(height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"\{preset}\"><a:avLst/></a:prstGeom>\{fill}<a:ln w=\"12700\">\{stroke}</a:ln></p:spPr>\{body}</p:sp>"
      (
        [object_insertion(original.tree, markup)],
        {
          ..self.selection,
          object: original.tree.part + "#" + id,
          mode: "object",
          anchor: 0,
          focus: 0,
        },
      )
    }
    Remove => {
      if self.selection.object.is_empty() {
        return self.query()
      }
      let object = self.editable(false)
      let reason = self.object_edit_reason(object, "delete")
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
      }
      let node = object.source.node
      let parent = original.tree.nodes[node.parent]
      (
        [
          {
            node: parent.id,
            offset: node.start - parent.start,
            length: node.end - node.start,
            xml: "",
          },
        ],
        { ..self.selection, object: "", mode: "object", anchor: 0, focus: 0, },
      )
    }
    Duplicate(dx, dy) => {
      guard [dx, dy].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) else {
        @failure.reject("invalid-transform", "Invalid duplication offset")
      }
      if self.selection.object.is_empty() {
        return self.query()
      }
      let object = self.editable(false)
      let reason = self.object_edit_reason(object, "duplicate")
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
      }
      let geometry = object.geometry.unwrap()
      let target = { ..geometry, x: geometry.x + dx, y: geometry.y + dy, }
      validate_object_box(
        target.x,
        target.y,
        target.width,
        target.height,
        object.preset == "line",
      )
      let id = self.next_object_identity()
      issued = Some(id)
      let changes = transform_changes(object, target)
      let identity = object.source
        .child(
          if object.kind == "image" {
            "nvPicPr"
          } else {
            "nvSpPr"
          },
          uri=presentation_uri,
        )
        .unwrap()
        .child("cNvPr", uri=presentation_uri)
        .unwrap()
      changes.push(attribute_change(identity, "id", id))
      let (copy, _) = original.tree.document.edit_source(changes)
      let copied = copy.node(object.source.node.id)
      (
        [
          object_insertion(
            original.tree,
            copy.source()[copied.start:copied.end].to_owned(),
          ),
        ],
        {
          ..self.selection,
          object: original.tree.part + "#" + id,
          anchor: 0,
          focus: 0,
        },
      )
    }
    Rotate(_) | Flip(_) | Layer(_) => {
      if self.selection.object.is_empty() {
        return self.query()
      }
      (self.arrange_object(self.editable(false), change), self.selection)
    }
  }
  if changes.is_empty() {
    return self.query()
  }
  let (candidate, edit) = self.prepare(original, changes)
  if issued is Some(_) {
    let object = candidate.object(after.object)
    let (_, _, diagnostic) = fit_text(
      object,
      object.geometry.unwrap(),
      probe,
      profile,
    )
    guard diagnostic.is_empty() else {
      @failure.reject("layout-overflow", diagnostic)
    }
  }
  self.commit(candidate, edit, after)
  if issued is Some(id) {
    self.object_sequence = number(id, 1, 4294967295).to_int64() + 1
  }
  self.query()
}
