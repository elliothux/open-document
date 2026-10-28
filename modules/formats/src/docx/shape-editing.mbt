///|
fn Session::editable_shape(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> (Int32, @layout.DrawingFrame, Int32) raise @failure.Failure {
  let paragraph = self.drawing_paragraph(tree, id)
  let (_, data) = tree.drawing_data(id)
  guard data.attribute("uri") == Some(word_shape_uri) else {
    @failure.reject("invalid-operation", "Drawing is not a basic shape")
  }
  let drawing = self.drawing_frame(tree, id) catch {
    @failure.Failure(code="unsupported-layout", message~, ..) =>
      @failure.reject("protected-content", message)
    error => raise error
  }
  for child in tree.descendants(id) {
    let node = tree.nodes[child]
    if node.name == "docPr" || node.name == "graphic" {
      if node.name == "docPr" {
        ignore(tree.drawing_link_node(id))
      } else {
        guard node.attributes.is_empty() else {
          @failure.reject(
            "protected-content", "Shape graphic attributes require support",
          )
        }
      }
    }
    if node.name == "cNvGraphicFramePr" {
      tree.shape_children(child, ["graphicFrameLocks"])
      guard node.attributes.is_empty() else {
        @failure.reject("protected-content", "Unknown shape frame metadata")
      }
    }
    if node.name.has_suffix("Locks") {
      guard node.uri == picture_drawing_uri &&
        ["spLocks", "graphicFrameLocks"].contains(node.name) &&
        tree.children[child].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.all(a => {
          a.uri.is_empty() &&
          [
            "noGrp", "noSelect", "noRot", "noChangeAspect", "noMove", "noResize",
            "noEditPoints", "noAdjustHandles", "noChangeArrowheads", "noChangeShapeType",
            "noTextEdit", "noDelete", "noChangeWrap", "noDrilldown", "noCopy",
          ].contains(a.name) &&
          ["0", "1", "false", "true"].contains(a.value)
        }) else {
        @failure.reject("protected-content", "Unknown shape lock metadata")
      }
    }
  }
  let shape = tree.children[data.id][0]
  let properties = tree
    .drawing_child(shape, "spPr", uri=word_shape_uri)
    .unwrap()
  (paragraph, drawing, properties)
}

///|
fn WordTree::shape_locked(self : WordTree, id : Int32, name : String) -> Bool {
  self
  .descendants(id)
  .any(child => {
    let node = self.nodes[child]
    node.name.has_suffix("Locks") &&
    ["1", "true"].contains(node.attribute(name).unwrap_or("0"))
  })
}

///|
pub fn Session::shapes(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let items : Array[Json] = []
  let links = self.hyperlink_relationships()
  let bookmarks = tree.bookmark_targets()
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri ||
      node.name != "drawing" ||
      tree.drawing_data(id).1.attribute("uri") != Some(word_shape_uri) {
      continue
    }
    guard items.length() < 256 else {
      @failure.reject("limit-exceeded", "Shape list exceeds 256 entries")
    }
    let frame = self.drawing_frame(tree, id)
    guard frame.content is (@layout.Shape(shape) | @layout.TextBox(shape, _)) else {
      abort("Shape payload expected")
    }
    let reason = try {
      ignore(self.editable_shape(tree, id))
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    let delete_reason = try {
      guard reason.is_empty() && !tree.shape_locked(id, "noDelete") else {
        @failure.reject(
          "protected-content",
          if reason.is_empty() {
            "Shape deletion is locked"
          } else {
            reason
          },
        )
      }
      tree.check_picture_references(id)
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    let wp = tree.drawing_data(id).0
    items.push({
      "id": id,
      "selected": self.selected_drawing(tree) == Some(id) &&
      !tree.shape_locked(id, "noSelect"),
      "name": tree.nodes[tree.anchor_child(wp.id, "docPr")]
      .attribute("name")
      .unwrap_or("Shape"),
      "preset": shape.preset,
      "width": frame.width,
      "height": frame.height,
      "fill": shape.fill,
      "stroke": shape.stroke,
      "lineWidth": shape.lineWidth,
      "textBox": match frame.content {
        @layout.TextBox(_, text) => Json(text.properties())
        _ => Json::null()
      },
      "textReason": if tree.shape_locked(id, "noTextEdit") ||
        tree.shape_locked(id, "noSelect") {
        "Text box text editing is locked"
      } else {
        reason
      },
      "anchor": frame.anchor
      .map(value => value.to_json())
      .unwrap_or(Json::null()),
      "positionReason": try {
        ignore(self.editable_drawing_position(tree, id))
        ""
      } catch {
        @failure.Failure(message~, ..) => message
      },
      "reason": reason,
      "sizeReason": if tree.shape_locked(id, "noResize") {
        "Shape resizing is locked"
      } else {
        reason
      },
      "deleteReason": delete_reason,
      "hyperlink": self.drawing_link_summary(tree, id, links~, bookmarks~),
    })
  }
  { "revision": revision, "items": items }
}

///|
fn shape_fill_markup(color : String, alpha~ : Double = 1) -> String {
  if color.is_empty() {
    "<a:noFill xmlns:a=\"\{picture_drawing_uri}\"/>"
  } else {
    let rgb = if alpha == 1 {
      "<a:srgbClr val=\"\{color}\"/>"
    } else {
      "<a:srgbClr val=\"\{color}\"><a:alpha val=\"\{(alpha * 100000).round().to_int()}\"/></a:srgbClr>"
    }
    "<a:solidFill xmlns:a=\"\{picture_drawing_uri}\">\{rgb}</a:solidFill>"
  }
}

///|
fn WordTree::shape_property_change(
  self : WordTree,
  parent : Int32,
  existing : Int32?,
  before : Int32?,
  markup : String,
) -> @xml.SourceChange raise @failure.Failure {
  let node = self.nodes[parent]
  let old = existing.map(id => self.nodes[id])
  if old is Some(old) {
    let source = self.source[old.start:old.end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      @failure.reject(
        "protected-content", "Shape property contains unknown source markup",
      )
    }
  }
  {
    node: parent,
    offset: old
    .map(n => n.start)
    .unwrap_or(
      before.map(id => self.nodes[id].start).unwrap_or(node.closing_start),
    ) -
    node.start,
    length: old.map(n => n.end - n.start).unwrap_or(0),
    xml: markup,
  }
}

///|
fn check_shape_properties(
  preset : String,
  width : Double,
  height : Double,
  fill : String,
  stroke : String,
  line_width : Double,
) -> (Double, Double, Double) raise @failure.Failure {
  guard ["rect", "ellipse", "line", "polyline"].contains(preset) &&
    [width, height].all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v <= 14400) &&
    !line_width.is_nan() &&
    !line_width.is_inf() &&
    line_width >= 0 &&
    line_width <= 1584 &&
    [fill, stroke].all(v => {
      v.is_empty() ||
      (v.length() == 6 && v.iter().all(c => c.is_ascii_hexdigit()))
    }) else {
    @failure.reject("invalid-operation", "Invalid shape dimensions or paint")
  }
  let width = (width * 12700).round() / 12700
  let height = (height * 12700).round() / 12700
  let line_width = (line_width * 12700).round() / 12700
  guard (preset != "polyline" || (fill.is_empty() && !stroke.is_empty())) &&
    (if preset == "line" {
      width > 0 || height > 0
    } else {
      width > 0 && height > 0
    }) &&
    (stroke.is_empty() || line_width > 0) else {
    @failure.reject("invalid-operation", "Shape dimensions or stroke are empty")
  }
  (width, height, line_width)
}

///|
/// Edits an existing ordinary shape in points and RGB colors; empty colors mean no fill.
pub fn Session::edit_shape(
  self : Session,
  revision : Int32,
  id : Int32,
  width : Double,
  height : Double,
  fill : String,
  stroke : String,
  line_width : Double,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let prepared = self.prepare_shape_edit(
    id, width, height, fill, stroke, line_width,
  )
  if prepared is Some(prepared) {
    self.check_picture_layout(prepared.document, probe, profile, images)
    self.commit_edit(prepared.edit, prepared.document)
  }
  self.edit_result(prepared.map(value => value.edit.paragraphs).unwrap_or([]))
}

///|
fn Session::prepare_shape_edit(
  self : Session,
  id : Int32,
  width : Double,
  height : Double,
  fill : String,
  stroke : String,
  line_width : Double,
) -> PreparedEdit? raise @failure.Failure {
  let document = self.document()
  let tree = WordTree::new(document)
  let (paragraph, frame, properties) = self.editable_shape(tree, id)
  guard frame.content is (@layout.Shape(shape) | @layout.TextBox(shape, _)) else {
    abort("Shape payload expected")
  }
  let (width, height, line_width) = check_shape_properties(
    shape.preset,
    width,
    height,
    fill,
    stroke,
    line_width,
  )
  let resized = frame.width != width || frame.height != height
  if resized {
    guard !tree.shape_locked(id, "noResize") else {
      @failure.reject("protected-content", "Shape resizing is locked")
    }
    if tree.shape_locked(id, "noChangeAspect") {
      guard (width * frame.height - height * frame.width).abs() <=
        (frame.width + frame.height) / 12700 else {
        @failure.reject("protected-content", "Shape aspect ratio is locked")
      }
    }
  }
  let changes : Array[@xml.SourceChange] = []
  if resized {
    for child in tree.descendants(id) {
      let node = tree.nodes[child]
      if (node.uri == picture_inline_uri && node.name == "extent") ||
        (node.uri == picture_drawing_uri && node.name == "ext") {
        for attr in node.attributes {
          let value = if attr.name == "cx" { width } else { height }
          let xml = (value * 12700).round().to_int64().to_string()
          if attr.value != xml {
            changes.push({
              node: child,
              offset: attr.start - node.start,
              length: attr.end - attr.start,
              xml,
            })
          }
        }
      }
    }
  }
  let line = tree.drawing_child(properties, "ln")
  if fill.to_upper() != shape.fill.to_upper() {
    let existing = match tree.drawing_child(properties, "solidFill") {
      Some(id) => Some(id)
      None => tree.drawing_child(properties, "noFill")
    }
    changes.push(
      tree.shape_property_change(
        properties,
        existing,
        line,
        shape_fill_markup(fill.to_upper()),
      ),
    )
  }
  if stroke.to_upper() != shape.stroke.to_upper() ||
    line_width != shape.lineWidth {
    let ink = shape.preset == "polyline"
    let markup = "<a:ln xmlns:a=\"\{picture_drawing_uri}\" w=\"\{(line_width * 12700).round().to_int64()}\"\{if ink { " cap='rnd'" } else { "" }}>\{shape_fill_markup(stroke.to_upper(),alpha=shape.strokeAlpha)}\{if ink { "<a:round/>" } else { "" }}</a:ln>"
    changes.push(tree.shape_property_change(properties, line, None, markup))
  }
  if changes.is_empty() {
    return None
  }
  let (candidate, xml) = document.edit_source(changes)
  Some({
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
    document: candidate,
    typing_text: None,
    join_group: false,
  })
}

///|
/// Deletes only the drawing source, retaining relationships and shared resources.
pub fn Session::delete_shape(
  self : Session,
  revision : Int32,
  id : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let (paragraph, _, _) = self.editable_shape(tree, id)
  guard !tree.shape_locked(id, "noDelete") else {
    @failure.reject("protected-content", "Shape deletion is locked")
  }
  tree.check_picture_references(id)
  self.delete_drawing(document, tree, id, paragraph)
}
