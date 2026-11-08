///|
fn chart_child(parent : Ref, name : String) -> Ref raise @failure.Failure {
  parent
  .child(name, uri=chart_uri)
  .unwrap_or_error(
    @failure.Failure(
      code="unsupported-chart",
      part=parent.tree.part,
      offset=-1,
      message="Missing chart " + name,
    ),
  )
}

///|
pub fn link(
  opc : @opc.Package,
  owner : String,
  id : String,
  kind : String,
  parts : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  if parts.get(relationship_part(owner)) is Some(document) {
    let root = document.nodes()[0]
    let links = document
      .nodes()
      .filter(n => n.parent == root.id && n.attribute("Id") == Some(id))
    guard links is [link] &&
      link.attribute("Type") == Some(relationship_uri + "/" + kind) &&
      [None, Some("Internal")].contains(link.attribute("TargetMode")) else {
      @failure.reject(
        "unsupported-chart", "Chart requires a known internal relationship",
      )
    }
    return @opc.resolve_target(owner, link.attribute("Target").unwrap_or(""))
  }
  let links = opc
    .relationships()
    .filter(link => link.owner == owner && link.id == id)
  guard links is [link] &&
    link.kind == relationship_uri + "/" + kind &&
    !link.external else {
    @failure.reject(
      "unsupported-chart", "Chart requires a known internal relationship",
    )
  }
  link.target
}

///|
fn chart_points(
  cache : Ref,
  numeric : Bool,
) -> Array[String] raise @failure.Failure {
  let count = number(
    chart_child(cache, "ptCount").node.attribute("val").unwrap_or(""),
    0,
    256,
  ).to_int()
  let values = Array::make(count, "")
  let seen : Map[Int32, Bool] = Map([])
  for node in cache.tree.all(cache.node.id, "pt", uri=chart_uri) {
    let index = number(
      node.attribute("idx").unwrap_or(""),
      0,
      (count - 1).to_double(),
    ).to_int()
    guard !seen.contains(index) else {
      @failure.reject("unsupported-chart", "Duplicate chart cache index")
    }
    seen[index] = true
    values[index] = chart_child({ tree: cache.tree, node, }, "v").node.text
  }
  guard numeric || seen.length() == count else {
    @failure.reject(
      "unsupported-chart", "Chart category cache must be complete",
    )
  }
  values
}

///|
fn chart_categories(
  series : Ref,
  scatter : Bool,
) -> Array[String] raise @failure.Failure {
  let source = chart_child(series, if scatter { "xVal" } else { "cat" })
  let numeric = source.child("numRef", uri=chart_uri)
  let text = source.child("strRef", uri=chart_uri)
  guard !(numeric is Some(_) && text is Some(_)) else {
    @failure.reject("unsupported-chart", "Ambiguous chart category source")
  }
  let numeric = numeric is Some(_)
  guard !scatter || numeric else {
    @failure.reject("unsupported-chart", "Scatter categories require numbers")
  }
  let cache = chart_child(
    chart_child(source, if numeric { "numRef" } else { "strRef" }),
    if numeric {
      "numCache"
    } else {
      "strCache"
    },
  )
  let values = chart_points(cache, numeric)
  if numeric {
    for value in values {
      if value.is_empty() {
        continue
      }
      let number = @string.parse_double(value) catch {
        _ =>
          @failure.reject("unsupported-chart", "Invalid numeric category cache")
      }
      guard !number.is_nan() && !number.is_inf() else {
        @failure.reject(
          "unsupported-chart", "Non-finite numeric category cache",
        )
      }
    }
  }
  values
}

///|
fn chart_series_name(
  series : Ref,
  native : Bool,
) -> String raise @failure.Failure {
  if series.child("tx", uri=chart_uri) is Some(title) {
    let names = chart_points(
      chart_child(chart_child(title, "strRef"), "strCache"),
      false,
    )
    guard names is [name] else {
      @failure.reject("unsupported-chart", "Chart series requires one title")
    }
    return name
  }
  guard native else {
    @failure.reject("unsupported-chart", "Missing chart series title")
  }
  let identity = chart_child(series, "idx")
  line_fields(identity, [], attributes=["val"])
  let index = number(
    identity.node.attribute("val").unwrap_or(""),
    0,
    4294967295,
  )
  guard index == index.floor() else {
    @failure.reject("unsupported-chart", "Invalid chart series identity")
  }
  "Series " + (index.to_int64() + 1).to_string()
}

///|
fn chart_rich_title(
  parent : Ref,
  line? : Int32,
) -> String raise @failure.Failure {
  let rich = chart_child(
    chart_child(chart_child(parent, "title"), "tx"),
    "rich",
  )
  let target = if line is Some(index) {
    let paragraphs = rich.tree.children
      .get(rich.node.id)
      .unwrap_or([])
      .filter(n => n.uri == drawing_uri && n.name == "p")
    guard paragraphs.get(index) is Some(node) else {
      @failure.reject("unsupported-chart", "Missing chart title paragraph")
    }
    node
  } else {
    rich.node
  }
  rich.tree.document
  .nodes()
  .filter(n => {
    n.start > target.start &&
    n.end < target.end &&
    n.uri == drawing_uri &&
    n.name == "t"
  })
  .map(n => n.text)
  .join("")
}

///|
fn chart_structure(actual : Ref, expected : Ref) -> Bool {
  let a = actual.node
  let b = expected.node
  if a.name != b.name ||
    a.uri != b.uri ||
    a.attributes.length() != b.attributes.length() ||
    !a.attributes.all(value => {
      b.attributes.any(other => {
        value.name == other.name &&
        value.uri == other.uri &&
        value.value == other.value
      })
    }) ||
    (if ["v", "t", "f", "formatCode"].contains(a.name) {
      a.text != b.text
    } else {
      a.text.trim() != b.text.trim()
    }) {
    return false
  }
  let left = actual.tree.children.get(a.id).unwrap_or([])
  let right = expected.tree.children.get(b.id).unwrap_or([])
  left.length() == right.length() &&
  left
  .mapi((i, node) => {
    chart_structure({ tree: actual.tree, node, }, {
      tree: expected.tree,
      node: right[i],
    })
  })
  .all(value => value)
}

///|
fn read_chart(
  part : String,
  document : @xml.Document,
  worksheet~ : Bool = false,
  native~ : Bool = false,
) -> (Ref, @layout.ChartData) raise @failure.Failure {
  let tree = Tree::new(part, document)
  guard document.nodes().length() <= 16384 &&
    document.source().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Chart XML exceeds layout limits")
  }
  let root : Ref = { tree, node: tree.root("chartSpace", uri=chart_uri), }
  let chart = chart_child(root, "chart")
  let plot = chart_child(chart, "plotArea")
  let lines = tree.all(plot.node.id, "lineChart", uri=chart_uri)
  let scatters = tree.all(plot.node.id, "scatterChart", uri=chart_uri)
  let (plot_source, kind) = if plot.child("pieChart", uri=chart_uri)
    is Some(pie) {
    (pie, "pie")
  } else if plot.child("doughnutChart", uri=chart_uri) is Some(doughnut) {
    (doughnut, "doughnut")
  } else if native && plot.child("ofPieChart", uri=chart_uri) is Some(split) {
    (split, "pie")
  } else if lines.get(0) is Some(node) {
    guard native || lines.length() == 1 else {
      @failure.reject(
        "unsupported-chart", "Multiple line groups require native layout",
      )
    }
    let line : Ref = { tree, node, }
    let kind = match chart_child(line, "grouping").node.attribute("val") {
      Some("standard") => "line"
      Some("stacked") => "stackedLine"
      Some("percentStacked") => "percentStackedLine"
      _ =>
        @failure.reject("unsupported-chart", "Unsupported line chart grouping")
    }
    (line, kind)
  } else if plot.child(
      if native && plot.child("area3DChart", uri=chart_uri) is Some(_) {
        "area3DChart"
      } else {
        "areaChart"
      },
      uri=chart_uri,
    )
    is Some(area) {
    let kind = match chart_child(area, "grouping").node.attribute("val") {
      Some("standard") => "area"
      Some("stacked") => "stackedArea"
      Some("percentStacked") => "percentStackedArea"
      _ =>
        @failure.reject("unsupported-chart", "Unsupported area chart grouping")
    }
    (area, kind)
  } else if scatters.get(0) is Some(node) {
    guard native || scatters.length() == 1 else {
      @failure.reject(
        "unsupported-chart", "Multiple scatter groups require native layout",
      )
    }
    ({ tree, node, }, "scatter")
  } else if native && plot.child("bubbleChart", uri=chart_uri) is Some(bubble) {
    (bubble, "scatter")
  } else if plot.child("radarChart", uri=chart_uri) is Some(radar) {
    (radar, "radar")
  } else {
    let bars = if native &&
      plot.child("bar3DChart", uri=chart_uri) is Some(bars) {
      bars
    } else {
      chart_child(plot, "barChart")
    }
    let direction = chart_child(bars, "barDir").node
      .attribute("val")
      .unwrap_or("")
    guard ["col", "bar"].contains(direction) else {
      @failure.reject("unsupported-chart", "Unsupported bar chart direction")
    }
    let grouping = chart_child(bars, "grouping").node
      .attribute("val")
      .unwrap_or("")
    guard ["clustered", "stacked", "percentStacked"].contains(grouping) ||
      (native && bars.node.name == "bar3DChart" && grouping == "standard") else {
      @failure.reject("unsupported-chart", "Unsupported bar chart grouping")
    }
    (
      bars,
      if grouping == "percentStacked" {
        if direction == "col" {
          "percentStackedColumn"
        } else {
          "percentStackedBar"
        }
      } else if grouping == "stacked" {
        if direction == "col" {
          "stackedColumn"
        } else {
          "stackedBar"
        }
      } else if direction == "col" {
        "column"
      } else {
        "bar"
      },
    )
  }
  let series = if native && kind == "line" {
    let groups = if plot.child("barChart", uri=chart_uri) is Some(_) {
      tree.children
      .get(plot.node.id)
      .unwrap_or([])
      .filter(node => {
        node.uri == chart_uri && ["barChart", "lineChart"].contains(node.name)
      })
    } else {
      lines
    }
    groups.map(node => tree.all(node.id, "ser", uri=chart_uri)).flatten()
  } else if native && !scatters.is_empty() {
    scatters.map(node => tree.all(node.id, "ser", uri=chart_uri)).flatten()
  } else {
    tree.all(plot_source.node.id, "ser", uri=chart_uri)
  }
  guard series.length() >= 1 && series.length() <= 32 else {
    @failure.reject("limit-exceeded", "Chart series exceed limits")
  }
  let first : Ref = { tree, node: series[0], }
  let categories = if native &&
    ["pie", "doughnut"].contains(kind) &&
    first.child("cat", uri=chart_uri) is None {
    let cache = chart_child(
      chart_child(chart_child(first, "val"), "numRef"),
      "numCache",
    )
    Array::makei(chart_points(cache, true).length(), index => {
      (index + 1).to_string()
    })
  } else {
    chart_categories(first, kind == "scatter")
  }
  let data : @layout.ChartData = {
    kind,
    legend: chart
    .child("legend", uri=chart_uri)
    .map(legend => {
      let position = chart_child(legend, "legendPos").node
        .attribute("val")
        .unwrap_or("")
      match position {
        "t" => "top"
        "b" => "bottom"
        "l" => "left"
        "r" => "right"
        _ =>
          @failure.reject(
            "unsupported-chart", "Unsupported chart legend position",
          )
      }
    })
    .unwrap_or("none"),
    hole_size: if kind == "doughnut" {
      Some(
        number(
          chart_child(plot_source, "holeSize").node
          .attribute("val")
          .unwrap_or(""),
          10,
          90,
        ).to_int(),
      )
    } else {
      None
    },
    title: if native {
      ""
    } else if ["pie", "doughnut"].contains(kind) {
      chart_rich_title(chart, line=0)
    } else {
      chart_rich_title(chart)
    },
    label: if native {
      ""
    } else if ["pie", "doughnut"].contains(kind) {
      chart_rich_title(chart, line=1)
    } else if kind == "scatter" {
      guard tree.all(plot.node.id, "valAx", uri=chart_uri) is [x_axis, _] else {
        @failure.reject(
          "unsupported-chart", "Scatter charts require two value axes",
        )
      }
      chart_rich_title({ tree, node: x_axis, })
    } else {
      chart_rich_title(chart_child(plot, "catAx"))
    },
    categories,
    series: series.map(node => {
      let item : Ref = { tree, node, }
      let name = chart_series_name(item, native)
      let values = chart_points(
        chart_child(
          chart_child(
            chart_child(item, if kind == "scatter" { "yVal" } else { "val" }),
            "numRef",
          ),
          "numCache",
        ),
        true,
      )
      {
        name,
        values: values.map(text => {
          if text.is_empty() {
            None
          } else {
            let value = @string.parse_double(text) catch {
              _ =>
                @failure.reject(
                  "unsupported-chart", "Invalid chart numeric cache",
                )
            }
            Some(value)
          }
        }),
      }
    }),
  }
  if worksheet {
    data.validate_sources()
  } else {
    data.validate()
  }
  (root, data)
}

///|
pub fn read(
  opc : @opc.Package,
  part : String,
  parts : Map[String, @xml.Document],
) -> Resource raise @failure.Failure {
  let document = parts.get(part).unwrap_or_else(() => opc.xml(part))
  let (data, workbook_link) = read_data(part, document)
  let workbook = link(opc, part, workbook_link, "package", parts)
  { part, workbook, data, native_pie: None, }
}

///|
/// Reads a supported native chart cache without resolving its workbook relationship.
pub fn read_data(
  part : String,
  document : @xml.Document,
) -> (@layout.ChartData, String) raise @failure.Failure {
  let (root, data) = read_chart(part, document)
  let external = chart_child(root, "externalData")
  let workbook_link = external.node
    .attribute("id", uri=relationship_uri)
    .unwrap_or("")
  let expected = @xml.Document::parse(
    @utf8.encode(markup(data, workbook_link)),
    part,
    64,
    4194304,
  )
  let expected_tree = Tree::new(part, expected)
  guard chart_structure(root, {
    tree: expected_tree,
    node: expected.nodes()[0],
  }) else {
    @failure.reject(
      "unsupported-chart", "Chart styles, axes or source formulas require support",
    )
  }
  (data, workbook_link)
}
