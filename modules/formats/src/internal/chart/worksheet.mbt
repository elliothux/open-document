///|
pub(all) struct WorksheetChart {
  data : @layout.ChartData
  categories : String
  names : Array[String]
  values : Array[String]
  colors : Array[String]
  native_line : NativeLine?
  native_radar : NativeRadar?
  native_area : NativeArea?
  native_bubble : NativeBubble?
  native_circular : NativeCircular?
  native_bar : NativeBar3d?
  native_surface : NativeSurface?
}

///|
pub fn WorksheetChart::markup(
  self : WorksheetChart,
) -> String raise @failure.Failure {
  guard self.native_line is None &&
    self.native_radar is None &&
    self.native_area is None &&
    self.native_bubble is None &&
    self.native_circular is None &&
    self.native_bar is None &&
    self.native_surface is None else {
    @failure.reject(
      "protected-content", "Native chart source rewriting requires support",
    )
  }
  self.data.validate_sources()
  guard self.names.length() == self.data.series.length() &&
    self.values.length() == self.data.series.length() &&
    self.colors.length() <= 256 &&
    self.colors.all(worksheet_color_valid) else {
    @failure.reject("invalid-chart", "Chart references must match every series")
  }
  let formulas = self.names
    .mapi((index, name) => [name, self.categories, self.values[index]])
    .flatten()
  guard formulas.all(value => {
    !value.is_empty() && value.length() <= 1024 && @xml.valid_text(value)
  }) else {
    @failure.reject("invalid-chart", "Chart references exceed source limits")
  }
  let document = @xml.Document::parse(
    @utf8.encode(markup(self.layout_data(), "worksheet")),
    "chart.xml",
    64,
    1048576,
  )
  let nodes = document.nodes()
  let sources = nodes
    .iter()
    .filter(node => node.uri == chart_uri && node.name == "f")
    .to_array()
  guard sources.length() == formulas.length() else {
    @failure.reject("invalid-chart", "Unexpected chart reference structure")
  }
  let changes : Array[@xml.SourceChange] = sources.mapi((index, node) => {
    node: node.id,
    offset: node.opening_end - node.start,
    length: node.closing_start - node.opening_end,
    xml: @xml.escape_text(formulas[index]),
  })
  let tree = Tree::new("chart.xml", document)
  for index, node in sources {
    let values = match index % 3 {
      0 => [self.data.series[index / 3].name]
      1 => self.data.categories
      _ =>
        self.data.series[index / 3].values.map(value => {
          value.map(value => value.to_string()).unwrap_or("")
        })
    }
    let numeric = index % 3 == 2 ||
      (index % 3 == 1 && self.data.kind == "scatter")
    let cache = tree
      .one(
        node.parent,
        if numeric {
          "numCache"
        } else {
          "strCache"
        },
        uri=chart_uri,
      )
      .unwrap()
    changes.push({
      node: cache.parent,
      offset: cache.start - nodes[cache.parent].start,
      length: cache.end - cache.start,
      xml: chart_cache(values, numeric),
    })
  }
  changes.append(self.palette_changes(document))
  for node in nodes {
    if node.uri == chart_uri && node.name == "externalData" {
      changes.push({
        node: node.parent,
        offset: node.start - nodes[node.parent].start,
        length: node.end - node.start,
        xml: "",
      })
    }
  }
  document.edit_source(changes).0.source()
}

///|
pub fn read_worksheet(
  part : String,
  document : @xml.Document,
) -> WorksheetChart raise @failure.Failure {
  if document
    .nodes()
    .any(node => node.uri == chart_uri && node.name == "ofPieChart") {
    return read_circular_worksheet(part, document)
  }
  if document
    .nodes()
    .any(node => {
      node.uri == chart_uri &&
      ["surfaceChart", "surface3DChart"].contains(node.name)
    }) {
    return read_surface_worksheet(part, document)
  }
  guard document
    .nodes()
    .filter(node => {
      node.uri == chart_uri && ["pieChart", "doughnutChart"].contains(node.name)
    })
    .length() ==
    1 else {
    return read_worksheet_known(part, document)
  }
  read_worksheet_known(part, document) catch {
    @failure.Failure(code="unsupported-chart", ..) =>
      read_circular_worksheet(part, document)
    error => raise error
  }
}

///|
fn read_worksheet_known(
  part : String,
  document : @xml.Document,
) -> WorksheetChart raise @failure.Failure {
  let nodes = document.nodes()
  let chart = nodes
    .iter()
    .find_first(n => n.uri == chart_uri && n.name == "chart")
  let untitled = chart is Some(chart) &&
    !nodes.any(n => {
      n.parent == chart.id && n.uri == chart_uri && n.name == "title"
    })
  let line_count = nodes
    .filter(n => n.uri == chart_uri && n.name == "lineChart")
    .length()
  let native_line_chart = line_count > 1 || (line_count == 1 && untitled)
  let native_radar_chart = nodes
    .filter(n => n.uri == chart_uri && n.name == "radarChart")
    .length() ==
    1 &&
    untitled
  let native_area_chart = nodes
    .filter(n => {
      n.uri == chart_uri && ["areaChart", "area3DChart"].contains(n.name)
    })
    .length() ==
    1 &&
    untitled
  let native_bubble_chart = nodes
    .filter(n => n.uri == chart_uri && n.name == "bubbleChart")
    .length() ==
    1
  let scatters = nodes.filter(n => {
    n.uri == chart_uri && n.name == "scatterChart"
  })
  let native_scatter_chart = scatters.length() > 1 ||
    scatters.any(group => {
      nodes.any(n => {
        n.parent == group.id &&
        n.uri == chart_uri &&
        n.name == "scatterStyle" &&
        n.attribute("val") != Some("marker")
      })
    })
  let native_bar_chart = nodes
    .filter(n => n.uri == chart_uri && n.name == "bar3DChart")
    .length() ==
    1
  let native = native_bar_chart ||
    native_line_chart ||
    native_radar_chart ||
    native_area_chart ||
    native_bubble_chart ||
    native_scatter_chart
  let (root, data) = read_chart(part, document, worksheet=true, native~)
  let native_line = if native_line_chart || native_scatter_chart {
    Some(read_native_line(root, scatter=native_scatter_chart))
  } else {
    None
  }
  let data = {
    ..data,
    title: native_line
    .bind(line => line.title)
    .map(title => title.text)
    .unwrap_or(data.title),
  }
  let native_radar = if native_radar_chart {
    Some(read_native_radar(root))
  } else {
    None
  }
  let native_area = if native_area_chart {
    Some(read_native_area(root))
  } else {
    None
  }
  let native_bubble = if native_bubble_chart {
    Some(read_native_bubble(root))
  } else {
    None
  }
  let formulas = document
    .nodes()
    .filter(node => {
      node.uri == chart_uri &&
      node.name == "f" &&
      (
        !native_bubble_chart ||
        document.node(document.node(node.parent).parent).name != "bubbleSize"
      )
    })
    .map(node => node.text)
  let references = nodes
    .iter()
    .filter(node => node.uri == chart_uri && node.name == "ser")
    .to_array()
    .map(node => {
      let source : Ref = { tree: root.tree, node, }
      let name = source
        .child("tx", uri=chart_uri)
        .map(title => chart_child(chart_child(title, "strRef"), "f").node.text)
        .unwrap_or("")
      let category = chart_child(
        source,
        if data.kind == "scatter" {
          "xVal"
        } else {
          "cat"
        },
      )
      let category = chart_child(
          chart_child(
            category,
            if category.child("numRef", uri=chart_uri) is Some(_) {
              "numRef"
            } else {
              "strRef"
            },
          ),
          "f",
        ).node.text
      let value = chart_child(
          chart_child(
            chart_child(
              source,
              if data.kind == "scatter" {
                "yVal"
              } else {
                "val"
              },
            ),
            "numRef",
          ),
          "f",
        ).node.text
      [name, category, value]
    })
  guard references.length() == data.series.length() &&
    references.flatten().filter(formula => !formula.is_empty()) ==
    formulas.iter().to_array() else {
    @failure.reject(
      "unsupported-chart", "Worksheet chart references must cover every series",
    )
  }
  let categories = references[0][1]
  guard references
    .map(reference => reference[1] == categories)
    .all(value => value) else {
    @failure.reject(
      "unsupported-chart", "Series require a common category source",
    )
  }
  let result : WorksheetChart = {
    data,
    categories,
    names: references.map(reference => reference[0]),
    values: references.map(reference => reference[2]),
    colors: if native_bar_chart {
      []
    } else {
      worksheet_palette(document, ["pie", "doughnut"].contains(data.kind))
    },
    native_line,
    native_radar,
    native_area,
    native_bubble,
    native_circular: None,
    native_surface: None,
    native_bar: if native_bar_chart {
      Some(read_native_bar3d(root))
    } else {
      None
    },
  }
  if native {
    return result
  }
  let expected = @xml.Document::parse(
    @utf8.encode(result.markup()),
    part,
    64,
    1048576,
  )
  let tree = Tree::new(part, expected)
  guard chart_structure(root, { tree, node: expected.nodes()[0], }) else {
    @failure.reject(
      "unsupported-chart", "Chart styles or source structure require support",
    )
  }
  result
}
