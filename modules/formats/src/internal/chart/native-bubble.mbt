///|
struct NativeBubbleSeries {
  idx : Int64
  fill : String
  pen : (String, Double)
  marker_pen : (String, Double)
  styled_points : Set[Int32]
}

///|
pub struct NativeBubble {
  frame_fill : String
  frame_pen : (String, Double)
  frame_default_fill : Bool
  frame_default_pen : Bool
  series : Array[NativeBubbleSeries]
  sizes : Array[Array[Double?]]
  size_sources : Array[String?]
  x_text : @layout.TextStyle
  y_text : @layout.TextStyle
  x_pen : (String, Double)
  y_pen : (String, Double)
  grid_pen : (String, Double)
  x_ticks : (String?, String?)
  y_ticks : (String?, String?)
  plot_fill : String
  plot_pen : (String, Double)
  legend : NativeLegend?
}

///|
fn bubble_axis(
  axis : Ref,
  horizontal : Bool,
) -> (@layout.TextStyle, (String, Double), (String, Double), (String?, String?)) raise @failure.Failure {
  line_fields(axis, [
    "axId", "scaling", "axPos", "numFmt", "tickLblPos", "spPr", "txPr", "crossAx",
    "crosses", "crossBetween", "majorGridlines", "delete", "majorTickMark", "minorTickMark",
  ])
  if axis.child("delete", uri=chart_uri) is Some(deleted) {
    guard !line_boolean(deleted) else {
      @failure.reject("unsupported-chart", "Hidden bubble axes require support")
    }
  }
  let tick = fn(name : String) raise @failure.Failure {
    axis
    .child(name, uri=chart_uri)
    .map(tick => {
      line_fields(tick, [], attributes=["val"])
      let kind = tick.node.attribute("val").unwrap_or("")
      guard ["none", "in", "out", "cross"].contains(kind) else {
        @failure.reject("unsupported-chart", "Invalid bubble tick mark")
      }
      kind
    })
  }
  for name in ["axId", "crossAx"] {
    let item = chart_child(axis, name)
    line_fields(item, [], attributes=["val"])
    ignore(number(item.node.attribute("val").unwrap_or(""), 1, 4294967295))
  }
  let scaling = chart_child(axis, "scaling")
  line_fields(scaling, ["orientation"])
  native_flag(chart_child(scaling, "orientation"), "minMax")
  native_flag(chart_child(axis, "axPos"), if horizontal { "b" } else { "l" })
  native_flag(chart_child(axis, "tickLblPos"), "nextTo")
  native_flag(chart_child(axis, "crosses"), "autoZero")
  native_flag(chart_child(axis, "crossBetween"), "midCat")
  let format = chart_child(axis, "numFmt")
  line_fields(format, [], attributes=["formatCode", "sourceLinked"])
  guard format.node.attribute("formatCode") == Some("General") &&
    [None, Some("0"), Some("false"), Some("1"), Some("true")].contains(
      format.node.attribute("sourceLinked"),
    ) else {
    @failure.reject(
      "unsupported-chart", "Native bubble axis number format requires support",
    )
  }
  let (fill, pen) = line_box(chart_child(axis, "spPr"), round_join=true)
  guard fill.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native bubble axis fill requires support",
    )
  }
  let grid = axis
    .child("majorGridlines", uri=chart_uri)
    .map(grid => {
      line_fields(grid, ["spPr"])
      let (fill, pen) = line_box(chart_child(grid, "spPr"), round_join=true)
      guard fill.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Native bubble grid fill requires support",
        )
      }
      pen
    })
    .unwrap_or(("", 0))
  (
    line_text(chart_child(axis, "txPr")),
    pen,
    grid,
    (tick("majorTickMark"), tick("minorTickMark")),
  )
}

///|
fn read_native_bubble(root : Ref) -> NativeBubble raise @failure.Failure {
  line_fields(root, ["lang", "chart", "printSettings", "roundedCorners", "spPr"])
  if root.child("roundedCorners", uri=chart_uri) is Some(rounded) {
    guard !line_boolean(rounded) else {
      @failure.reject(
        "unsupported-chart", "Rounded bubble frames require support",
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
    for item in margins.node.attributes {
      ignore(line_real(item.value, 0, 100))
    }
  }
  let chart = chart_child(root, "chart")
  line_fields(chart, [
    "plotArea", "legend", "plotVisOnly", "dispBlanksAs", "autoTitleDeleted",
  ])
  if chart.child("autoTitleDeleted", uri=chart_uri) is Some(deleted) {
    guard line_boolean(deleted) else {
      @failure.reject(
        "unsupported-chart", "Automatic bubble titles require support",
      )
    }
  }
  native_flag(chart_child(chart, "plotVisOnly"), "1")
  native_flag(chart_child(chart, "dispBlanksAs"), "gap")
  let plot = chart_child(chart, "plotArea")
  line_fields(plot, ["layout", "bubbleChart", "valAx", "spPr"])
  if plot.child("layout", uri=chart_uri) is Some(layout) {
    line_fields(layout, [])
  }
  let bubble = chart_child(plot, "bubbleChart")
  line_fields(bubble, ["ser", "bubbleScale", "axId", "varyColors"])
  if bubble.child("bubbleScale", uri=chart_uri) is Some(scale) {
    native_flag(scale, "100")
  }
  if bubble.child("varyColors", uri=chart_uri) is Some(vary) {
    guard !line_boolean(vary) else {
      @failure.reject(
        "unsupported-chart", "Varying bubble point colors require support",
      )
    }
  }
  let axes = plot.tree.all(plot.node.id, "valAx", uri=chart_uri)
  guard axes is [x, y] else {
    @failure.reject(
      "unsupported-chart", "Native bubble charts require two value axes",
    )
  }
  let x : Ref = { tree: plot.tree, node: x, }
  let y : Ref = { tree: plot.tree, node: y, }
  let x_id = chart_child(x, "axId").node.attribute("val")
  let y_id = chart_child(y, "axId").node.attribute("val")
  guard x_id != y_id &&
    chart_child(x, "crossAx").node.attribute("val") == y_id &&
    chart_child(y, "crossAx").node.attribute("val") == x_id &&
    bubble.tree
    .all(bubble.node.id, "axId", uri=chart_uri)
    .map(n => n.attribute("val")) ==
    [x_id, y_id] else {
    @failure.reject(
      "unsupported-chart", "Native bubble axes require a linked numeric pair",
    )
  }
  let (x_text, x_pen, x_grid, x_ticks) = bubble_axis(x, true)
  let (y_text, y_pen, grid_pen, y_ticks) = bubble_axis(y, false)
  guard x_grid.0.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native bubble horizontal grid requires support",
    )
  }
  let (plot_fill, plot_pen) = line_box(
    chart_child(plot, "spPr"),
    round_join=true,
  )
  let sizes : Array[Array[Double?]] = []
  let size_sources : Array[String?] = []
  let indices = Map([])
  let orders = Map([])
  let sources = bubble.tree.all(bubble.node.id, "ser", uri=chart_uri)
  let common = chart_categories({ tree: bubble.tree, node: sources[0], }, true)
  let series = sources.mapi((index, node) => {
    let source : Ref = { tree: bubble.tree, node, }
    line_fields(source, [
      "idx", "order", "tx", "spPr", "xVal", "yVal", "bubbleSize", "bubble3D", "dPt",
      "invertIfNegative", "dLbls",
    ])
    if source.child("invertIfNegative", uri=chart_uri) is Some(invert) {
      guard !line_boolean(invert) else {
        @failure.reject(
          "unsupported-chart", "Inverted negative bubbles require support",
        )
      }
    }
    if source.child("dLbls", uri=chart_uri) is Some(labels) {
      native_inactive_labels(labels, points=common.length())
    }
    // The native bubble path renderer paints retained bubble3D flags as flat circles.
    ignore(circular_bool(source.child("bubble3D", uri=chart_uri)))
    let (fill, pen) = line_box(chart_child(source, "spPr"), round_join=true)
    guard !fill.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Native bubbles require a solid series fill",
      )
    }
    let point_indices = Set([])
    let styled_points = Set([])
    for point in source.tree.all(source.node.id, "dPt", uri=chart_uri) {
      let point : Ref = { tree: source.tree, node: point, }
      line_fields(point, ["idx", "bubble3D", "invertIfNegative", "spPr"])
      let identity = chart_child(point, "idx")
      line_fields(identity, [], attributes=["val"])
      let value = number(
        identity.node.attribute("val").unwrap_or(""),
        0,
        (common.length() - 1).to_double(),
      )
      guard value == value.floor() && !point_indices.contains(value.to_int()) else {
        @failure.reject(
          "unsupported-chart", "Duplicate native bubble point identity",
        )
      }
      point_indices.add(value.to_int())
      ignore(circular_bool(point.child("bubble3D", uri=chart_uri)))
      if point.child("invertIfNegative", uri=chart_uri) is Some(invert) {
        guard !line_boolean(invert) else {
          @failure.reject(
            "unsupported-chart", "Inverted negative bubble points require support",
          )
        }
      }
      if point.child("spPr", uri=chart_uri) is Some(paint) {
        guard line_box(paint, round_join=true) == (fill, pen) else {
          @failure.reject(
            "unsupported-chart", "Bubble point paint differs from its series",
          )
        }
        styled_points.add(value.to_int())
      }
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
      )
      guard value == value.floor() &&
        !seen.contains(value.to_string()) &&
        (name != "order" || value == index.to_double()) else {
        @failure.reject(
          "unsupported-chart", "Duplicate native bubble series identity",
        )
      }
      seen[value.to_string()] = true
    }
    if source.child("tx", uri=chart_uri) is Some(title) {
      line_cache(title, false)
    }
    line_cache(chart_child(source, "xVal"), true)
    line_cache(chart_child(source, "yVal"), true)
    guard chart_categories(source, true) == common else {
      @failure.reject(
        "unsupported-chart", "Native bubble series require common numeric X caches",
      )
    }
    let size = source.child("bubbleSize", uri=chart_uri)
    let values = if size is Some(size) {
      line_fields(size, ["numRef", "numLit"])
      let cache = if size.child("numRef", uri=chart_uri) is Some(reference) {
        guard size.child("numLit", uri=chart_uri) is None else {
          @failure.reject(
            "unsupported-chart", "Ambiguous native bubble size cache",
          )
        }
        line_cache(size, true)
        size_sources.push(Some(chart_child(reference, "f").node.text))
        chart_child(reference, "numCache")
      } else {
        let cache = chart_child(size, "numLit")
        size_sources.push(None)
        cache
      }
      line_fields(cache, ["formatCode", "ptCount", "pt"])
      if cache.child("formatCode", uri=chart_uri) is Some(format) {
        line_fields(format, [])
        guard format.node.text == "General" else {
          @failure.reject(
            "unsupported-chart", "Native bubble size number format requires support",
          )
        }
      }
      line_fields(chart_child(cache, "ptCount"), [], attributes=["val"])
      for point in cache.tree.all(cache.node.id, "pt", uri=chart_uri) {
        let point : Ref = { tree: cache.tree, node: point, }
        line_fields(point, ["v"], attributes=["idx"])
        line_fields(chart_child(point, "v"), [])
      }
      chart_points(cache, true).map(text => {
        if text.is_empty() {
          None
        } else {
          let value = @string.parse_double(text) catch {
            _ =>
              @failure.reject("unsupported-chart", "Invalid native bubble size")
          }
          guard !value.is_nan() && !value.is_inf() else {
            @failure.reject(
              "unsupported-chart", "Non-finite native bubble size",
            )
          }
          Some(value)
        }
      })
    } else {
      size_sources.push(None)
      Array::make(common.length(), None)
    }
    guard values.length() == common.length() &&
      chart_points(
        chart_child(
          chart_child(chart_child(source, "yVal"), "numRef"),
          "numCache",
        ),
        true,
      ).length() ==
      common.length() else {
      @failure.reject(
        "unsupported-chart", "Native bubble X Y and size caches must align",
      )
    }
    sizes.push(values)
    NativeBubbleSeries::{
      idx: number(
        chart_child(source, "idx").node.attribute("val").unwrap(),
        0,
        4294967295,
      ).to_int64(),
      fill,
      pen,
      marker_pen: (fill, 0.75),
      styled_points,
    }
  })
  let frame = root.child("spPr", uri=chart_uri)
  let (frame_fill, frame_pen) = frame
    .map(paint => line_box(paint, round_join=true))
    .unwrap_or(("", ("d9d9d9", 0.75)))
  {
    frame_fill: if frame_fill.is_empty() {
      "ffffff"
    } else {
      frame_fill
    },
    frame_pen,
    frame_default_fill: frame.bind(paint => paint.child("solidFill")) is None,
    frame_default_pen: frame is None,
    series,
    sizes,
    size_sources,
    x_text,
    y_text,
    x_pen,
    y_pen,
    grid_pen,
    x_ticks,
    y_ticks,
    plot_fill,
    plot_pen,
    legend: chart
    .child("legend", uri=chart_uri)
    .map(legend => native_legend(legend, round_join=true)),
  }
}

///|
pub fn WorksheetChart::with_bubble_sizes(
  self : WorksheetChart,
  sizes : Array[Array[Double?]],
) -> WorksheetChart raise @failure.Failure {
  guard self.native_bubble is Some(bubble) &&
    sizes.length() == self.data.series.length() &&
    sizes
    .mapi((i, values) => {
      values.length() == self.data.series[i].values.length() &&
      values.length() == self.data.categories.length() &&
      values.all(v => v.map(n => !n.is_nan() && !n.is_inf()).unwrap_or(true))
    })
    .all(value => value) else {
    @failure.reject(
      "invalid-chart", "Native bubble sizes must align with finite source values",
    )
  }
  { ..self, native_bubble: Some({ ..bubble, sizes, }), }
}
