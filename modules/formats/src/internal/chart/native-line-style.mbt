///|
struct NativeLineTitle {
  text : String
  style : @layout.TextStyle
  rotation : Int32
  angle : Double
  position : (Double, Double)?
}

///|
struct NativeLineAxis {
  text : @layout.TextStyle
  pen : (String, Double)
  major : (String, Double)
  minor : (String, Double)
  major_tick : String
  minor_tick : String
  minimum : Double?
  maximum : Double?
  title : NativeLineTitle?
}

///|
struct NativeLineCurve {
  idx : Int64
  paint : NativeLineSeries
  show_legend_marker : Bool
  plot_markers : Bool
  axis : Int32
  smooth : Bool
  dash : Array[Double]
  labels : NativeLineLabels?
  trend : NativeLineTrend?
  points : Map[Int32, NativeLineSeries]
  column : NativeColumn?
}

///|
fn line_read_marker(
  source : Ref,
  base : NativeLineSeries,
  inherit_outline~ : Bool,
) -> NativeLineSeries raise @failure.Failure {
  line_fields(source, ["symbol", "size", "spPr"])
  let symbol = source
    .child("symbol", uri=chart_uri)
    .map(symbol => {
      line_fields(symbol, [], attributes=["val"])
      let value = symbol.node.attribute("val").unwrap_or("")
      guard [
        "diamond", "square", "circle", "x", "none", "triangle", "star", "plus", "dot",
        "dash",
      ].contains(value) else {
        @failure.reject(
          "unsupported-chart", "Native curve marker requires support",
        )
      }
      value
    })
    .unwrap_or(base.marker)
  let size = source
    .child("size", uri=chart_uri)
    .map(size => {
      line_fields(size, [], attributes=["val"])
      number(size.node.attribute("val").unwrap_or(""), 2, 72) / 2.69 * 72 / 25.4
    })
    .unwrap_or(base.marker_size)
  let (fill, pen, dash) = source
    .child("spPr", uri=chart_uri)
    .map(properties => {
      let explicit = properties.child("ln") is Some(_)
      guard symbol == "none" ||
        explicit ||
        (
          inherit_outline &&
          (
            properties.child("solidFill") is Some(_) ||
            properties.child("noFill") is Some(_)
          )
        ) else {
        @failure.reject("unsupported-chart", "Unresolved native marker outline")
      }
      let (fill, pen, dash) = line_paint_box(properties)
      (fill, if explicit { Some(pen) } else { base.marker_pen }, dash)
    })
    .unwrap_or((base.marker_fill, base.marker_pen, []))
  guard symbol == "none" || (size > 0 && dash.is_empty()) else {
    @failure.reject(
      "unsupported-chart", "Native marker size or dash requires support",
    )
  }
  {
    ..base,
    marker: symbol,
    marker_size: size,
    marker_fill: fill,
    marker_pen: pen,
  }
}

///|
priv struct NativeLineLabels {
  text : @layout.TextStyle
  fill : String
  pen : (String, Double)
  value : Bool
  series : Bool
}

///|
priv struct NativeLineTrend {
  order : Int32
  pen : (String, Double)
  dash : Array[Double]
  text : @layout.TextStyle
  equation : Bool
  r_squared : Bool
}

///|
fn line_boolean(source : Ref) -> Bool raise @failure.Failure {
  line_fields(source, [], attributes=["val"])
  match source.node.attribute("val").unwrap_or("1") {
    "1" | "true" => true
    "0" | "false" => false
    _ => @failure.reject("unsupported-chart", "Invalid native chart boolean")
  }
}

///|
fn line_stroke(
  source : Ref,
  round_join~ : Bool = false,
) -> ((String, Double), Array[Double]) raise @failure.Failure {
  line_fields(
    source,
    ["solidFill", "noFill", "prstDash"] +
    (if round_join { ["round"] } else { [] }),
    attributes=["w"],
    uri=drawing_uri,
  )
  if source.child("round") is Some(join) {
    line_fields(join, [])
  }
  let width = number(source.node.attribute("w").unwrap_or("9525"), 0, 12700000) /
    12700
  let color = if source.child("noFill") is Some(empty) {
    line_fields(empty, [])
    guard source.child("solidFill") is None else {
      @failure.reject("unsupported-chart", "Conflicting native chart pen fills")
    }
    ""
  } else {
    line_color(line_child(source, "solidFill"))
  }
  let dash = source
    .child("prstDash")
    .map(dash => {
      line_fields(dash, [], attributes=["val"])
      // ONLYOFFICE Drawings/Metafile.js DashPatternPresets, in pen widths.
      let pattern : Array[Double] = match
        dash.node.attribute("val").unwrap_or("") {
        "solid" => []
        "dash" => [4, 3]
        "sysDashDotDot" => [3, 1, 1, 1, 1, 1]
        _ =>
          @failure.reject(
            "unsupported-chart", "Native line dash requires support",
          )
      }
      pattern.map(value => value * width)
    })
    .unwrap_or([])
  ((color, width), dash)
}

///|
fn line_paint_box(
  source : Ref,
  round_join~ : Bool = false,
) -> (String, (String, Double), Array[Double]) raise @failure.Failure {
  line_fields(
    source,
    ["solidFill", "noFill", "ln", "effectLst"],
    uri=drawing_uri,
  )
  let fill = if source.child("noFill") is Some(empty) {
    line_fields(empty, [])
    guard source.child("solidFill") is None else {
      @failure.reject("unsupported-chart", "Conflicting native chart fills")
    }
    ""
  } else {
    source.child("solidFill").map(line_color).unwrap_or("")
  }
  let (pen, dash) = source
    .child("ln")
    .map(line => line_stroke(line, round_join~))
    .unwrap_or((("", 0), []))
  native_shadow(source)
  (fill, pen, dash)
}

///|
fn line_caption(
  source : Ref,
  edge_layout~ : Bool = false,
) -> NativeLineTitle raise @failure.Failure {
  let (text, style) = native_title(
    source,
    true,
    free_rotation=true,
    manual_layout=edge_layout,
  )
  let body = line_child(
    chart_child(chart_child(source, "tx"), "rich"),
    "bodyPr",
  )
  let rotation = line_real(
    body.node.attribute("rot").unwrap_or("0"),
    -21600000,
    21600000,
  )
  let position = chart_child(source, "layout")
    .child("manualLayout", uri=chart_uri)
    .map(manual => {
      line_fields(manual, ["xMode", "yMode", "x", "y"])
      native_flag(chart_child(manual, "xMode"), "edge")
      native_flag(chart_child(manual, "yMode"), "edge")
      guard rotation == 0 else {
        @failure.reject(
          "unsupported-chart", "Manual native chart title must be horizontal",
        )
      }
      let coordinate = fn(name : String) raise @failure.Failure {
        let node = chart_child(manual, name)
        line_fields(node, [], attributes=["val"])
        line_real(node.node.attribute("val").unwrap_or(""), 0, 1)
      }
      (coordinate("x"), coordinate("y"))
    })
  // Native text turns only at quarter turns; its text box still measures the original angle.
  {
    text,
    style: circular_text_style(style),
    position,
    angle: rotation / 60000 * @math.PI / 180,
    rotation: if (rotation + 5400000).abs() <= 1000 {
      -1
    } else if (rotation - 5400000).abs() <= 1000 {
      1
    } else {
      0
    },
  }
}

///|
fn line_read_axis(
  axis : Ref,
  category : Bool,
  secondary : Bool,
  scatter~ : Bool = false,
) -> NativeLineAxis raise @failure.Failure {
  line_fields(axis, [
    "axId", "scaling", "delete", "axPos", "majorGridlines", "minorGridlines", "title",
    "numFmt", "majorTickMark", "minorTickMark", "tickLblPos", "spPr", "txPr", "crossAx",
    "crosses", "lblAlgn", "lblOffset", "crossBetween",
  ])
  for name in ["axId", "crossAx"] {
    let id = chart_child(axis, name)
    line_fields(id, [], attributes=["val"])
    let value = number(id.node.attribute("val").unwrap_or(""), 1, 4294967295)
    guard value == value.floor() else {
      @failure.reject("unsupported-chart", "Invalid native axis id")
    }
  }
  let hidden = axis
    .child("delete", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(false)
  guard hidden == (category && secondary) else {
    @failure.reject(
      "unsupported-chart", "Native line axis visibility requires support",
    )
  }
  let scaling = chart_child(axis, "scaling")
  line_fields(
    scaling,
    if category && !scatter {
      ["orientation"]
    } else {
      ["orientation", "min", "max"]
    },
  )
  native_flag(chart_child(scaling, "orientation"), "minMax")
  let bound = fn(name : String) raise @failure.Failure {
    scaling
    .child(name, uri=chart_uri)
    .map(value => {
      line_fields(value, [], attributes=["val"])
      line_real(value.node.attribute("val").unwrap_or(""), -1.0e100, 1.0e100)
    })
  }
  let minimum = bound("min")
  let maximum = bound("max")
  guard !(minimum is Some(low) && maximum is Some(high) && low >= high) else {
    @failure.reject("unsupported-chart", "Invalid native line axis range")
  }
  native_flag(
    chart_child(axis, "axPos"),
    if category {
      "b"
    } else if secondary {
      "r"
    } else {
      "l"
    },
  )
  native_flag(chart_child(axis, "tickLblPos"), "nextTo")
  native_flag(
    chart_child(axis, "crosses"),
    if !category && secondary {
      "max"
    } else {
      "autoZero"
    },
  )
  let format = chart_child(axis, "numFmt")
  line_fields(format, [], attributes=["formatCode", "sourceLinked"])
  guard format.node.attribute("formatCode") == Some("General") &&
    [None, Some("1"), Some("true")].contains(
      format.node.attribute("sourceLinked"),
    ) else {
    @failure.reject(
      "unsupported-chart", "Native axis number format requires support",
    )
  }
  if category && !scatter {
    native_flag(chart_child(axis, "lblAlgn"), "ctr")
    native_flag(chart_child(axis, "lblOffset"), "100")
    guard axis.child("crossBetween", uri=chart_uri) is None else {
      @failure.reject("unsupported-chart", "Invalid category axis crossing")
    }
  } else {
    native_flag(
      chart_child(axis, "crossBetween"),
      if scatter {
        "midCat"
      } else {
        "between"
      },
    )
    guard axis.child("lblAlgn", uri=chart_uri) is None &&
      axis.child("lblOffset", uri=chart_uri) is None else {
      @failure.reject("unsupported-chart", "Invalid value axis label setting")
    }
  }
  let tick = fn(name : String, fallback : String) raise @failure.Failure {
    axis
    .child(name, uri=chart_uri)
    .map(node => {
      line_fields(node, [], attributes=["val"])
      let value = node.node.attribute("val").unwrap_or("")
      guard ["none", "in", "out", "cross"].contains(value) else {
        @failure.reject("unsupported-chart", "Invalid native chart tick")
      }
      value
    })
    .unwrap_or(fallback)
  }
  let pen = axis
    .child("spPr", uri=chart_uri)
    .map(box => {
      let (fill, pen, dash) = line_paint_box(box)
      guard fill.is_empty() && dash.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Native axis paint requires support",
        )
      }
      pen
    })
    .unwrap_or(("", 0))
  let grid = fn(name : String) raise @failure.Failure {
    axis
    .child(name, uri=chart_uri)
    .map(grid => {
      line_fields(grid, ["spPr"])
      let (fill, pen, dash) = line_paint_box(chart_child(grid, "spPr"))
      guard fill.is_empty() && dash.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Native grid paint requires support",
        )
      }
      pen
    })
    .unwrap_or(("", 0))
  }
  let text = axis.child("txPr", uri=chart_uri).map(line_text)
  guard hidden ||
    (text is Some(_) && axis.child("spPr", uri=chart_uri) is Some(_)) else {
    @failure.reject("unsupported-chart", "Missing native line axis style")
  }
  {
    text: circular_text_style(
      text.unwrap_or(@layout.TextStyle::new("Arial", 10, "000000")),
    ),
    pen,
    major: grid("majorGridlines"),
    minor: grid("minorGridlines"),
    major_tick: tick("majorTickMark", "out"),
    minor_tick: tick("minorTickMark", "none"),
    minimum,
    maximum,
    title: axis.child("title", uri=chart_uri).map(title => line_caption(title)),
  }
}
