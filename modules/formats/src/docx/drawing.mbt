///|
fn Session::drawing_frame(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> @layout.DrawingFrame raise @failure.Failure {
  let (_, data) = tree.drawing_data(id)
  if data.attribute("uri") == Some(chart_uri) {
    let resource = self.read_chart(tree, id)
    let (width, height, anchor) = tree.drawing_geometry(id)
    let frame : @layout.DrawingFrame = {
      width,
      height,
      effectExtent: tree.drawing_effect_extent(id),
      anchor,
      content: @layout.Chart(@layout.ChartFrame::new(resource.data)),
    }
    frame.validate()
    return frame
  }
  if data.attribute("uri") == Some(word_shape_uri) {
    let frame = tree.read_basic_shape(id, data.id)
    let shape = tree.children[data.id][0]
    if tree.linked_text_boxes(shape) is Some((members, sequence)) {
      let result = {
        ..frame,
        content: self.linked_shape_text(tree, members, sequence),
      }
      result.validate()
      return result
    }
    if tree.drawing_child(shape, "txbx", uri=word_shape_uri) is Some(text) {
      guard frame.content is @layout.Shape(paint) &&
        !["line", "polyline"].contains(paint.preset) else {
        @failure.reject(
          "unsupported-layout", "Line shape text requires support",
        )
      }
      let result : @layout.DrawingFrame = {
        ..frame,
        content: @layout.TextBox(paint, self.shape_text(tree, shape, text)),
      }
      result.validate()
      return result
    }
    return frame
  }
  let picture = self.image_frame(tree, id)
  {
    width: picture.width,
    height: picture.height,
    effectExtent: tree.drawing_effect_extent(id),
    anchor: picture.anchor,
    content: @layout.Picture(picture.key, picture.crop),
  }
}

///|
let word_shape_uri = "http://schemas.microsoft.com/office/word/2010/wordprocessingShape"

///|
let drawing_2010_uri = "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing"

///|
fn WordTree::drawing_data(
  self : WordTree,
  id : Int32,
) -> (@xml.Node, @xml.Node) raise @failure.Failure {
  guard self.children[id] is [frame] &&
    self.nodes[frame].uri == picture_inline_uri &&
    ["inline", "anchor"].contains(self.nodes[frame].name) else {
    @failure.reject(
      "unsupported-layout", "Drawing requires one inline or anchored frame",
    )
  }
  let graphics = self.children[frame].filter(child => {
    self.nodes[child].uri == picture_drawing_uri &&
    self.nodes[child].name == "graphic"
  })
  guard graphics is [graphic] &&
    self.children[graphic] is [data] &&
    self.nodes[data].uri == picture_drawing_uri &&
    self.nodes[data].name == "graphicData" else {
    @failure.reject(
      "unsupported-layout", "Drawing requires one graphic payload",
    )
  }
  (self.nodes[frame], self.nodes[data])
}

///|
fn drawing_number(
  node : @xml.Node,
  name : String,
) -> Double raise @failure.Failure {
  let value = @string.parse_int64(node.attribute(name).unwrap_or("")[:]) catch {
    _ => @failure.reject("unsupported-layout", "Invalid drawing coordinate")
  }
  guard value >= 0 && value <= 182880000L else {
    @failure.reject("limit-exceeded", "Drawing coordinate exceeds budget")
  }
  value.to_double() / 12700
}

///|
fn WordTree::drawing_geometry(
  self : WordTree,
  id : Int32,
) -> (Double, Double, @layout.DrawingAnchor?) raise @failure.Failure {
  let (frame, _) = self.drawing_data(id)
  let anchor = if frame.name == "anchor" {
    Some(self.image_anchor(id, frame.id))
  } else {
    self.anchor_children(frame.id, [
      "extent", "effectExtent", "docPr", "cNvGraphicFramePr", "graphic",
    ])
    guard frame.attributes.all(a => {
      a.uri.is_empty() && ["distT", "distB", "distL", "distR"].contains(a.name)
    }) else {
      @failure.reject("unsupported-layout", "Unknown inline drawing attributes")
    }
    ignore(self.drawing_effect_extent(id))
    None
  }
  let extent = self.nodes[self.anchor_child(frame.id, "extent")]
  guard extent.attributes.all(a => {
      a.uri.is_empty() && ["cx", "cy"].contains(a.name)
    }) &&
    self.children[extent.id].is_empty() else {
    @failure.reject("unsupported-layout", "Unknown drawing extent")
  }
  (drawing_number(extent, "cx"), drawing_number(extent, "cy"), anchor)
}

///|
fn WordTree::drawing_effect_extent(
  self : WordTree,
  id : Int32,
) -> (Double, Double, Double, Double) raise @failure.Failure {
  let (frame, _) = self.drawing_data(id)
  for child in self.children[frame.id] {
    let node = self.nodes[child]
    if node.uri == picture_inline_uri && node.name == "effectExtent" {
      guard self.children[child].is_empty() &&
        node.text.trim().is_empty() &&
        node.attributes.length() == 4 &&
        node.attributes.all(a => {
          a.uri.is_empty() && ["l", "t", "r", "b"].contains(a.name)
        }) else {
        @failure.reject("unsupported-layout", "Invalid drawing effect extent")
      }
      return (
        drawing_number(node, "l"),
        drawing_number(node, "t"),
        drawing_number(node, "r"),
        drawing_number(node, "b"),
      )
    }
  }
  (0, 0, 0, 0)
}
