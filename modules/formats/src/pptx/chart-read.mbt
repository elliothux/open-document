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
fn chart_link(
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
    1,
    256,
  ).to_int()
  let values = Array::make(count, "")
  let seen : Map[Int, Bool] = Map([])
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
fn chart_rich_title(parent : Ref, line? : Int) -> String raise @failure.Failure {
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
  opc : @opc.Package,
  source : Ref,
  parts : Map[String, @xml.Document],
) -> DrawingChart raise @failure.Failure {
  let frame = source.child("graphic").bind(g => g.child("graphicData")).unwrap()
  let link = chart_child(frame, "chart").node
    .attribute("id", uri=relationship_uri)
    .unwrap_or("")
  let part = chart_link(opc, source.tree.part, link, "chart", parts)
  read_chart_part(opc, part, parts)
}

///|
fn read_chart_part(
  opc : @opc.Package,
  part : String,
  parts : Map[String, @xml.Document],
) -> DrawingChart raise @failure.Failure {
  let document = parts.get(part).unwrap_or_else(() => opc.xml(part))
  let tree = Tree::new(part, document)
  guard document.nodes().length() <= 16384 &&
    document.source().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Chart XML exceeds layout limits")
  }
  let root : Ref = { tree, node: tree.root("chartSpace", uri=chart_uri), }
  let chart = chart_child(root, "chart")
  let plot = chart_child(chart, "plotArea")
  let (plot_source, kind) = if plot.child("pieChart", uri=chart_uri)
    is Some(pie) {
    (pie, "pie")
  } else if plot.child("lineChart", uri=chart_uri) is Some(line) {
    (line, "line")
  } else if plot.child("areaChart", uri=chart_uri) is Some(area) {
    (area, "area")
  } else {
    let bars = chart_child(plot, "barChart")
    let direction = chart_child(bars, "barDir").node
      .attribute("val")
      .unwrap_or("")
    guard ["col", "bar"].contains(direction) else {
      @failure.reject("unsupported-chart", "Unsupported bar chart direction")
    }
    (bars, if direction == "col" { "column" } else { "bar" })
  }
  let series = tree.all(plot_source.node.id, "ser", uri=chart_uri)
  guard series.length() >= 1 && series.length() <= 8 else {
    @failure.reject("limit-exceeded", "Chart series exceed limits")
  }
  let categories = chart_points(
    chart_child(
      chart_child(chart_child({ tree, node: series[0], }, "cat"), "strRef"),
      "strCache",
    ),
    false,
  )
  let data : ChartData = {
    kind,
    title: if kind == "pie" {
      chart_rich_title(chart, line=0)
    } else {
      chart_rich_title(chart)
    },
    label: if kind == "pie" {
      chart_rich_title(chart, line=1)
    } else {
      chart_rich_title(chart_child(plot, "catAx"))
    },
    categories,
    series: series.map(node => {
      let item : Ref = { tree, node, }
      let names = chart_points(
        chart_child(chart_child(chart_child(item, "tx"), "strRef"), "strCache"),
        false,
      )
      guard names is [name] else {
        @failure.reject("unsupported-chart", "Chart series requires one title")
      }
      let values = chart_points(
        chart_child(chart_child(chart_child(item, "val"), "numRef"), "numCache"),
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
  data.validate()
  let external = chart_child(root, "externalData")
  let workbook_link = external.node
    .attribute("id", uri=relationship_uri)
    .unwrap_or("")
  let workbook = chart_link(opc, part, workbook_link, "package", parts)
  let expected = @xml.Document::parse(
    @utf8.encode(data.markup(workbook_link)),
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
  { part, workbook, data, }
}
