///|
pub struct NativeSurface {
  rotation : (Double, Double)
  perspective : Double
  height_percent : Double?
  depth : Double
  wireframe : Bool
  frame : (String, (String, Double))
  default_fill : Bool
  default_pen : Bool
  category : NativeLineAxis
  value : NativeLineAxis
  series_axis : NativeLineAxis
  value_hidden : Bool
  value_labels : Bool
  category_between : Bool
  plot : @layout.Border?
  floor : (String, (String, Double))
  side : (String, (String, Double))
  back : (String, (String, Double))
  legend : NativeLegend?
  palette : Array[String]
}

///|
fn surface_axis(
  source : Ref,
  category : Bool,
  fallback : @layout.TextStyle?,
  edge_layout~ : Bool = false,
) -> (NativeLineAxis, Bool, Bool) raise @failure.Failure {
  line_fields(source, [
    "axId", "scaling", "delete", "axPos", "majorGridlines", "title", "numFmt", "majorTickMark",
    "tickLblPos", "spPr", "txPr", "crossAx", "crosses", "lblAlgn", "lblOffset", "crossBetween",
  ])
  let scaling = chart_child(source, "scaling")
  line_fields(scaling, ["orientation"])
  native_flag(chart_child(scaling, "orientation"), "minMax")
  native_flag(chart_child(source, "axPos"), if category { "b" } else { "l" })
  native_flag(chart_child(source, "crosses"), "autoZero")
  let hidden = source
    .child("delete", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(false)
  let position = chart_child(source, "tickLblPos")
  line_fields(position, [], attributes=["val"])
  guard (if category {
    !hidden && position.node.attribute("val") == Some("low")
  } else {
    [Some("none"), Some("nextTo")].contains(position.node.attribute("val"))
  }) else {
    @failure.reject(
      "unsupported-chart", "Surface axis label position requires support",
    )
  }
  let tick = source
    .child("majorTickMark", uri=chart_uri)
    .map(node => {
      line_fields(node, [], attributes=["val"])
      let tick = node.node.attribute("val").unwrap_or("")
      guard ["none", "out"].contains(tick) else {
        @failure.reject(
          "unsupported-chart", "Surface tick direction requires support",
        )
      }
      tick
    })
    .unwrap_or("out")
  if source.child("numFmt", uri=chart_uri) is Some(format) {
    line_fields(format, [], attributes=["formatCode", "sourceLinked"])
    guard format.node.attribute("formatCode") == Some("General") &&
      [None, Some("1"), Some("true")].contains(
        format.node.attribute("sourceLinked"),
      ) else {
      @failure.reject(
        "unsupported-chart", "Surface axis number format requires support",
      )
    }
  }
  for name in ["axId", "crossAx"] {
    let node = chart_child(source, name)
    line_fields(node, [], attributes=["val"])
    let id = number(node.node.attribute("val").unwrap_or(""), 1, 4294967295)
    guard id == id.floor() else {
      @failure.reject("unsupported-chart", "Invalid surface axis identifier")
    }
  }
  for (name, value) in [("lblAlgn", "ctr"), ("lblOffset", "100")] {
    if source.child(name, uri=chart_uri) is Some(node) {
      native_flag(node, value)
    }
  }
  if source.child("crossBetween", uri=chart_uri) is Some(node) {
    line_fields(node, [], attributes=["val"])
    guard !category &&
      [Some("between"), Some("midCat")].contains(node.node.attribute("val")) else {
      @failure.reject(
        "unsupported-chart", "Surface axis crossing requires support",
      )
    }
  }
  let pen = fn(name : String, grid : Bool) raise @failure.Failure {
    source
    .child(name, uri=chart_uri)
    .map(node => {
      let paint = if grid {
        line_fields(node, ["spPr"])
        chart_child(node, "spPr")
      } else {
        node
      }
      let (fill, pen, dash) = line_paint_box(paint)
      guard fill.is_empty() && dash.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Surface axis paint requires support",
        )
      }
      (if grid && pen.0 == "000000" { "868686" } else { pen.0 }, pen.1)
    })
    .unwrap_or(("", 0))
  }
  let text = if source.child("txPr", uri=chart_uri) is Some(text) {
    line_text(text)
  } else {
    fallback.unwrap_or_error(
      @failure.Failure(
        code="unsupported-chart",
        part=source.tree.part,
        offset=-1,
        message="Surface axis text is missing",
      ),
    )
  }
  (
    {
      text: circular_text_style(text),
      pen: pen("spPr", false),
      major: pen("majorGridlines", true),
      minor: ("", 0),
      major_tick: tick,
      minor_tick: "none",
      minimum: None,
      maximum: None,
      title: source
      .child("title", uri=chart_uri)
      .map(title => line_caption(title, edge_layout~)),
    },
    hidden,
    position.node.attribute("val") != Some("none"),
  )
}

///|
fn read_surface_worksheet(
  part : String,
  document : @xml.Document,
) -> WorksheetChart raise @failure.Failure {
  guard document.nodes().length() <= 16384 &&
    document.source().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Surface XML exceeds chart limits")
  }
  let tree = Tree::new(part, document)
  let root : Ref = { tree, node: tree.root("chartSpace", uri=chart_uri), }
  line_fields(root, ["lang", "chart", "spPr", "printSettings"])
  if root.child("lang", uri=chart_uri) is Some(lang) {
    line_fields(lang, [], attributes=["val"])
  }
  if root.child("printSettings", uri=chart_uri) is Some(settings) {
    line_fields(settings, ["headerFooter", "pageMargins", "pageSetup"])
    for name in ["headerFooter", "pageSetup"] {
      if settings.child(name, uri=chart_uri) is Some(node) {
        line_fields(node, [])
      }
    }
    if settings.child("pageMargins", uri=chart_uri) is Some(margins) {
      line_fields(margins, [], attributes=[
        "b", "l", "r", "t", "header", "footer",
      ])
      for attribute in margins.node.attributes {
        ignore(line_real(attribute.value, 0, 100))
      }
    }
  }
  let chart = chart_child(root, "chart")
  line_fields(chart, [
    "view3D", "floor", "sideWall", "backWall", "plotArea", "legend", "plotVisOnly",
    "dispBlanksAs",
  ])
  native_flag(chart_child(chart, "plotVisOnly"), "1")
  native_flag(chart_child(chart, "dispBlanksAs"), "gap")
  let view = chart_child(chart, "view3D")
  line_fields(view, [
    "rotX", "rotY", "hPercent", "depthPercent", "perspective", "rAngAx",
  ])
  guard !view.child("rAngAx", uri=chart_uri).map(line_boolean).unwrap_or(false) else {
    @failure.reject(
      "unsupported-chart", "Right-angle surface projection requires support",
    )
  }
  let setting = fn(
    name : String,
    low : Double,
    high : Double,
  ) raise @failure.Failure {
    view
    .child(name, uri=chart_uri)
    .map(node => {
      line_fields(node, [], attributes=["val"])
      line_real(node.node.attribute("val").unwrap_or(""), low, high)
    })
  }
  let plot = chart_child(chart, "plotArea")
  let plots = tree.children
    .get(plot.node.id)
    .unwrap_or([])
    .filter(node => {
      node.uri == chart_uri &&
      ["surfaceChart", "surface3DChart"].contains(node.name)
    })
  guard plots is [source] else {
    @failure.reject("unsupported-chart", "Expected one surface group")
  }
  let source : Ref = { tree, node: source, }
  line_fields(plot, [
    "layout",
    source.node.name,
    "catAx",
    "valAx",
    "serAx",
    "spPr",
  ])
  line_fields(source, ["wireframe", "ser", "bandFmts", "axId"])
  if source.child("bandFmts", uri=chart_uri) is Some(bands) {
    line_fields(bands, [])
  }
  let wireframe = source
    .child("wireframe", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(false)
  let layout = chart_child(plot, "layout")
  line_fields(layout, ["manualLayout"])
  let manual = layout
    .child("manualLayout", uri=chart_uri)
    .map(manual => {
      line_fields(manual, ["xMode", "yMode", "x", "y", "w", "h"])
      native_flag(chart_child(manual, "xMode"), "edge")
      native_flag(chart_child(manual, "yMode"), "edge")
      let value = fn(name : String) raise @failure.Failure {
        let node = chart_child(manual, name)
        line_fields(node, [], attributes=["val"])
        line_real(node.node.attribute("val").unwrap_or(""), 0, 1)
      }
      let rect : @layout.Border = {
        x: value("x"),
        y: value("y"),
        width: value("w"),
        height: value("h"),
      }
      guard rect.width > 0 &&
        rect.height > 0 &&
        rect.x + rect.width <= 1 &&
        rect.y + rect.height <= 1 else {
        @failure.reject(
          "unsupported-chart", "Surface manual plot exceeds its frame",
        )
      }
      rect
    })
  let category_source = chart_child(plot, "catAx")
  let value_source = chart_child(plot, "valAx")
  let series_source = chart_child(plot, "serAx")
  let id = fn(axis : Ref) raise @failure.Failure {
    chart_child(axis, "axId").node.attribute("val").unwrap_or("")
  }
  let ids = [id(category_source), id(value_source), id(series_source)]
  guard ids[0] != ids[1] &&
    ids[0] != ids[2] &&
    ids[1] != ids[2] &&
    tree
    .all(source.node.id, "axId", uri=chart_uri)
    .map(node => node.attribute("val").unwrap_or("")) ==
    ids &&
    chart_child(category_source, "crossAx").node.attribute("val") ==
    Some(ids[1]) &&
    chart_child(value_source, "crossAx").node.attribute("val") == Some(ids[0]) &&
    chart_child(series_source, "crossAx").node.attribute("val") == Some(ids[1]) else {
    @failure.reject("unsupported-chart", "Unlinked surface axes")
  }
  let (category, _, _) = surface_axis(category_source, true, None)
  let (value, value_hidden, value_labels) = surface_axis(
    value_source,
    false,
    Some(category.text),
  )
  let (series_axis, _, _) = surface_axis(
    series_source,
    true,
    Some(category.text),
    edge_layout=true,
  )
  let seen : Set[Double] = Set([])
  let series = tree.all(source.node.id, "ser", uri=chart_uri)
  guard series.length() >= 2 && series.length() <= 32 else {
    @failure.reject("limit-exceeded", "Surface requires 2-32 series")
  }
  let values : Array[String] = []
  let data_series = series.mapi((index, node) => {
    let item : Ref = { tree, node, }
    line_fields(item, ["idx", "order", "spPr", "val"])
    let idx = chart_child(item, "idx")
    let order = chart_child(item, "order")
    line_fields(idx, [], attributes=["val"])
    line_fields(order, [], attributes=["val"])
    let number = number(idx.node.attribute("val").unwrap_or(""), 0, 4294967295)
    guard number == number.floor() &&
      !seen.contains(number) &&
      order.node.attribute("val") == Some(index.to_string()) else {
      @failure.reject("unsupported-chart", "Invalid surface series order")
    }
    seen.add(number)
    let (_, _, dash) = line_paint_box(chart_child(item, "spPr"))
    guard dash.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Surface series dash requires support",
      )
    }
    let value = chart_child(item, "val")
    line_cache(value, true)
    let reference = chart_child(value, "numRef")
    values.push(chart_child(reference, "f").node.text)
    let cache = chart_child(reference, "numCache")
    @layout.ChartSeries::{
      name: "Series " + (index + 1).to_string(),
      values: chart_points(cache, true).map(text => {
        if text.is_empty() {
          None
        } else {
          Some(line_real(text, -1.0e300, 1.0e300))
        }
      }),
    }
  })
  let count = data_series[0].values.length()
  guard count >= 2 && data_series.all(series => series.values.length() == count) else {
    @failure.reject(
      "unsupported-chart", "Surface caches require a rectangular grid",
    )
  }
  let paint = fn(
    parent : Ref,
    name : String,
    wall : Bool,
  ) raise @failure.Failure {
    let node = chart_child(parent, name)
    let node = if wall {
      line_fields(node, ["spPr"])
      chart_child(node, "spPr")
    } else {
      node
    }
    let (fill, pen, dash) = line_paint_box(node)
    guard dash.is_empty() else {
      @failure.reject("unsupported-chart", "Surface dash requires support")
    }
    (fill, pen)
  }
  let plot_paint = paint(plot, "spPr", false)
  guard plot_paint.0.is_empty() && plot_paint.1.0.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Surface plot plane paint requires support",
    )
  }
  let frame_source = root.child("spPr", uri=chart_uri)
  let frame = frame_source
    .map(node => {
      let (fill, pen, dash) = line_paint_box(node)
      guard dash.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Surface frame dash requires support",
        )
      }
      (fill, pen)
    })
    .unwrap_or(("ffffff", (line_frame_color("000000"), 0.75)))
  let legend = chart
    .child("legend", uri=chart_uri)
    .map(node => native_legend(node))
  let data : @layout.ChartData = {
    kind: "surface",
    title: "",
    label: "",
    hole_size: None,
    legend: if legend is Some(_) {
      "right"
    } else {
      "none"
    },
    categories: Array::makei(count, index => (index + 1).to_string()),
    series: data_series,
  }
  data.validate_sources()
  {
    data,
    categories: "",
    names: Array::make(series.length(), ""),
    values,
    colors: [],
    native_line: None,
    native_radar: None,
    native_area: None,
    native_bubble: None,
    native_circular: None,
    native_bar: None,
    native_surface: Some({
      rotation: (
        setting("rotX", -90, 90).unwrap_or(15),
        setting("rotY", 0, 360).unwrap_or(20),
      ),
      perspective: setting("perspective", 0, 240).unwrap_or(30).max(1),
      height_percent: setting("hPercent", 5, 500).map(value => value / 100),
      depth: setting("depthPercent", 20, 2000).unwrap_or(100) / 100,
      wireframe,
      frame,
      default_fill: frame_source is None,
      default_pen: frame_source.bind(node => node.child("ln")) is None,
      category,
      value,
      series_axis,
      value_hidden,
      value_labels,
      category_between: chart_child(value_source, "crossBetween").node.attribute(
        "val",
      ) ==
      Some("between"),
      plot: manual,
      floor: paint(chart, "floor", true),
      side: paint(chart, "sideWall", true),
      back: paint(chart, "backWall", true),
      legend,
      palette: ["4f81bd", "c0504d", "9bbb59", "8064a2", "4bacc6", "f79646"],
    }),
  }
}
