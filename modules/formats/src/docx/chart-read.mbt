///|
let chart_uri = "http://schemas.openxmlformats.org/drawingml/2006/chart"

///|
fn Session::read_chart(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> @chart.Resource raise @failure.Failure {
  let (_, data) = tree.drawing_data(id)
  guard data.attribute("uri") == Some(chart_uri) &&
    tree.children[data.id] is [child] else {
    @failure.reject("unsupported-chart", "Drawing requires one native chart")
  }
  let node = tree.nodes[child]
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  guard node.uri == chart_uri &&
    node.name == "chart" &&
    tree.children[child].is_empty() &&
    node.attributes.length() == 1 &&
    node.attribute("id", uri=rel_uri) is Some(link) else {
    @failure.reject("unsupported-chart", "Unsupported chart frame reference")
  }
  let part = @chart.link(self.opc, self.main, link, "chart", self.parts)
  @chart.read(self.opc, part, self.parts)
}

///|
fn Session::chart_workbook(
  self : Session,
  chart : @chart.Resource,
) -> Bytes raise @failure.Failure {
  let bytes = self.media
    .get(chart.workbook)
    .unwrap_or_else(() => self.opc.read(chart.workbook))
  let actual = @xlsx.chart_data(
    chart.data.kind,
    chart.data.title,
    bytes,
    self.opc.budget,
    hole_size=chart.data.hole_size,
    legend=Some(chart.data.legend),
  )
  guard actual == chart.data else {
    @failure.reject(
      "protected-content", "Chart cache and embedded workbook disagree",
    )
  }
  bytes
}

///|
fn Session::editable_chart(
  self : Session,
  tree : WordTree,
  id : Int32,
  operation~ : ChartOperation = ChartContent,
) -> (Int32, @chart.Resource) raise @failure.Failure {
  if operation != ChartCopy && operation != ChartRetain {
    self.check_document_protection()
  }
  let paragraph = self.drawing_paragraph(tree, id)
  let chart = self.read_chart(tree, id)
  ignore(self.drawing_frame(tree, id))
  ignore(self.chart_workbook(chart))
  let links = self.relationships().filter(link => link.target == chart.part)
  guard links.length() == 1 && links[0].owner == self.main else {
    @failure.reject(
      "protected-content", "Shared chart parts require independent editing",
    )
  }
  let uses = tree.order.filter(child => {
    tree.nodes[child].uri == chart_uri &&
    tree.nodes[child].name == "chart" &&
    tree.nodes[child].attribute(
      "id",
      uri="http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    ) ==
    Some(links[0].id)
  })
  guard uses.length() == 1 else {
    @failure.reject(
      "protected-content", "Shared chart references require independent editing",
    )
  }
  let root = self.part_xml(chart.part).nodes()[0]
  let source = self.part_xml(chart.part).source()[root.start:root.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque chart source requires editing support",
    )
  }
  tree.check_chart_operation(id, operation)
  (paragraph, chart)
}

///|
pub fn Session::charts(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let items : Array[Json] = []
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri ||
      node.name != "drawing" ||
      !tree
      .descendants(id)
      .any(child => tree.nodes[child].attribute("uri") == Some(chart_uri)) {
      continue
    }
    guard items.length() < 256 else {
      @failure.reject("limit-exceeded", "Chart catalog exceeds256 items")
    }
    let item : Map[String, Json] = {
      "id": Json(id),
      "width": 0,
      "height": 0,
      "settings": Json::null(),
      "anchor": Json::null(),
      "selected": false,
    }
    let retained = try {
      let (_, chart) = self.editable_chart(tree, id, operation=ChartRetain)
      let frame = self.drawing_frame(tree, id)
      item["width"] = Json(frame.width)
      item["height"] = Json(frame.height)
      item["settings"] = chart.data.query()
      item["anchor"] = frame.anchor
        .map(anchor => anchor.to_json())
        .unwrap_or(Json::null())
      item["selected"] = Json(
        self.selected_drawing(tree) == Some(id) &&
        !tree.shape_locked(id, "noSelect"),
      )
      ""
    } catch {
      @failure.Failure(code="limit-exceeded", ..) as error => raise error
      @failure.Failure(message~, ..) => message
    }
    fn reason(operation : ChartOperation) -> String raise @failure.Failure {
      if !retained.is_empty() {
        return retained
      }
      try {
        self.check_document_protection()
        tree.check_chart_operation(id, operation)
        if operation == ChartDelete {
          tree.check_picture_references(id)
        }
        ""
      } catch {
        @failure.Failure(code="limit-exceeded", ..) as error => raise error
        @failure.Failure(message~, ..) => message
      }
    }
    item["reason"] = Json(reason(ChartContent))
    item["deleteReason"] = Json(reason(ChartDelete))
    item["sizeReason"] = Json(reason(ChartResize))
    item["positionReason"] = Json(reason(ChartPosition))
    items.push(Json(item))
  }
  { "revision": revision, "items": items }
}
