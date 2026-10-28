///|
fn markup_svg_path(segments : Array[@layout.PathSegment]) -> String {
  let path = StringBuilder()
  for segment in segments {
    match segment {
      @layout.Move(x, y) => path.write_string("M\{x} \{y} ")
      @layout.Line(x, y) => path.write_string("L\{x} \{y} ")
      @layout.Cubic(x1, y1, x2, y2, x, y) =>
        path.write_string("C\{x1} \{y1} \{x2} \{y2} \{x} \{y} ")
      @layout.Close => path.write_string("Z")
    }
  }
  path.to_string()
}

///|
fn shape_markup_svg(
  frame : @layout.DrawingFrame,
  shape : @layout.BasicShape,
  label : String,
  decoration~ : Bool = false,
) -> String raise @failure.Failure {
  let path = markup_svg_path(shape.path(frame.width, frame.height))
  let margin = if shape.stroke.is_empty() { 0.0 } else { shape.lineWidth / 2 }
  let width = (frame.width + 2 * margin).max(0.1)
  let height = (frame.height + 2 * margin).max(0.1)
  let fill = if shape.fill.is_empty() || shape.preset == "line" {
    "none"
  } else {
    "#" + shape.fill
  }
  let stroke = if shape.stroke.is_empty() { "none" } else { "#" + shape.stroke }
  "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
  (if decoration {
    "aria-hidden=\"true\""
  } else {
    "role=\"img\" aria-label=\"" + property_attribute(label) + "\""
  }) +
  " width=\"\{width}pt\" height=\"\{height}pt\" viewBox=\"\{-margin} \{-margin} \{width} \{height}\" style=\"" +
  (if decoration {
    "position:absolute;left:\{-margin}pt;top:\{-margin}pt;"
  } else {
    ""
  }) +
  "vertical-align:middle\"><path d=\"" +
  path +
  "\" fill=\"\{fill}\" stroke=\"\{stroke}\" stroke-width=\"\{shape.lineWidth}\" stroke-opacity=\"\{shape.strokeAlpha}\"" +
  (if shape.preset == "polyline" {
    " stroke-linecap=\"round\" stroke-linejoin=\"round\""
  } else {
    ""
  }) +
  " /></svg>"
}

///|
fn Session::markup_drawing(
  self : Session,
  tree : WordTree,
  styles : Styles,
  span : @layout.Span,
  output : MarkupOutput,
) -> String raise @failure.Failure {
  if span.drawing is Some({ content: Math(formula), .. }) {
    return mathml_markup(formula)
  }
  let link = self.markup_drawing_link(tree, span.node, output)
  let content = if output.charts.get(span.node) is Some(frame) {
    chart_markup_svg(frame, output)
  } else if tree.drawing_data(span.node).1.attribute("uri") ==
    Some(word_shape_uri) {
    let frame = self.drawing_frame(tree, span.node)
    let identity = tree.nodes[tree.drawing_link_node(span.node).0]
    let label = identity
      .attribute("descr")
      .unwrap_or_else(() => identity.attribute("name").unwrap_or("Shape"))
    if frame.content is @layout.TextBox(shape, text) {
      return self.markup_text_box(
        tree,
        styles,
        span.node,
        frame,
        shape,
        text,
        label,
        link,
        output,
      )
    }
    guard frame.content is @layout.Shape(shape) else {
      @failure.reject("unsupported-output", "Unknown drawing markup output")
    }
    tree.check_fragment_shape(span.node)
    shape_markup_svg(frame, shape, label)
  } else {
    self.markup_picture(tree, span, output)
  }
  if link is Some(attributes) {
    "<a" + attributes + ">" + content + "</a>"
  } else {
    content
  }
}

///|
fn Session::markup_drawing_link(
  self : Session,
  tree : WordTree,
  id : Int32,
  output : MarkupOutput,
) -> String? raise @failure.Failure {
  let target = self.drawing_link_target(
    tree,
    id,
    links=output.links,
    bookmarks=output.bookmarks,
  )
  guard target is Some(target) else { return None }
  guard tree.run_hyperlink(tree.nodes[id].parent) is None else {
    @failure.reject(
      "unsupported-output", "Nested drawing hyperlinks require output support",
    )
  }
  let click = tree.nodes[tree.drawing_link_node(id).1.unwrap()]
  let title = click.attribute("tooltip").unwrap_or("")
  let frame = click.attribute("tgtFrame").unwrap_or("")
  let frame = if frame.is_empty() {
    ""
  } else {
    " target=\"" + property_attribute(frame) + "\" rel=\"noopener noreferrer\""
  }
  Some(
    " href=\"" +
    property_attribute(output.link_target(target)) +
    "\" title=\"" +
    property_attribute(title) +
    "\"" +
    frame,
  )
}
