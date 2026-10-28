///|
fn worksheet_color_valid(color : String) -> Bool {
  color.length() == 6 &&
  color
  .iter()
  .all(c => {
    (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
  })
}

///|
fn WorksheetChart::color(self : WorksheetChart, index : Int32) -> String {
  self.colors.get(index).unwrap_or_else(() => @layout.chart_color(index))
}

///|
fn worksheet_color(
  document : @xml.Document,
  parent : @xml.Node,
) -> String raise @failure.Failure {
  let color = document
    .nodes()
    .iter()
    .find_first(node => {
      node.start > parent.start &&
      node.end < parent.end &&
      node.uri == drawing_uri &&
      node.name == "srgbClr"
    })
    .bind(node => node.attribute("val"))
    .unwrap_or("")
  guard worksheet_color_valid(color) else {
    @failure.reject("unsupported-chart", "Chart palette requires RGB colors")
  }
  color
}

///|
fn worksheet_palette(
  document : @xml.Document,
  pie : Bool,
) -> Array[String] raise @failure.Failure {
  let series = document
    .nodes()
    .iter()
    .filter(node => node.uri == chart_uri && node.name == "ser")
    .to_array()
  if pie {
    guard series.get(0) is Some(first) else {
      @failure.reject("unsupported-chart", "Missing chart series")
    }
    let tree = Tree::new("chart.xml", document)
    let points = tree.all(first.id, "dPt", uri=chart_uri)
    guard points.length() <= 256 else {
      @failure.reject("limit-exceeded", "Chart palette exceeds point limit")
    }
    points.map(point => worksheet_color(document, point))
  } else {
    series.map(series => worksheet_color(document, series))
  }
}

///|
fn WorksheetChart::palette_changes(
  self : WorksheetChart,
  document : @xml.Document,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let nodes = document.nodes()
  let series = nodes.filter(node => node.uri == chart_uri && node.name == "ser")
  let tree = Tree::new("chart.xml", document)
  let changes : Array[@xml.SourceChange] = []
  for index, series in series {
    if self.data.kind == "pie" &&
      index > 0 &&
      tree.all(series.id, "dPt", uri=chart_uri).is_empty() &&
      self.colors
      .mapi((index, color) => color.to_lower() != @layout.chart_color(index))
      .any(value => value) {
      let anchor = tree.one(series.id, "cat", uri=chart_uri).unwrap()
      let count = self.layout_data().categories.length()
      let xml = Array::makei(count, index => {
        pie_point_markup(index, self.color(index))
      }).join("")
      changes.push({
        node: series.id,
        offset: anchor.start - series.start,
        length: 0,
        xml,
      })
    }
    let targets = if ["pie", "doughnut"].contains(self.data.kind) {
      tree
      .all(series.id, "dPt", uri=chart_uri)
      .mapi((index, node) => (node, self.color(index)))
    } else {
      [(series, self.color(index))]
    }
    for (target, color) in targets {
      for node in nodes {
        if node.start > target.start &&
          node.end < target.end &&
          node.uri == drawing_uri &&
          node.name == "srgbClr" {
          changes.push({
            node: node.parent,
            offset: node.start - nodes[node.parent].start,
            length: node.end - node.start,
            xml: "<a:srgbClr val=\"\{color}\"/>",
          })
        }
      }
    }
  }
  changes
}

///|
fn WorksheetChart::layout_data(self : WorksheetChart) -> @layout.ChartData {
  let count = self.data.series.fold(init=self.data.categories.length().max(1), (
    count,
    series,
  ) => count.max(series.values.length()))
  {
    ..self.data,
    categories: Array::makei(count, index => {
      self.data.categories
      .get(index)
      .unwrap_or(
        if self.data.kind == "scatter" {
          ""
        } else {
          (index + 1).to_string()
        },
      )
    }),
    series: self.data.series.map(series => {
      ..series,
      values: Array::makei(count, index => {
        series.values.get(index).bind(value => value)
      }),
    }),
  }
}
