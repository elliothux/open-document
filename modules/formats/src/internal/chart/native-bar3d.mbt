///|
pub struct NativeBar3d {
  horizontal : Bool
  rotation : (Double, Double)
  perspective : Double
  depth : Double
  frame : (String, (String, Double))
  default_fill : Bool
  default_pen : Bool
  series : Array[(String, (String, Double))]
  category : NativeLineAxis
  value : NativeLineAxis
  series_axis : NativeLineAxis?
  floor : (String, (String, Double))
  side : (String, (String, Double))
  back : (String, (String, Double))
  legend : NativeLegend?
}

///|
fn bar3d_axis(
  source : Ref,
  position : String,
  category : Bool,
  series : Bool,
) -> NativeLineAxis raise @failure.Failure {
  line_fields(source, [
    "axId", "scaling", "axPos", "title", "numFmt", "majorGridlines", "minorGridlines",
    "majorTickMark", "minorTickMark", "tickLblPos", "spPr", "txPr", "crossAx", "crosses",
    "lblAlgn", "lblOffset", "crossBetween",
  ])
  native_flag(chart_child(source, "axPos"), position)
  native_flag(chart_child(source, "crosses"), "autoZero")
  native_flag(
    chart_child(source, "tickLblPos"),
    if category || series {
      "low"
    } else {
      "nextTo"
    },
  )
  let scaling = chart_child(source, "scaling")
  line_fields(scaling, ["orientation"])
  native_flag(chart_child(scaling, "orientation"), "minMax")
  for name in ["axId", "crossAx"] {
    let id = chart_child(source, name)
    line_fields(id, [], attributes=["val"])
    let value = number(id.node.attribute("val").unwrap_or(""), 1, 4294967295)
    guard value == value.floor() else {
      @failure.reject("unsupported-chart", "Invalid three-dimensional axis id")
    }
  }
  if source.child("numFmt", uri=chart_uri) is Some(format) {
    line_fields(format, [], attributes=["formatCode", "sourceLinked"])
    guard format.node.attribute("formatCode") == Some("General") &&
      [None, Some("1"), Some("true")].contains(
        format.node.attribute("sourceLinked"),
      ) else {
      @failure.reject(
        "unsupported-chart", "Three-dimensional axis number format requires support",
      )
    }
  }
  if category {
    native_flag(chart_child(source, "lblAlgn"), "ctr")
    native_flag(chart_child(source, "lblOffset"), "100")
  } else if !series {
    native_flag(chart_child(source, "crossBetween"), "between")
  }
  let text = chart_child(source, "txPr")
  line_fields(text, ["bodyPr", "lstStyle", "p"], uri=drawing_uri)
  let body = line_child(text, "bodyPr")
  line_fields(body, [], attributes=["rot", "vert"])
  guard body.node.attribute("rot").unwrap_or("0") == "0" &&
    (
      body.node.attribute("vert").unwrap_or("horz") == "horz" ||
      (series && body.node.attribute("vert") == Some("vert270"))
    ) else {
    @failure.reject(
      "unsupported-chart", "Three-dimensional axis text direction requires support",
    )
  }
  line_fields(line_child(text, "lstStyle"), [])
  let paragraph = line_child(text, "p")
  line_fields(paragraph, ["pPr", "endParaRPr"], uri=drawing_uri)
  if paragraph.child("endParaRPr") is Some(end) {
    line_fields(end, [], attributes=["lang"])
  }
  let properties = line_child(paragraph, "pPr")
  line_fields(properties, ["defRPr"], uri=drawing_uri)
  let pen = fn(name : String, grid : Bool) raise @failure.Failure {
    source
    .child(name, uri=chart_uri)
    .map(node => {
      let node = if grid {
        line_fields(node, ["spPr"])
        chart_child(node, "spPr")
      } else {
        node
      }
      let (fill, pen, dash) = line_paint_box(node)
      guard fill.is_empty() && dash.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Three-dimensional axis paint requires support",
        )
      }
      pen
    })
    .unwrap_or(("", 0))
  }
  let tick = fn(name : String) raise @failure.Failure {
    source
    .child(name, uri=chart_uri)
    .map(node => {
      line_fields(node, [], attributes=["val"])
      let value = node.node.attribute("val").unwrap_or("out")
      guard ["none", "out"].contains(value) else {
        @failure.reject(
          "unsupported-chart", "Three-dimensional tick direction requires support",
        )
      }
      value
    })
    .unwrap_or(if name == "majorTickMark" { "out" } else { "none" })
  }
  guard pen("majorGridlines", true).0.is_empty() &&
    pen("minorGridlines", true).0.is_empty() &&
    tick("minorTickMark") == "none" else {
    @failure.reject(
      "unsupported-chart", "Three-dimensional grid and minor ticks require support",
    )
  }
  {
    text: circular_text_style(line_text_style(line_child(properties, "defRPr"))),
    pen: pen("spPr", false),
    major: pen("majorGridlines", true),
    minor: pen("minorGridlines", true),
    major_tick: tick("majorTickMark"),
    minor_tick: tick("minorTickMark"),
    minimum: None,
    maximum: None,
    title: source
    .child("title", uri=chart_uri)
    .map(title => line_caption(title, edge_layout=series)),
  }
}

///|
fn read_native_bar3d(root : Ref) -> NativeBar3d raise @failure.Failure {
  line_fields(root, ["lang", "chart", "spPr", "printSettings"])
  if root.child("lang", uri=chart_uri) is Some(lang) {
    line_fields(lang, [], attributes=["val"])
  }
  if root.child("printSettings", uri=chart_uri) is Some(settings) {
    line_fields(settings, ["headerFooter", "pageMargins", "pageSetup"])
    line_fields(chart_child(settings, "headerFooter"), [])
    line_fields(chart_child(settings, "pageSetup"), [])
    let margins = chart_child(settings, "pageMargins")
    line_fields(margins, [], attributes=["b", "l", "r", "t", "header", "footer"])
    for attribute in margins.node.attributes {
      ignore(line_real(attribute.value, 0, 100))
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
  line_fields(view, ["rotX", "rotY", "depthPercent", "rAngAx", "perspective"])
  let setting = fn(
    name : String,
    fallback : Double,
    lo : Double,
    hi : Double,
  ) raise @failure.Failure {
    view
    .child(name, uri=chart_uri)
    .map(value => {
      line_fields(value, [], attributes=["val"])
      line_real(value.node.attribute("val").unwrap_or(""), lo, hi)
    })
    .unwrap_or(fallback)
  }
  let rotation = (setting("rotX", 0, -90, 90), setting("rotY", 0, 0, 360))
  let right_angle = view
    .child("rAngAx", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(false)
  guard !right_angle || rotation == (0, 0) else {
    @failure.reject(
      "unsupported-chart", "Rotated right-angle bar projection requires support",
    )
  }
  let plot = chart_child(chart, "plotArea")
  line_fields(plot, ["layout", "bar3DChart", "catAx", "valAx", "serAx", "spPr"])
  line_fields(chart_child(plot, "layout"), [])
  let bars = chart_child(plot, "bar3DChart")
  line_fields(bars, ["barDir", "grouping", "ser", "shape", "axId"])
  let horizontal = chart_child(bars, "barDir").node.attribute("val") ==
    Some("bar")
  native_flag(
    chart_child(bars, "barDir"),
    if horizontal {
      "bar"
    } else {
      "col"
    },
  )
  native_flag(
    chart_child(bars, "grouping"),
    if horizontal {
      "stacked"
    } else {
      "standard"
    },
  )
  native_flag(chart_child(bars, "shape"), "box")
  guard !horizontal || right_angle else {
    @failure.reject(
      "unsupported-chart", "Perspective stacked bars require support",
    )
  }
  let categories = chart_child(plot, "catAx")
  let values = chart_child(plot, "valAx")
  let series_axis = plot.child("serAx", uri=chart_uri)
  let id = fn(axis : Ref) raise @failure.Failure {
    chart_child(axis, "axId").node.attribute("val").unwrap_or("")
  }
  let linked = plot.tree
    .all(bars.node.id, "axId", uri=chart_uri)
    .map(node => node.attribute("val").unwrap_or(""))
  guard linked ==
    [id(categories), id(values), series_axis.map(id).unwrap_or("0")] &&
    id(categories) != id(values) &&
    chart_child(categories, "crossAx").node.attribute("val") == Some(id(values)) &&
    chart_child(values, "crossAx").node.attribute("val") == Some(id(categories)) &&
    (if series_axis is Some(axis) {
      id(axis) != id(categories) &&
      id(axis) != id(values) &&
      chart_child(axis, "crossAx").node.attribute("val") == Some(id(values))
    } else {
      horizontal
    }) else {
    @failure.reject("unsupported-chart", "Unlinked three-dimensional bar axes")
  }
  let series = plot.tree.all(bars.node.id, "ser", uri=chart_uri)
  let seen : Set[Double] = Set([])
  let paints = series.mapi((index, node) => {
    let source : Ref = { tree: plot.tree, node, }
    line_fields(source, ["idx", "order", "tx", "spPr", "cat", "val"])
    let idx = chart_child(source, "idx")
    let order = chart_child(source, "order")
    line_fields(idx, [], attributes=["val"])
    line_fields(order, [], attributes=["val"])
    let idx = number(idx.node.attribute("val").unwrap_or(""), 0, 4294967295)
    guard idx == idx.floor() &&
      !seen.contains(idx) &&
      order.node.attribute("val") == Some(index.to_string()) else {
      @failure.reject(
        "unsupported-chart", "Invalid three-dimensional series order",
      )
    }
    seen.add(idx)
    if source.child("tx", uri=chart_uri) is Some(title) {
      line_cache(title, false)
    }
    let cat = chart_child(source, "cat")
    line_cache(cat, cat.child("numRef", uri=chart_uri) is Some(_))
    line_cache(chart_child(source, "val"), true)
    guard chart_categories(source, false) ==
      chart_categories({ tree: plot.tree, node: series[0], }, false) else {
      @failure.reject(
        "unsupported-chart", "Three-dimensional category caches must agree",
      )
    }
    let (fill, pen, dash) = line_paint_box(chart_child(source, "spPr"))
    guard dash.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Three-dimensional bar dash requires support",
      )
    }
    (fill, pen)
  })
  let surface = fn(parent : Ref, name : String) raise @failure.Failure {
    let node = chart_child(parent, name)
    line_fields(node, ["spPr"])
    let (fill, pen, dash) = line_paint_box(chart_child(node, "spPr"))
    guard dash.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Three-dimensional surface dash requires support",
      )
    }
    (fill, pen)
  }
  let (fill, pen, dash) = line_paint_box(chart_child(plot, "spPr"))
  guard fill.is_empty() && pen.0.is_empty() && dash.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Three-dimensional plot plane requires support",
    )
  }
  let frame = root.child("spPr", uri=chart_uri)
  let (fill, pen, dash) = frame
    .map(paint => line_paint_box(paint))
    .unwrap_or(("ffffff", ("", 0), []))
  guard dash.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Three-dimensional frame dash requires support",
    )
  }
  let default_pen = frame.bind(frame => frame.child("ln")) is None
  {
    horizontal,
    rotation,
    perspective: if right_angle {
      0
    } else {
      setting("perspective", 30, 1, 240)
    },
    depth: setting("depthPercent", 100, 1, 2000) / 100,
    frame: (
      fill,
      if default_pen {
        (line_frame_color("000000"), 0.75)
      } else {
        pen
      },
    ),
    default_fill: frame is None,
    default_pen,
    series: paints,
    category: bar3d_axis(
      categories,
      if horizontal {
        "l"
      } else {
        "b"
      },
      true,
      false,
    ),
    value: bar3d_axis(values, if horizontal { "b" } else { "l" }, false, false),
    series_axis: series_axis.map(axis => bar3d_axis(axis, "b", false, true)),
    floor: surface(chart, "floor"),
    side: surface(chart, "sideWall"),
    back: surface(chart, "backWall"),
    legend: chart
    .child("legend", uri=chart_uri)
    .map(legend => native_legend(legend)),
  }
}
