///|
fn Tree::sheet_graphic(
  tree : Tree,
  source : @xml.Node,
) -> (@xml.Node, @xml.Node) raise @failure.Failure {
  guard source.attributes.all(a => {
    a.uri.is_empty() &&
    (
      (a.name == "macro" && a.value.is_empty()) ||
      (a.name == "fPublished" && ["0", "1", "true", "false"].contains(a.value))
    )
  }) else {
    @failure.reject(
      "unsupported-chart", "Chart bindings or macros require support",
    )
  }
  guard tree.children
    .get(source.id)
    .unwrap_or([])
    .all(node => {
      (
        node.uri == picture_uri &&
        ["nvGraphicFramePr", "xfrm"].contains(node.name)
      ) ||
      (node.uri == picture_drawing_uri && node.name == "graphic")
    }) else {
    @failure.reject("unsupported-chart", "Unknown worksheet chart frame")
  }
  let nv = tree.picture_node(source.id, "nvGraphicFramePr")
  ignore(
    tree.shape_children(nv, ["cNvPr", "cNvGraphicFramePr"], uri=picture_uri),
  )
  let identity = tree.picture_node(nv.id, "cNvPr")
  let id = identity.attribute("id").unwrap_or("")
  guard natural(id, 2147483647) > 0 &&
    tree.children.get(identity.id).unwrap_or([]).is_empty() else {
    @failure.reject("unsupported-chart", "Chart identity requires support")
  }
  let nonvisual = tree.picture_node(nv.id, "cNvGraphicFramePr")
  ignore(tree.shape_children(nonvisual, ["graphicFrameLocks"]))
  let transform = tree.picture_node(source.id, "xfrm")
  guard transform.attributes.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Rotated worksheet chart frames require support",
    )
  }
  ignore(tree.shape_children(transform, ["off", "ext"]))
  let graphic = tree.picture_node(source.id, "graphic", uri=picture_drawing_uri)
  let data = tree.picture_node(
    graphic.id,
    "graphicData",
    uri=picture_drawing_uri,
  )
  ignore(tree.shape_children(graphic, ["graphicData"]))
  (identity, data)
}

///|
fn Session::read_sheet_chart(
  self : Session,
  sheet : Sheet,
  part : String,
  tree : Tree,
  frame : @xml.Node,
  source : @xml.Node,
  dimensions : Dimensions,
) -> SheetObject raise @failure.Failure {
  let (identity, data) = tree.sheet_graphic(source)
  let id = identity.attribute("id").unwrap()
  guard data.attribute("uri") == Some(chart_uri) else {
    @failure.reject("unsupported-chart", "Unknown worksheet graphic type")
  }
  ignore(tree.shape_children(data, ["chart"], uri=chart_uri))
  let node = tree.picture_node(data.id, "chart", uri=chart_uri)
  let relation = node
    .attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    )
    .unwrap_or("")
  let links = self
    .relationships()
    .filter(link => link.owner == part && link.id == relation)
  guard links is [link] &&
    !link.external &&
    link.kind == relationship_uri + "chart" else {
    @failure.reject(
      "unsupported-chart", "Chart requires an internal chart relationship",
    )
  }
  let transform = tree.picture_node(source.id, "xfrm")
  let (anchor, rect) = tree.drawing_rect(frame, dimensions, transform~)
  let client = tree.picture_child(frame.id, "clientData")
  if client is Some(client) {
    guard tree.children.get(client.id).unwrap_or([]).is_empty() &&
      client.attributes.all(a => {
        a.uri.is_empty() &&
        ["fPrintsWithSheet", "fLocksWithSheet"].contains(a.name) &&
        ["0", "1", "true", "false"].contains(a.value)
      }) else {
      @failure.reject(
        "unsupported-chart", "Unknown worksheet chart client data",
      )
    }
  }
  let visible = !flag(identity, "hidden")
  let document = self.part_xml(link.target)
  let chart = @chart.read_worksheet(link.target, document) catch {
    @failure.Failure(code="unsupported-chart", message~, offset~, ..) =>
      @failure.reject("unsupported-chart", message, part=link.target, offset~)
    error => raise error
  }
  let chart = if chart.native_line is Some(_) ||
    chart.native_radar is Some(_) ||
    chart.native_area is Some(_) ||
    chart.native_bubble is Some(_) ||
    chart.native_circular is Some(_) ||
    chart.native_bar is Some(_) ||
    chart.native_surface is Some(_) {
    chart.with_native_theme(self.theme, self.chart_theme_line_width())
  } else {
    chart
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    random: None,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let (pending, inputs) = self.chart_input_state(sheet.id, chart, work)
  let manual = self.calculation.map(c => c.manual).unwrap_or(false) &&
    inputs.any(input => input.3 is Some(_))
  let chart = if pending || manual {
    if !pending &&
      inputs.any(input => input.2 is Error(_)) &&
      (
        chart.native_bar is Some(_) ||
        chart.native_area is Some(_) ||
        chart.native_bubble is Some(_) ||
        (
          chart.native_line is Some(_) &&
          ["line", "scatter"].contains(chart.data.kind)
        ) ||
        (
          chart.native_circular is Some(_) &&
          chart.data.kind == "pie" &&
          chart.categories.is_empty()
        )
      ) {
      self.manual_chart_error_gaps(sheet.id, chart, work)
    } else {
      chart
    }
  } else {
    self.resolved_chart(sheet.id, chart, work)
  }
  {
    id,
    part,
    tree,
    frame,
    source,
    rect,
    anchor,
    name: identity.attribute("name").unwrap_or("Chart"),
    description: identity.attribute("descr").unwrap_or(""),
    media: None,
    shape: None,
    slicer: None,
    timeline: None,
    chart: Some((link.target, chart)),
    chart_visibility: Some(
      self.chart_visibility(sheet.id, chart, cached_only=pending),
    ),
    chart_pending: pending,
    crop: [0, 0, 0, 0],
    printable: client
    .map(node => flag(node, "fPrintsWithSheet", fallback=true))
    .unwrap_or(true),
    visible,
  }
}
