///|
pub struct NativePie {
  colors : Array[Array[(String, Double)]]
  explosions : Array[(Double, Array[Double])]
  first_angle : Double
}

///|
fn native_children(
  parent : Ref,
  names : Array[String],
  uri~ : String = chart_uri,
) -> Unit raise @failure.Failure {
  for child in parent.tree.children.get(parent.node.id).unwrap_or([]) {
    guard child.uri == uri && names.contains(child.name) else {
      @failure.reject(
        "unsupported-chart",
        "Unsupported native chart element \{child.name} in \{parent.node.name}",
        part=parent.tree.part,
      )
    }
  }
}

///|
fn native_empty(parent : Ref) -> Unit raise @failure.Failure {
  native_children(parent, [])
}

///|
fn native_flag(parent : Ref, expected : String) -> Unit raise @failure.Failure {
  native_empty(parent)
  guard parent.node.attribute("val").unwrap_or("1") == expected else {
    @failure.reject(
      "unsupported-chart",
      "Unsupported native chart setting: " + parent.node.name,
    )
  }
}

///|
fn native_no_paint(properties : Ref) -> Unit raise @failure.Failure {
  native_children(properties, ["noFill", "ln", "effectLst"], uri=drawing_uri)
  guard properties.child("noFill") is Some(fill) else {
    @failure.reject(
      "unsupported-chart", "Native chart background requires explicit noFill",
    )
  }
  native_empty(fill)
  if properties.child("ln") is Some(line) {
    native_children(line, ["noFill", "miter"], uri=drawing_uri)
    guard line.child("noFill") is Some(fill) else {
      @failure.reject(
        "unsupported-chart", "Native chart outline requires noFill",
      )
    }
    native_empty(fill)
    if line.child("miter") is Some(miter) {
      native_empty(miter)
    }
  }
  if properties.child("effectLst") is Some(effects) {
    native_empty(effects)
  }
}

///|
fn native_metadata(parent : Ref) -> Unit raise @failure.Failure {
  let source = parent.tree
  native_children(parent, ["ext"])
  for node in source.all(parent.node.id, "ext", uri=chart_uri) {
    let extension : Ref = { tree: source, node, }
    guard node.attribute("uri") ==
      Some("{C3380CC4-5D6E-409C-BE32-E72D297353CC}") else {
      @failure.reject("unsupported-chart", "Unknown native chart extension")
    }
    native_children(
      extension,
      ["uniqueId"],
      uri="http://schemas.microsoft.com/office/drawing/2014/chart",
    )
    for child in source.children.get(node.id).unwrap_or([]) {
      native_empty({ tree: source, node: child, })
    }
  }
}

///|
/// Reads explicit-fill, untitled circular caches without rewriting native styling.
pub fn read_native_pie(
  opc : @opc.Package,
  part : String,
  parts : Map[String, @xml.Document],
  color : (Int32) -> (String, Double) raise @failure.Failure,
) -> Resource raise @failure.Failure {
  let document = parts.get(part).unwrap_or_else(() => opc.xml(part))
  let (root, data) = read_chart(part, document, native=true)
  guard ["pie", "doughnut"].contains(data.kind) &&
    (data.kind == "doughnut" || data.series.length() == 1) else {
    @failure.reject(
      "unsupported-chart", "Native chart requires circular layout",
    )
  }
  let tree = root.tree
  for node in tree.children.get(root.node.id).unwrap_or([]) {
    let item : Ref = { tree, node, }
    if node.uri == chart_uri {
      match node.name {
        "chart" | "externalData" | "clrMapOvr" | "spPr" => ()
        "date1904" => {
          native_empty(item)
          ignore(number(node.attribute("val").unwrap_or("1"), 0, 1))
        }
        "lang" => native_empty(item)
        "roundedCorners" => native_flag(item, "0")
        "style" => native_flag(item, "18")
        _ =>
          @failure.reject(
            "unsupported-chart", "Unsupported native chart metadata",
          )
      }
    } else if node.uri ==
      "http://schemas.openxmlformats.org/markup-compatibility/2006" &&
      node.name == "AlternateContent" {
      for branch in tree.children.get(node.id).unwrap_or([]) {
        guard branch.uri == node.uri &&
          ["Choice", "Fallback"].contains(branch.name) else {
          @failure.reject(
            "unsupported-chart", "Unsupported native chart choice",
          )
        }
        for style in tree.children.get(branch.id).unwrap_or([]) {
          guard style.name == "style" &&
            (
              (style.uri == chart_uri && style.attribute("val") == Some("18")) ||
              (
                style.uri ==
                "http://schemas.microsoft.com/office/drawing/2007/8/2/chart" &&
                style.attribute("val") == Some("118")
              )
            ) else {
            @failure.reject(
              "unsupported-chart", "Unsupported native chart style",
            )
          }
          native_empty({ tree, node: style, })
        }
      }
    } else {
      @failure.reject("unsupported-chart", "Unsupported native chart namespace")
    }
  }
  guard document
    .nodes()
    .any(node => {
      node.name == "style" &&
      (
        (node.uri == chart_uri && node.attribute("val") == Some("18")) ||
        (
          node.uri ==
          "http://schemas.microsoft.com/office/drawing/2007/8/2/chart" &&
          node.attribute("val") == Some("118")
        )
      )
    }) else {
    @failure.reject(
      "unsupported-chart", "Native circular chart requires a known style",
    )
  }
  native_no_paint(chart_child(root, "spPr"))
  let chart = chart_child(root, "chart")
  native_children(chart, [
    "autoTitleDeleted", "plotArea", "plotVisOnly", "dispBlanksAs", "showDLblsOverMax",
  ])
  native_flag(chart_child(chart, "autoTitleDeleted"), "1")
  if chart.child("plotVisOnly", uri=chart_uri) is Some(flag) {
    native_flag(flag, "1")
  }
  if chart.child("dispBlanksAs", uri=chart_uri) is Some(flag) {
    native_flag(flag, "gap")
  }
  if chart.child("showDLblsOverMax", uri=chart_uri) is Some(flag) {
    native_empty(flag)
    ignore(number(flag.node.attribute("val").unwrap_or("1"), 0, 1))
  }
  let plot = chart_child(chart, "plotArea")
  native_children(plot, ["layout", "pieChart", "doughnutChart", "spPr"])
  if plot.child("layout", uri=chart_uri) is Some(layout) {
    native_empty(layout)
  }
  native_no_paint(chart_child(plot, "spPr"))
  guard tree.children
    .get(plot.node.id)
    .unwrap_or([])
    .filter(n => {
      n.uri == chart_uri && ["pieChart", "doughnutChart"].contains(n.name)
    })
    .length() ==
    1 else {
    @failure.reject(
      "unsupported-chart", "Native circular combinations require support",
    )
  }
  let circular = chart_child(
    plot,
    if data.kind == "pie" {
      "pieChart"
    } else {
      "doughnutChart"
    },
  )
  native_children(circular, [
    "varyColors", "ser", "dLbls", "firstSliceAng", "holeSize",
  ])
  if circular.child("varyColors", uri=chart_uri) is Some(flag) {
    native_flag(flag, "1")
  }
  let first_angle = circular
    .child("firstSliceAng", uri=chart_uri)
    .map(n => number(n.node.attribute("val").unwrap_or("0"), 0, 360))
    .unwrap_or(0)
  if circular.child("dLbls", uri=chart_uri) is Some(labels) {
    native_children(labels, [
      "showLegendKey", "showVal", "showCatName", "showSerName", "showPercent", "showBubbleSize",
      "showLeaderLines",
    ])
    for node in tree.children.get(labels.node.id).unwrap_or([]) {
      native_flag({ tree, node, }, "0")
    }
  }
  let colors : Array[Array[(String, Double)]] = []
  let explosions : Array[(Double, Array[Double])] = []
  for index, node in tree.all(circular.node.id, "ser", uri=chart_uri) {
    let series : Ref = { tree, node, }
    native_children(series, [
      "idx", "order", "tx", "explosion", "dPt", "cat", "val", "extLst",
    ])
    let categories = chart_points(
      chart_child(chart_child(chart_child(series, "cat"), "strRef"), "strCache"),
      false,
    )
    guard categories == data.categories else {
      @failure.reject(
        "unsupported-chart", "Native circular series require matching categories",
      )
    }
    guard number(
        chart_child(series, "order").node.attribute("val").unwrap_or(""),
        0,
        31,
      ) ==
      index.to_double() else {
      @failure.reject(
        "unsupported-chart", "Native circular series order requires support",
      )
    }
    let parent = series
      .child("explosion", uri=chart_uri)
      .map(n => number(n.node.attribute("val").unwrap_or("0"), 0, 400))
      .unwrap_or(0)
    let palette : Array[(String, Double)?] = Array::make(
      data.categories.length(),
      None,
    )
    let offsets = Array::make(data.categories.length(), parent)
    let seen : Map[Int32, Bool] = Map([])
    for point in tree.all(node.id, "dPt", uri=chart_uri) {
      let item : Ref = { tree, node: point, }
      native_children(item, ["idx", "bubble3D", "spPr", "explosion", "extLst"])
      let position = number(
        chart_child(item, "idx").node.attribute("val").unwrap_or(""),
        0,
        255,
      ).to_int()
      guard !seen.contains(position) else {
        @failure.reject(
          "unsupported-chart", "Duplicate native chart point style",
        )
      }
      seen[position] = true
      if item.child("bubble3D", uri=chart_uri) is Some(flag) {
        native_flag(flag, "0")
      }
      if item.child("extLst", uri=chart_uri) is Some(extension) {
        native_metadata(extension)
      }
      let properties = chart_child(item, "spPr")
      native_children(
        properties,
        ["solidFill", "ln", "effectLst"],
        uri=drawing_uri,
      )
      let fill = properties
        .child("solidFill")
        .unwrap_or_error(
          @failure.Failure(
            code="unsupported-chart",
            message="Native circular points require explicit solid fills",
            part~,
            offset=-1,
          ),
        )
      if properties.child("ln") is Some(line) {
        native_children(line, ["noFill"], uri=drawing_uri)
        guard line.child("noFill") is Some(fill) else {
          @failure.reject(
            "unsupported-chart", "Native point outlines require support",
          )
        }
        native_empty(fill)
      }
      if properties.child("effectLst") is Some(effects) {
        native_empty(effects)
      }
      let paint = color(fill.node.id)
      let explosion = item
        .child("explosion", uri=chart_uri)
        .map(n => number(n.node.attribute("val").unwrap_or("0"), 0, 400))
        .unwrap_or(parent)
      // shortcut: larger independent offsets need native frame clipping before they can be displayed.
      guard explosion <= parent else {
        @failure.reject(
          "unsupported-chart", "Independent native point explosion requires support",
        )
      }
      if position < palette.length() {
        palette[position] = Some(paint)
        offsets[position] = explosion
      }
    }
    if series.child("extLst", uri=chart_uri) is Some(extension) {
      native_metadata(extension)
    }
    guard palette.all(c => c is Some(_)) else {
      @failure.reject(
        "unsupported-chart", "Native circular points require explicit colors",
      )
    }
    colors.push(palette.map(c => c.unwrap()))
    explosions.push((parent, offsets))
  }
  let external = chart_child(root, "externalData")
  native_children(external, ["autoUpdate"])
  if external.child("autoUpdate", uri=chart_uri) is Some(update) {
    native_flag(update, "0")
  }
  let workbook = link(
    opc,
    part,
    external.node.attribute("id", uri=relationship_uri).unwrap_or(""),
    "package",
    parts,
  )
  {
    part,
    workbook,
    data,
    native_pie: Some({ colors, explosions, first_angle, }),
  }
}
