///|
struct NativeAreaSeries {
  fill : String
  pen : (String, Double)
}

///|
pub struct NativeArea {
  frame_fill : String
  frame_pen : (String, Double)
  frame_default_fill : Bool
  frame_default_pen : Bool
  series : Array[NativeAreaSeries]
  category_text : @layout.TextStyle
  value_text : @layout.TextStyle
  category_title : (String, @layout.TextStyle)
  value_title : (String, @layout.TextStyle)
  category_pen : (String, Double)
  value_pen : (String, Double)
  grid_pen : (String, Double)
  plot_fill : String
  plot_pen : (String, Double)
  flat_plot : @layout.Border?
  category_grid : (String, Double)
  floor_pen : (String, Double)
  category_tick : String
  category_minor_tick : String
  value_tick : String
  value_minor_tick : String
}

///|
fn native_title(
  source : Ref,
  category : Bool,
  free_rotation~ : Bool = false,
  manual_layout~ : Bool = false,
) -> (String, @layout.TextStyle) raise @failure.Failure {
  line_fields(source, ["tx", "layout", "overlay", "spPr"])
  if source.child("layout", uri=chart_uri) is Some(layout) {
    line_fields(layout, if manual_layout { ["manualLayout"] } else { [] })
  }
  if source.child("overlay", uri=chart_uri) is Some(overlay) {
    native_flag(overlay, "0")
  }
  if source.child("spPr", uri=chart_uri) is Some(paint) {
    native_no_paint(paint)
  }
  let text = chart_child(source, "tx")
  line_fields(text, ["rich"])
  let rich = chart_child(text, "rich")
  line_fields(rich, ["bodyPr", "lstStyle", "p"], uri=drawing_uri)
  let body = line_child(rich, "bodyPr")
  line_fields(body, [], attributes=["rot"])
  if free_rotation {
    ignore(
      line_real(body.node.attribute("rot").unwrap_or("0"), -21600000, 21600000),
    )
  }
  guard free_rotation ||
    body.node.attribute("rot").unwrap_or("0") ==
    (if category { "0" } else { "-5400000" }) else {
    @failure.reject(
      "unsupported-chart", "Native area axis title rotation requires support",
    )
  }
  line_fields(line_child(rich, "lstStyle"), [])
  let paragraph = line_child(rich, "p")
  line_fields(paragraph, ["pPr", "r"], uri=drawing_uri)
  let properties = line_child(paragraph, "pPr")
  line_fields(properties, ["defRPr"], attributes=["algn"], uri=drawing_uri)
  guard properties.node.attribute("algn").unwrap_or("ctr") == "ctr" else {
    @failure.reject(
      "unsupported-chart", "Native area title alignment requires support",
    )
  }
  let runs = paragraph.tree.all(paragraph.node.id, "r", uri=drawing_uri)
  guard !runs.is_empty() && runs.length() <= 256 else {
    @failure.reject(
      "unsupported-chart", "Native chart title run count exceeds limits",
    )
  }
  let defaults = line_child(properties, "defRPr")
  let explicit_style = if runs is [node] {
    let run : Ref = { tree: paragraph.tree, node, }
    run
    .child("rPr")
    .filter(properties => {
      properties.child("latin") is Some(_) &&
      properties.child("solidFill") is Some(_) &&
      properties.node.attribute("sz") is Some(_)
    })
  } else {
    None
  }
  let style = if explicit_style is Some(explicit) {
    for
      (name, default) in [
        ("b", "0"),
        ("i", "0"),
        ("u", "none"),
        ("strike", "noStrike"),
      ] {
      guard explicit.node.attribute(name) is Some(_) ||
        defaults.node.attribute(name).unwrap_or(default) == default else {
        @failure.reject(
          "unsupported-chart", "Mixed native chart title styling requires support",
        )
      }
    }
    for script in ["ea", "cs"] {
      guard explicit.child(script) is Some(_) || defaults.child(script) is None else {
        @failure.reject(
          "unsupported-chart", "Mixed native chart title typefaces require support",
        )
      }
    }
    ignore(line_text_style(defaults, fallback_color=Some("000000")))
    line_text_style(explicit)
  } else {
    line_text_style(defaults)
  }
  let text = runs
    .map(node => {
      let run : Ref = { tree: paragraph.tree, node, }
      line_fields(run, ["rPr", "t"], uri=drawing_uri)
      if explicit_style is None && run.child("rPr") is Some(properties) {
        line_fields(properties, [], attributes=["lang"])
      }
      let text = line_child(run, "t")
      line_fields(text, [])
      text.node.text
    })
    .join("")
  guard text.length() <= 256 && !text.contains("\n") && !text.contains("\r") else {
    @failure.reject(
      "unsupported-chart", "Native area title exceeds text limits",
    )
  }
  (text, style)
}

///|
fn area_axis(
  axis : Ref,
  category : Bool,
  flat~ : Bool = false,
  fallback~ : @layout.TextStyle? = None,
) -> (
  @layout.TextStyle,
  (String, @layout.TextStyle),
  (String, Double),
  (String, Double),
) raise @failure.Failure {
  let fields = [
    "axId", "scaling", "axPos", "majorGridlines", "title", "numFmt", "tickLblPos",
    "spPr", "txPr", "crossAx", "crosses", "lblAlgn", "lblOffset", "crossBetween",
    "majorTickMark", "minorTickMark", "auto", "noMultiLvlLbl", "delete",
  ]
  line_fields(axis, fields)
  for name in ["auto", "noMultiLvlLbl"] {
    if axis.child(name, uri=chart_uri) is Some(flag) {
      let enabled = line_boolean(flag)
      guard enabled == (name == "auto") else {
        @failure.reject(
          "unsupported-chart", "Area category label mode requires support",
        )
      }
    }
  }
  if !flat && axis.child("delete", uri=chart_uri) is Some(deleted) {
    guard !line_boolean(deleted) else {
      @failure.reject("unsupported-chart", "Hidden area axes require support")
    }
  }
  if flat {
    if category {
      native_flag(chart_child(axis, "majorTickMark"), "in")
      guard axis.child("delete", uri=chart_uri) is None else {
        @failure.reject(
          "unsupported-chart", "Hidden flat area category axis requires support",
        )
      }
    } else {
      native_flag(chart_child(axis, "delete"), "1")
      guard axis.child("majorTickMark", uri=chart_uri) is None else {
        @failure.reject(
          "unsupported-chart", "Hidden flat area ticks require support",
        )
      }
    }
  }
  for name in ["axId", "crossAx"] {
    let node = chart_child(axis, name)
    line_fields(node, [], attributes=["val"])
    ignore(number(node.node.attribute("val").unwrap_or(""), 1, 4294967295))
  }
  let scaling = chart_child(axis, "scaling")
  line_fields(scaling, ["orientation"])
  native_flag(chart_child(scaling, "orientation"), "minMax")
  native_flag(chart_child(axis, "axPos"), if category { "b" } else { "l" })
  native_flag(
    chart_child(axis, "tickLblPos"),
    if flat && category {
      "low"
    } else {
      "nextTo"
    },
  )
  native_flag(chart_child(axis, "crosses"), "autoZero")
  if axis.child("numFmt", uri=chart_uri) is Some(format) {
    line_fields(format, [], attributes=["formatCode", "sourceLinked"])
    guard format.node.attribute("formatCode") ==
      Some(if category || flat { "General" } else { "0%" }) &&
      [None, Some("1"), Some("true"), Some("0"), Some("false")].contains(
        format.node.attribute("sourceLinked"),
      ) else {
      @failure.reject(
        "unsupported-chart", "Native area axis number format requires support",
      )
    }
  } else {
    guard category else {
      @failure.reject(
        "unsupported-chart", "Native percentage axis requires its number format",
      )
    }
  }
  if category {
    native_flag(chart_child(axis, "lblAlgn"), "ctr")
    native_flag(chart_child(axis, "lblOffset"), "100")
    guard axis.child("crossBetween", uri=chart_uri) is None &&
      (flat || axis.child("majorGridlines", uri=chart_uri) is None) else {
      @failure.reject(
        "unsupported-chart", "Native area category grid requires support",
      )
    }
  } else {
    native_flag(chart_child(axis, "crossBetween"), "midCat")
    guard axis.child("lblAlgn", uri=chart_uri) is None &&
      axis.child("lblOffset", uri=chart_uri) is None else {
      @failure.reject(
        "unsupported-chart", "Unknown native area value-axis labels",
      )
    }
  }
  let (fill, pen) = if flat &&
    !category &&
    axis.child("spPr", uri=chart_uri) is None {
    ("", ("", 0.0))
  } else {
    line_box(chart_child(axis, "spPr"), round_join=true)
  }
  guard fill.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native area axis fill requires support",
    )
  }
  let grid = axis
    .child("majorGridlines", uri=chart_uri)
    .map(grid => {
      line_fields(grid, ["spPr"])
      let (fill, pen) = line_box(chart_child(grid, "spPr"), round_join=true)
      guard fill.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Native area grid fill requires support",
        )
      }
      (if pen.0 == "000000" { "868686" } else { pen.0 }, pen.1)
    })
    .unwrap_or(("", 0))
  let text = if axis.child("txPr", uri=chart_uri) is Some(text) {
    line_text(text)
  } else if flat && fallback is Some(style) {
    style
  } else {
    @failure.reject("unsupported-chart", "Native area axis text is missing")
  }
  (
    if flat {
      circular_text_style(text)
    } else {
      text
    },
    native_title(chart_child(axis, "title"), category || flat),
    pen,
    grid,
  )
}

///|
fn read_native_area(root : Ref) -> NativeArea raise @failure.Failure {
  line_fields(root, ["lang", "chart", "printSettings", "roundedCorners", "spPr"])
  if root.child("roundedCorners", uri=chart_uri) is Some(rounded) {
    guard !line_boolean(rounded) else {
      @failure.reject(
        "unsupported-chart", "Rounded area chart frames require support",
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
    for attribute in margins.node.attributes {
      ignore(line_real(attribute.value, 0, 100))
    }
  }
  let chart = chart_child(root, "chart")
  let plot = chart_child(chart, "plotArea")
  let flat = plot.child("area3DChart", uri=chart_uri) is Some(_)
  let fields = ["plotArea", "plotVisOnly", "dispBlanksAs", "autoTitleDeleted"]
  if chart.child("autoTitleDeleted", uri=chart_uri) is Some(deleted) {
    guard line_boolean(deleted) else {
      @failure.reject(
        "unsupported-chart", "Automatic area titles require support",
      )
    }
  }
  if flat {
    fields.append(["view3D", "floor", "sideWall", "backWall"])
  }
  line_fields(chart, fields)
  native_flag(chart_child(chart, "plotVisOnly"), "1")
  native_flag(chart_child(chart, "dispBlanksAs"), "zero")
  line_fields(plot, [
    "layout",
    if flat {
      "area3DChart"
    } else {
      "areaChart"
    },
    "catAx",
    "valAx",
    "spPr",
  ])
  let (flat_plot, back_fill, floor_pen) = if flat {
    let view = chart_child(chart, "view3D")
    line_fields(view, ["rotX", "rotY", "depthPercent", "rAngAx"])
    native_flag(chart_child(view, "rAngAx"), "1")
    for name in ["rotX", "rotY"] {
      if view.child(name, uri=chart_uri) is Some(rotation) {
        native_flag(rotation, "0")
      }
    }
    let depth = chart_child(view, "depthPercent")
    line_fields(depth, [], attributes=["val"])
    ignore(line_real(depth.node.attribute("val").unwrap_or(""), 20, 2000))
    let surface = fn(name : String) raise @failure.Failure {
      let surface = chart_child(chart, name)
      line_fields(surface, ["spPr"])
      line_box(chart_child(surface, "spPr"))
    }
    let (floor_fill, floor_pen) = surface("floor")
    let (side_fill, side_pen) = surface("sideWall")
    let (back_fill, back_pen) = surface("backWall")
    guard floor_fill.is_empty() &&
      side_fill == back_fill &&
      side_pen.0.is_empty() &&
      back_pen.0.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Flat area wall and floor paints require support",
      )
    }
    let layout = chart_child(plot, "layout")
    line_fields(layout, ["manualLayout"])
    let manual = chart_child(layout, "manualLayout")
    line_fields(manual, ["layoutTarget", "xMode", "yMode", "x", "y", "w", "h"])
    if manual.child("layoutTarget", uri=chart_uri) is Some(target) {
      native_flag(target, "outer")
    }
    for name in ["xMode", "yMode"] {
      native_flag(chart_child(manual, name), "edge")
    }
    let value = fn(name : String) raise @failure.Failure {
      let value = chart_child(manual, name)
      line_fields(value, [], attributes=["val"])
      line_real(value.node.attribute("val").unwrap_or(""), 0, 1)
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
        "unsupported-chart", "Flat area manual plot exceeds frame",
      )
    }
    (Some(rect), back_fill, floor_pen)
  } else {
    if plot.child("layout", uri=chart_uri) is Some(layout) {
      line_fields(layout, [])
    }
    (None, "", ("", 0.0))
  }
  let area = chart_child(plot, if flat { "area3DChart" } else { "areaChart" })
  line_fields(area, ["grouping", "ser", "axId"])
  native_flag(
    chart_child(area, "grouping"),
    if flat {
      "stacked"
    } else {
      "percentStacked"
    },
  )
  let category_axis = chart_child(plot, "catAx")
  let value_axis = chart_child(plot, "valAx")
  let category_id = chart_child(category_axis, "axId").node.attribute("val")
  let value_id = chart_child(value_axis, "axId").node.attribute("val")
  guard category_id != value_id &&
    chart_child(category_axis, "crossAx").node.attribute("val") == value_id &&
    chart_child(value_axis, "crossAx").node.attribute("val") == category_id &&
    area.tree
    .all(area.node.id, "axId", uri=chart_uri)
    .map(node => node.attribute("val")) ==
    [category_id, value_id] + (if flat { [Some("0")] } else { [] }) else {
    @failure.reject(
      "unsupported-chart", "Native area axes require a single linked pair",
    )
  }
  let (category_text, category_title, category_pen, category_grid) = area_axis(
    category_axis,
    true,
    flat~,
  )
  let (value_text, value_title, value_pen, grid_pen) = area_axis(
    value_axis,
    false,
    flat~,
    fallback=Some(category_text),
  )
  let (plot_fill, plot_pen, plot_dash) = line_paint_box(
    chart_child(plot, "spPr"),
    round_join=true,
  )
  guard plot_dash.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native area plot dash requires support",
    )
  }
  guard !flat || (plot_fill.is_empty() && plot_pen.0.is_empty()) else {
    @failure.reject(
      "unsupported-chart", "Flat area plot paint requires support",
    )
  }
  let sources = area.tree.all(area.node.id, "ser", uri=chart_uri)
  let first : Ref = { tree: area.tree, node: sources[0], }
  let common = chart_categories(first, false)
  let indices = Map([])
  let orders = Map([])
  let series = sources.map(node => {
    let source : Ref = { tree: area.tree, node, }
    line_fields(source, ["idx", "order", "tx", "spPr", "cat", "val", "dLbls"])
    if source.child("dLbls", uri=chart_uri) is Some(labels) {
      native_inactive_labels(labels)
    }
    for (name, seen) in [("idx", indices), ("order", orders)] {
      let item = chart_child(source, name)
      line_fields(item, [], attributes=["val"])
      let value = number(
        item.node.attribute("val").unwrap_or(""),
        0,
        if name == "idx" {
          4294967295.0
        } else {
          31.0
        },
      ).to_string()
      guard !seen.contains(value) else {
        @failure.reject(
          "unsupported-chart", "Duplicate native area series identity",
        )
      }
      seen[value] = true
    }
    if source.child("tx", uri=chart_uri) is Some(title) {
      line_cache(title, false)
    }
    let categories = chart_child(source, "cat")
    line_cache(categories, categories.child("numRef", uri=chart_uri) is Some(_))
    line_cache(chart_child(source, "val"), true)
    guard chart_categories(source, false) == common else {
      @failure.reject(
        "unsupported-chart", "Native area category caches must agree",
      )
    }
    let properties = chart_child(source, "spPr")
    let (fill, pen, dash) = line_paint_box(properties, round_join=!flat)
    guard dash.is_empty() && (flat || !fill.is_empty()) else {
      @failure.reject(
        "unsupported-chart", "Native area requires a solid series fill",
      )
    }
    // Native area output uses miter joins even when source round joins are retained.
    NativeAreaSeries::{ fill, pen, }
  })
  let tick = fn(
    axis : Ref,
    name : String,
    fallback : String,
  ) raise @failure.Failure {
    axis
    .child(name, uri=chart_uri)
    .map(tick => {
      line_fields(tick, [], attributes=["val"])
      let value = tick.node.attribute("val").unwrap_or("")
      guard ["none", "out", "in", "cross"].contains(value) else {
        @failure.reject("unsupported-chart", "Invalid area axis tick mark")
      }
      value
    })
    .unwrap_or(fallback)
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
    series,
    category_text,
    value_text,
    category_title,
    value_title,
    category_pen,
    value_pen,
    grid_pen,
    plot_fill: if flat {
      back_fill
    } else {
      plot_fill
    },
    plot_pen,
    flat_plot,
    category_grid,
    floor_pen,
    category_tick: tick(
      category_axis,
      "majorTickMark",
      if flat {
        "in"
      } else {
        "out"
      },
    ),
    category_minor_tick: tick(category_axis, "minorTickMark", "none"),
    value_tick: tick(value_axis, "majorTickMark", "out"),
    value_minor_tick: tick(value_axis, "minorTickMark", "none"),
  }
}
