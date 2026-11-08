///|
struct NativeRadarSeries {
  idx : Int64
  line : NativeLineSeries
  fill : String
  dash : Array[Double]
  join : Int32
}

///|
pub struct NativeRadar {
  frame_fill : String
  frame_pen : (String, Double)
  frame_join : Int32
  frame_default_fill : Bool
  frame_default_pen : Bool
  series : Array[NativeRadarSeries]
  filled : Bool
  plot : @layout.Border?
  grid_pen : (String, Double)
  grid_join : Int32
  reversed : Bool
}

///|
fn radar_axis(
  axis : Ref,
  category : Bool,
) -> ((String, Double), Int32) raise @failure.Failure {
  line_fields(axis, [
    "axId", "scaling", "delete", "axPos", "numFmt", "tickLblPos", "crossAx", "crosses",
    "lblAlgn", "lblOffset", "crossBetween", "majorGridlines", "minorGridlines", "majorTickMark",
    "minorTickMark", "spPr", "txPr", "auto", "noMultiLvlLbl",
  ])
  for name in ["axId", "crossAx"] {
    let node = chart_child(axis, name)
    line_fields(node, [], attributes=["val"])
    ignore(number(node.node.attribute("val").unwrap_or(""), 1, 4294967295))
  }
  let scaling = chart_child(axis, "scaling")
  line_fields(scaling, ["orientation"])
  let orientation = chart_child(scaling, "orientation")
  line_fields(orientation, [], attributes=["val"])
  guard orientation.node.attribute("val") == Some("minMax") ||
    (category && orientation.node.attribute("val") == Some("maxMin")) else {
    @failure.reject("unsupported-chart", "Unsupported radar axis orientation")
  }
  native_flag(chart_child(axis, "delete"), "1")
  // Tick and text formatting on these deleted axes cannot paint.
  for name in ["majorTickMark", "minorTickMark"] {
    if axis.child(name, uri=chart_uri) is Some(tick) {
      line_fields(tick, [], attributes=["val"])
      guard [Some("cross"), Some("none"), Some("in"), Some("out")].contains(
        tick.node.attribute("val"),
      ) else {
        @failure.reject("unsupported-chart", "Invalid native radar tick mark")
      }
    }
  }
  for name in ["auto", "noMultiLvlLbl"] {
    if axis.child(name, uri=chart_uri) is Some(flag) {
      ignore(line_boolean(flag))
    }
  }
  native_flag(chart_child(axis, "axPos"), if category { "b" } else { "l" })
  native_flag(chart_child(axis, "tickLblPos"), "nextTo")
  if axis.child("crosses", uri=chart_uri) is Some(crosses) {
    native_flag(crosses, "autoZero")
  }
  let format = chart_child(axis, "numFmt")
  line_fields(format, [], attributes=["formatCode", "sourceLinked"])
  guard format.node.attribute("formatCode") == Some("General") &&
    [None, Some("1"), Some("true")].contains(
      format.node.attribute("sourceLinked"),
    ) else {
    @failure.reject(
      "unsupported-chart", "Native radar axis format requires support",
    )
  }
  if category {
    native_flag(chart_child(axis, "lblAlgn"), "ctr")
    native_flag(chart_child(axis, "lblOffset"), "100")
    guard axis.child("majorGridlines", uri=chart_uri) is None &&
      axis.child("minorGridlines", uri=chart_uri) is None &&
      axis.child("crossBetween", uri=chart_uri) is None else {
      @failure.reject(
        "unsupported-chart", "Native radar spokes require support",
      )
    }
  } else {
    let between = chart_child(axis, "crossBetween")
    line_fields(between, [], attributes=["val"])
    guard [Some("between"), Some("midCat")].contains(
      between.node.attribute("val"),
    ) else {
      @failure.reject("unsupported-chart", "Unsupported radar axis crossing")
    }
    guard axis.child("lblAlgn", uri=chart_uri) is None &&
      axis.child("lblOffset", uri=chart_uri) is None else {
      @failure.reject("unsupported-chart", "Unknown radar value axis setting")
    }
  }
  let mut major = (("", 0.0), 0)
  for name in ["majorGridlines", "minorGridlines"] {
    if axis.child(name, uri=chart_uri) is Some(grid) {
      line_fields(grid, ["spPr"])
      let paint = chart_child(grid, "spPr")
      let (fill, pen) = line_box(paint, round_join=true)
      guard fill.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Native radar grid fill requires support",
        )
      }
      if name == "majorGridlines" {
        // ONLYOFFICE calcGridLine replaces pure black with its chart grid gray.
        let color = if pen.0 == "000000" { "868686" } else { pen.0 }
        let join = if paint.child("ln").bind(line => line.child("round"))
          is Some(_) {
          1
        } else {
          0
        }
        major = ((color, pen.1), join)
      }
    }
  }
  major
}

///|
fn radar_marker(
  source : Ref,
) -> (String, Double, String, (String, Double)?) raise @failure.Failure {
  line_fields(source, ["symbol", "size", "spPr"])
  let symbol = chart_child(source, "symbol")
  line_fields(symbol, [], attributes=["val"])
  let symbol = symbol.node.attribute("val").unwrap_or("")
  guard ["square", "circle", "diamond", "none"].contains(symbol) else {
    @failure.reject("unsupported-chart", "Native radar marker requires support")
  }
  let size = chart_child(source, "size")
  line_fields(size, [], attributes=["val"])
  let size = number(size.node.attribute("val").unwrap_or(""), 2, 72) /
    2.69 *
    72 /
    25.4
  let properties = chart_child(source, "spPr")
  line_fields(properties, ["solidFill", "ln", "effectLst"], uri=drawing_uri)
  let fill = line_color(line_child(properties, "solidFill"))
  let pen = properties.child("ln").map(line => line_pen(line))
  native_shadow(properties)
  (symbol, size, fill, pen)
}

///|
fn read_native_radar(root : Ref) -> NativeRadar raise @failure.Failure {
  line_fields(root, ["lang", "chart", "printSettings", "roundedCorners", "spPr"])
  if root.child("roundedCorners", uri=chart_uri) is Some(rounded) {
    guard !line_boolean(rounded) else {
      @failure.reject(
        "unsupported-chart", "Rounded radar frames require support",
      )
    }
  }
  if root.child("lang", uri=chart_uri) is Some(language) {
    line_fields(language, [], attributes=["val"])
  }
  if root.child("printSettings", uri=chart_uri) is Some(settings) {
    line_fields(settings, ["headerFooter", "pageMargins", "pageSetup"])
    line_fields(chart_child(settings, "headerFooter"), [])
    line_fields(chart_child(settings, "pageSetup"), [])
    let margins = chart_child(settings, "pageMargins")
    line_fields(margins, [], attributes=["b", "l", "r", "t", "header", "footer"])
    for value in margins.node.attributes {
      ignore(line_real(value.value, 0, 100))
    }
  }
  let chart = chart_child(root, "chart")
  line_fields(chart, [
    "plotArea", "plotVisOnly", "dispBlanksAs", "autoTitleDeleted",
  ])
  if chart.child("autoTitleDeleted", uri=chart_uri) is Some(deleted) {
    guard line_boolean(deleted) else {
      @failure.reject(
        "unsupported-chart", "Automatic radar titles require support",
      )
    }
  }
  native_flag(chart_child(chart, "plotVisOnly"), "1")
  native_flag(chart_child(chart, "dispBlanksAs"), "gap")
  let plot = chart_child(chart, "plotArea")
  line_fields(plot, ["layout", "radarChart", "catAx", "valAx", "spPr"])
  native_no_paint(chart_child(plot, "spPr"))
  let position = plot
    .child("layout", uri=chart_uri)
    .bind(layout => {
      line_fields(layout, ["manualLayout"])
      layout.child("manualLayout", uri=chart_uri)
    })
    .map(manual => {
      line_fields(manual, ["xMode", "yMode", "x", "y", "w", "h"])
      native_flag(chart_child(manual, "xMode"), "edge")
      native_flag(chart_child(manual, "yMode"), "edge")
      let values = ["x", "y", "w", "h"].map(name => {
        let value = chart_child(manual, name)
        line_fields(value, [], attributes=["val"])
        line_real(value.node.attribute("val").unwrap_or(""), 0, 1)
      })
      guard values[2] > 0 &&
        values[3] > 0 &&
        values[0] + values[2] <= 1 &&
        values[1] + values[3] <= 1 else {
        @failure.reject(
          "unsupported-chart", "Native radar plot exceeds its frame",
        )
      }
      @layout.Border::{
        x: values[0],
        y: values[1],
        width: values[2],
        height: values[3],
      }
    })
  let radar = chart_child(plot, "radarChart")
  line_fields(radar, ["radarStyle", "ser", "axId", "varyColors"])
  if radar.child("varyColors", uri=chart_uri) is Some(vary) {
    guard !line_boolean(vary) else {
      @failure.reject(
        "unsupported-chart", "Native radar point colors require support",
      )
    }
  }
  let style = chart_child(radar, "radarStyle")
  line_fields(style, [], attributes=["val"])
  let style = style.node.attribute("val").unwrap_or("")
  guard ["standard", "marker", "filled"].contains(style) else {
    @failure.reject("unsupported-chart", "Unknown native radar style")
  }
  let category_axis = chart_child(plot, "catAx")
  let value_axis = chart_child(plot, "valAx")
  let category_id = chart_child(category_axis, "axId").node.attribute("val")
  let value_id = chart_child(value_axis, "axId").node.attribute("val")
  guard category_id != value_id &&
    chart_child(category_axis, "crossAx").node.attribute("val") == value_id &&
    chart_child(value_axis, "crossAx").node.attribute("val") == category_id &&
    radar.tree
    .all(radar.node.id, "axId", uri=chart_uri)
    .map(n => n.attribute("val")) ==
    [category_id, value_id] else {
    @failure.reject(
      "unsupported-chart", "Native radar requires a single linked axis pair",
    )
  }
  for node in radar.tree.all(radar.node.id, "axId", uri=chart_uri) {
    line_fields({ tree: radar.tree, node, }, [], attributes=["val"])
  }
  ignore(radar_axis(category_axis, true))
  let (grid_pen, grid_join) = radar_axis(value_axis, false)
  let sources = radar.tree.all(radar.node.id, "ser", uri=chart_uri)
  let identities : Map[String, Unit] = Map([])
  let orders : Map[String, Unit] = Map([])
  let series = sources.map(node => {
    let source : Ref = { tree: radar.tree, node, }
    line_fields(source, [
      "idx", "order", "tx", "spPr", "marker", "cat", "val", "dLbls",
    ])
    if source.child("dLbls", uri=chart_uri) is Some(labels) {
      native_inactive_labels(labels)
    }
    for name in ["idx", "order"] {
      line_fields(chart_child(source, name), [], attributes=["val"])
    }
    let idx = number(
      chart_child(source, "idx").node.attribute("val").unwrap_or(""),
      0,
      4294967295,
    )
    guard idx == idx.floor() else {
      @failure.reject(
        "unsupported-chart", "Invalid native radar series identity",
      )
    }
    let identity = idx.to_string()
    let order = number(
      chart_child(source, "order").node.attribute("val").unwrap_or(""),
      0,
      31,
    ).to_string()
    guard !identities.contains(identity) && !orders.contains(order) else {
      @failure.reject(
        "unsupported-chart", "Duplicate native radar series identity or order",
      )
    }
    identities[identity] = ()
    orders[order] = ()
    if source.child("tx", uri=chart_uri) is Some(title) {
      line_cache(title, false)
    }
    let categories = chart_child(source, "cat")
    line_cache(categories, categories.child("numRef", uri=chart_uri) is Some(_))
    line_cache(chart_child(source, "val"), true)
    let properties = chart_child(source, "spPr")
    line_fields(properties, ["solidFill", "ln"], uri=drawing_uri)
    let fill = properties.child("solidFill").map(line_color).unwrap_or("")
    guard (if style == "filled" { !fill.is_empty() } else { fill.is_empty() }) else {
      @failure.reject(
        "unsupported-chart", "Native radar line fill requires support",
      )
    }
    let pen = line_child(properties, "ln")
    line_fields(
      pen,
      ["solidFill", "prstDash", "round"],
      attributes=["w"],
      uri=drawing_uri,
    )
    let width = number(pen.node.attribute("w").unwrap_or("9525"), 0, 12700000) /
      12700
    let color = line_color(line_child(pen, "solidFill"))
    let join = if pen.child("round") is Some(round) {
      line_fields(round, [])
      1
    } else {
      0
    }
    let dash = pen
      .child("prstDash")
      .map(dash => {
        line_fields(dash, [], attributes=["val"])
        match dash.node.attribute("val") {
          Some("solid") => []
          Some("sysDash") => [3.0 * width, width]
          _ =>
            @failure.reject(
              "unsupported-chart", "Native radar dash requires support",
            )
        }
      })
      .unwrap_or([])
    guard style != "marker" || source.child("marker", uri=chart_uri) is Some(_) else {
      @failure.reject(
        "unsupported-chart", "Automatic native radar markers require support",
      )
    }
    let (marker, marker_size, marker_fill, marker_stroke) = source
      .child("marker", uri=chart_uri)
      .map(radar_marker)
      .unwrap_or(("none", 0, "", Some(("", 0))))
    guard style != "filled" || marker == "none" else {
      @failure.reject(
        "unsupported-chart", "Filled radar markers require support",
      )
    }
    NativeRadarSeries::{
      idx: idx.to_int64(),
      line: {
        color,
        width,
        marker,
        marker_size,
        marker_fill,
        marker_pen: marker_stroke,
      },
      fill,
      dash,
      join,
    }
  })
  let first : Ref = { tree: radar.tree, node: sources[0], }
  let common = chart_categories(first, false)
  guard sources.all(node => {
    chart_categories({ tree: radar.tree, node, }, false) == common
  }) else {
    @failure.reject(
      "unsupported-chart", "Native radar category caches must agree",
    )
  }
  let frame = root.child("spPr", uri=chart_uri)
  let (frame_fill, frame_pen) = frame
    .map(paint => line_box(paint, round_join=true))
    .unwrap_or(("", (line_frame_color("000000"), 0.75)))
  {
    frame_fill: if frame_fill.is_empty() {
      "ffffff"
    } else {
      frame_fill
    },
    frame_pen,
    frame_default_fill: frame.bind(paint => paint.child("solidFill")) is None,
    frame_default_pen: frame.bind(paint => paint.child("ln")) is None,
    frame_join: if frame
      .bind(paint => paint.child("ln"))
      .bind(pen => pen.child("round"))
      is Some(_) {
      1
    } else {
      0
    },
    series,
    filled: style == "filled",
    plot: position,
    grid_pen,
    grid_join,
    reversed: chart_child(chart_child(category_axis, "scaling"), "orientation").node.attribute(
      "val",
    ) ==
    Some("maxMin"),
  }
}

///|
fn native_shadow(properties : Ref) -> Unit raise @failure.Failure {
  if properties.child("effectLst") is Some(effects) {
    line_fields(effects, ["outerShdw"], uri=drawing_uri)
    if effects.child("outerShdw") is Some(shadow) {
      // Native chart marker painting ignores the retained DrawingML shadow.
      line_fields(
        shadow,
        ["srgbClr"],
        attributes=["dist", "dir", "algn"],
        uri=drawing_uri,
      )
      ignore(
        number(shadow.node.attribute("dist").unwrap_or("0"), 0, 2147483647),
      )
      ignore(number(shadow.node.attribute("dir").unwrap_or("0"), 0, 21599999))
      guard shadow.node.attribute("algn").unwrap_or("b") == "br" else {
        @failure.reject(
          "unsupported-chart", "Native radar marker shadow requires support",
        )
      }
      let color = line_child(shadow, "srgbClr")
      line_fields(color, [], attributes=["val"])
      guard worksheet_color_valid(color.node.attribute("val").unwrap_or("")) else {
        @failure.reject(
          "unsupported-chart", "Invalid radar marker shadow color",
        )
      }
    }
  }
}
