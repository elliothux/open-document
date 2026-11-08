///|
fn line_read_labels(source : Ref) -> NativeLineLabels raise @failure.Failure {
  line_fields(source, [
    "spPr", "txPr", "showLegendKey", "showVal", "showCatName", "showSerName", "showPercent",
    "showBubbleSize",
  ])
  for name in ["showLegendKey", "showCatName", "showPercent", "showBubbleSize"] {
    guard !source.child(name, uri=chart_uri).map(line_boolean).unwrap_or(false) else {
      @failure.reject(
        "unsupported-chart", "Native line data label requires support",
      )
    }
  }
  let (fill, pen, dash) = line_paint_box(chart_child(source, "spPr"))
  guard dash.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native data label dash requires support",
    )
  }
  {
    fill,
    pen,
    text: circular_text_style(line_text(chart_child(source, "txPr"))),
    value: source
    .child("showVal", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(false),
    series: source
    .child("showSerName", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(false),
  }
}

///|
fn line_read_trend(source : Ref) -> NativeLineTrend raise @failure.Failure {
  line_fields(source, [
    "spPr", "trendlineType", "order", "dispEq", "dispRSqr", "trendlineLbl",
  ])
  native_flag(chart_child(source, "trendlineType"), "poly")
  let order = chart_child(source, "order")
  line_fields(order, [], attributes=["val"])
  let order = number(order.node.attribute("val").unwrap_or(""), 2, 6)
  guard order == order.floor() else {
    @failure.reject("unsupported-chart", "Invalid polynomial order")
  }
  let (fill, pen, dash) = line_paint_box(chart_child(source, "spPr"))
  guard fill.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native trendline fill requires support",
    )
  }
  let label = chart_child(source, "trendlineLbl")
  line_fields(label, ["layout", "numFmt", "spPr", "txPr"])
  line_fields(chart_child(label, "layout"), [])
  let format = chart_child(label, "numFmt")
  line_fields(format, [], attributes=["formatCode", "sourceLinked"])
  guard format.node.attribute("formatCode") == Some("General") &&
    [Some("0"), Some("false")].contains(format.node.attribute("sourceLinked")) else {
    @failure.reject(
      "unsupported-chart", "Native trendline format requires support",
    )
  }
  let (label_fill, label_pen, label_dash) = line_paint_box(
    chart_child(label, "spPr"),
  )
  guard label_fill.is_empty() && label_pen.0.is_empty() && label_dash.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native trendline label paint requires support",
    )
  }
  {
    order: order.to_int(),
    pen,
    dash,
    text: circular_text_style(line_text(chart_child(label, "txPr"))),
    equation: source
    .child("dispEq", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(true),
    r_squared: source
    .child("dispRSqr", uri=chart_uri)
    .map(line_boolean)
    .unwrap_or(true),
  }
}

///|
fn read_native_line(
  root : Ref,
  scatter~ : Bool = false,
) -> NativeLine raise @failure.Failure {
  line_fields(root, ["lang", "roundedCorners", "chart", "spPr", "printSettings"])
  if root.child("lang", uri=chart_uri) is Some(language) {
    line_fields(language, [], attributes=["val"])
  }
  if root.child("roundedCorners", uri=chart_uri) is Some(rounded) {
    ignore(line_boolean(rounded))
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
    "title", "plotArea", "legend", "plotVisOnly", "dispBlanksAs",
  ])
  native_flag(chart_child(chart, "plotVisOnly"), "1")
  native_flag(chart_child(chart, "dispBlanksAs"), "gap")
  let plot = chart_child(chart, "plotArea")
  let mixed = !scatter && plot.child("barChart", uri=chart_uri) is Some(_)
  guard !mixed ||
    (
      chart.child("title", uri=chart_uri) is None &&
      chart.child("legend", uri=chart_uri) is None
    ) else {
    @failure.reject(
      "unsupported-chart", "Mixed chart titles and legends require support",
    )
  }
  line_fields(
    plot,
    if scatter {
      ["layout", "scatterChart", "valAx", "spPr"]
    } else {
      ["layout", "lineChart", "catAx", "valAx", "spPr"] +
      (if mixed { ["barChart"] } else { [] })
    },
  )
  let layout = chart_child(plot, "layout")
  line_fields(layout, ["manualLayout"])
  let position = layout
    .child("manualLayout", uri=chart_uri)
    .map(manual => {
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
        @failure.reject("unsupported-chart", "Native line plot exceeds frame")
      }
      rect
    })
  let tree = plot.tree
  let groups = if mixed {
    let columns = tree.all(plot.node.id, "barChart", uri=chart_uri)
    let lines = tree.all(plot.node.id, "lineChart", uri=chart_uri)
    guard columns.length() == 1 &&
      lines.length() == 1 &&
      columns[0].start < lines[0].start else {
      @failure.reject(
        "unsupported-chart", "Mixed charts require a column group followed by a line group",
      )
    }
    columns + lines
  } else {
    tree.all(
      plot.node.id,
      if scatter {
        "scatterChart"
      } else {
        "lineChart"
      },
      uri=chart_uri,
    )
  }
  let categories = tree.all(plot.node.id, "catAx", uri=chart_uri)
  let values = tree.all(plot.node.id, "valAx", uri=chart_uri)
  guard groups.length() == 1 || position is Some(_) || mixed else {
    @failure.reject(
      "unsupported-chart", "Native dual axes require an outer manual plot layout",
    )
  }
  guard groups.length() >= 1 &&
    groups.length() <= 2 &&
    (if scatter {
      categories.is_empty() && values.length() == groups.length() * 2
    } else {
      categories.length() == groups.length() &&
      values.length() == groups.length()
    }) else {
    @failure.reject(
      "unsupported-chart", "Native line requires one or two linked axis pairs",
    )
  }
  let ids : Set[String] = Set([])
  for node in categories + values {
    let axis : Ref = { tree, node, }
    let id = chart_child(axis, "axId").node.attribute("val").unwrap_or("")
    guard !ids.contains(id) else {
      @failure.reject("unsupported-chart", "Duplicate native axis id")
    }
    ids.add(id)
  }
  let series : Array[NativeLineCurve] = []
  let sources : Array[Ref] = []
  let axes : Array[NativeLineAxis] = []
  let mut category : NativeLineAxis? = None
  let mut secondary_x : NativeLineAxis? = None
  let orders : Set[Double] = Set([])
  let indices : Set[Double] = Set([])
  let mut point_legend = false
  for axis, node in groups {
    let group : Ref = { tree, node, }
    let column = node.name == "barChart"
    line_fields(
      group,
      if scatter {
        ["scatterStyle", "varyColors", "ser", "axId"]
      } else if column {
        ["barDir", "grouping", "ser", "gapWidth", "overlap", "axId"]
      } else {
        ["grouping", "ser", "marker", "axId"]
      },
    )
    let point_colors = scatter &&
      group
      .child("varyColors", uri=chart_uri)
      .map(line_boolean)
      .unwrap_or(false)
    if scatter {
      native_flag(chart_child(group, "scatterStyle"), "lineMarker")
    } else if column {
      native_flag(chart_child(group, "barDir"), "col")
      native_flag(chart_child(group, "grouping"), "clustered")
      if group.child("overlap", uri=chart_uri) is Some(overlap) {
        native_flag(overlap, "0")
      }
    } else {
      native_flag(chart_child(group, "grouping"), "standard")
      native_flag(chart_child(group, "marker"), "1")
    }
    let gap = if column {
      group
      .child("gapWidth", uri=chart_uri)
      .map(gap => {
        line_fields(gap, [], attributes=["val"])
        let value = number(gap.node.attribute("val").unwrap_or(""), 0, 500)
        guard value == value.floor() else {
          @failure.reject("unsupported-chart", "Column gap must be an integer")
        }
        value / 100
      })
      .unwrap_or(1.5)
    } else {
      0.0
    }
    let linked = tree.all(node.id, "axId", uri=chart_uri)
    guard linked.length() == 2 else {
      @failure.reject("unsupported-chart", "Native curve requires two axes")
    }
    let find_axis = fn(index : Int32) raise @failure.Failure {
      (categories + values)
      .iter()
      .find_first(node => {
        let source : Ref = { tree, node, }
        chart_child(source, "axId").node.attribute("val") ==
        linked[index].attribute("val")
      })
      .unwrap_or_else(() => {
        @failure.reject("unsupported-chart", "Missing linked curve axis")
      })
    }
    let cat : Ref = { tree, node: find_axis(0), }
    let val : Ref = { tree, node: find_axis(1), }
    let cat_id = chart_child(cat, "axId").node.attribute("val")
    let val_id = chart_child(val, "axId").node.attribute("val")
    guard chart_child(cat, "crossAx").node.attribute("val") == val_id &&
      chart_child(val, "crossAx").node.attribute("val") == cat_id &&
      tree.all(node.id, "axId", uri=chart_uri).map(n => n.attribute("val")) ==
      [cat_id, val_id] else {
      @failure.reject("unsupported-chart", "Unlinked native line axes")
    }
    let parsed = line_read_axis(cat, true, axis > 0, scatter~)
    if axis == 0 {
      category = Some(parsed)
    } else if scatter {
      secondary_x = Some(parsed)
    }
    axes.push(line_read_axis(val, false, axis > 0, scatter~))
    let nodes = tree.all(node.id, "ser", uri=chart_uri)
    guard !nodes.is_empty() else {
      @failure.reject("unsupported-chart", "Empty native line group")
    }
    let series_palette = !point_colors || nodes.length() != 1
    let show_legend_marker = series_palette || groups.length() == 1
    if scatter && groups.length() == 1 && nodes.length() == 1 {
      point_legend = point_colors ||
        tree
        .all(nodes[0].id, "dPt", uri=chart_uri)
        .any(point => tree.one(point.id, "spPr", uri=chart_uri) is Some(_))
    }
    for node in nodes {
      let source : Ref = { tree, node, }
      line_fields(
        source,
        if scatter {
          [
            "idx", "order", "tx", "spPr", "marker", "xVal", "yVal", "smooth", "dPt",
          ]
        } else if column {
          ["idx", "order", "tx", "spPr", "cat", "val", "dPt"]
        } else {
          [
            "idx", "order", "tx", "spPr", "marker", "cat", "val", "smooth", "dLbls",
            "trendline",
          ]
        },
      )
      let mut idx = 0L
      for (name, seen) in [("idx", indices), ("order", orders)] {
        let value = chart_child(source, name)
        line_fields(value, [], attributes=["val"])
        let value = number(
          value.node.attribute("val").unwrap_or(""),
          0,
          if name == "idx" {
            4294967295.0
          } else {
            31.0
          },
        )
        guard value == value.floor() && !seen.contains(value) else {
          @failure.reject(
            "unsupported-chart", "Duplicate or invalid native series index",
          )
        }
        seen.add(value)
        if name == "idx" {
          idx = value.to_int64()
        }
      }
      if source.child("tx", uri=chart_uri) is Some(title) {
        line_cache(title, false)
      }
      let cat = chart_child(source, if scatter { "xVal" } else { "cat" })
      line_cache(cat, cat.child("numRef", uri=chart_uri) is Some(_))
      line_cache(
        chart_child(source, if scatter { "yVal" } else { "val" }),
        true,
      )
      let properties = chart_child(source, "spPr")
      let (fill, (color, width), dash) = line_paint_box(properties)
      guard column || fill.is_empty() else {
        @failure.reject(
          "unsupported-chart", "Native line series fill requires support",
        )
      }
      let base : NativeLineSeries = {
        color,
        width,
        marker: "none",
        marker_size: 0,
        marker_fill: "",
        marker_pen: Some(("", 0.75)),
      }
      let curve_pen = if !series_palette &&
        dash.is_empty() &&
        properties.child("ln") is Some(_) {
        Some((color, width))
      } else {
        None
      }
      let marker = if column {
        None
      } else {
        Some(chart_child(source, "marker"))
      }
      let marker_properties = marker.bind(marker => {
        marker.child("spPr", uri=chart_uri)
      })
      let paint = marker
        .map(marker => {
          let base = if marker_properties is Some(_) {
            { ..base, marker_pen: curve_pen, }
          } else {
            base
          }
          line_read_marker(
            marker,
            base,
            inherit_outline=series_palette || curve_pen is Some(_),
          )
        })
        .unwrap_or(base)
      let inherited_pen = if marker_properties.bind(style => style.child("ln"))
        is Some(_) {
        paint.marker_pen
      } else {
        curve_pen
      }
      let points : Map[Int32, NativeLineSeries] = Map([])
      let count = chart_categories(source, scatter).length()
      for
        point in (if column {
          []
        } else {
          tree.all(node.id, "dPt", uri=chart_uri)
        }) {
        let point : Ref = { tree, node: point, }
        line_fields(point, ["idx", "marker", "spPr"])
        let index = chart_child(point, "idx")
        line_fields(index, [], attributes=["val"])
        let index = number(
          index.node.attribute("val").unwrap_or(""),
          0,
          (count - 1).to_double(),
        )
        guard index == index.floor() && !points.contains(index.to_int()) else {
          @failure.reject(
            "unsupported-chart", "Duplicate or invalid scatter point style",
          )
        }
        let point_properties = point.child("spPr", uri=chart_uri)
        let point_paint = point_properties
          .map(style => {
            let (fill, (color, width), dash) = line_paint_box(style)
            guard fill.is_empty() && dash.is_empty() else {
              @failure.reject(
                "unsupported-chart", "Scatter point line paint requires support",
              )
            }
            { ..paint, color, width, }
          })
          .unwrap_or(paint)
        points[index.to_int()] = point
          .child("marker", uri=chart_uri)
          .map(marker => {
            let pen = if series_palette {
              point_paint.marker_pen
            } else if point_properties.bind(style => style.child("ln"))
              is Some(_) {
              Some((point_paint.color, point_paint.width))
            } else {
              inherited_pen
            }
            line_read_marker(
              marker,
              { ..point_paint, marker_pen: pen, },
              inherit_outline=series_palette || pen is Some(_),
            )
          })
          .unwrap_or(point_paint)
      }
      series.push({
        idx,
        paint,
        show_legend_marker,
        plot_markers: series_palette,
        axis,
        smooth: source
        .child("smooth", uri=chart_uri)
        .map(line_boolean)
        .unwrap_or(false),
        dash,
        labels: source.child("dLbls", uri=chart_uri).map(line_read_labels),
        trend: source.child("trendline", uri=chart_uri).map(line_read_trend),
        points,
        column: if column {
          guard !fill.is_empty() && dash.is_empty() else {
            @failure.reject(
              "unsupported-chart", "Native columns require a solid series fill and pen",
            )
          }
          Some(read_native_column(source, fill, (color, width), gap, count))
        } else {
          None
        },
      })
      sources.push(source)
    }
  }
  guard series.length() <= 32 &&
    sources.all(source => {
      chart_categories(source, scatter) == chart_categories(sources[0], scatter)
    }) else {
    @failure.reject(
      "unsupported-chart", "Native line category caches must agree",
    )
  }
  let (plot_fill, plot_pen, plot_dash) = line_paint_box(
    chart_child(plot, "spPr"),
  )
  guard plot_dash.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native line plot dash requires support",
    )
  }
  let frame = root.child("spPr", uri=chart_uri)
  let (frame_fill, frame_pen, frame_dash) = frame
    .map(paint => line_paint_box(paint))
    .unwrap_or(("ffffff", (line_frame_color("000000"), 0.75), []))
  guard !frame_fill.is_empty() else {
    @failure.reject(
      "unsupported-chart", "Native line frame requires a solid background",
    )
  }
  let legend_source = chart.child("legend", uri=chart_uri)
  guard mixed || legend_source is Some(_) else {
    @failure.reject("unsupported-chart", "Native line legend requires support")
  }
  let side = legend_source
    .map(legend => {
      chart_child(legend, "legendPos").node.attribute("val").unwrap_or("")
    })
    .unwrap_or("r")
  guard ["r", "b"].contains(side) else {
    @failure.reject(
      "unsupported-chart", "Native line legend position requires support",
    )
  }
  let legend = legend_source
    .map(legend => native_legend(legend, side~))
    .unwrap_or({
      text: category.unwrap().text,
      fill: "",
      pen: ("", 0),
      join: 0,
      position: None,
    })
  {
    frame_fill,
    frame_pen,
    frame_dash,
    frame_default: frame is None,
    series,
    category: category.unwrap(),
    secondary_x,
    axes,
    plot: position,
    title: chart.child("title", uri=chart_uri).map(title => line_caption(title)),
    plot_fill,
    plot_pen,
    legend_text: circular_text_style(legend.text),
    legend_fill: legend.fill,
    legend_pen: legend.pen,
    legend_position: legend.position,
    legend_bottom: side == "b",
    point_legend,
    numeric_categories: chart_child(
      sources[0],
      if scatter {
        "xVal"
      } else {
        "cat"
      },
    ).child("numRef", uri=chart_uri)
    is Some(_),
  }
}

///|
fn native_inactive_labels(
  source : Ref,
  points~ : Int32 = 0,
) -> Unit raise @failure.Failure {
  let flags = [
    "showLegendKey", "showVal", "showCatName", "showSerName", "showPercent", "showBubbleSize",
  ]
  line_fields(
    source,
    flags +
    ["txPr", "separator", "extLst"] +
    (if points > 0 { ["dLbl"] } else { [] }),
  )
  for flag in flags {
    guard !source.child(flag, uri=chart_uri).map(line_boolean).unwrap_or(false) else {
      @failure.reject(
        "unsupported-chart", "Native chart labels require support",
      )
    }
  }
  let seen = Set([])
  for node in source.tree.all(source.node.id, "dLbl", uri=chart_uri) {
    let point : Ref = { tree: source.tree, node, }
    line_fields(point, flags + ["idx", "txPr", "separator"])
    let identity = chart_child(point, "idx")
    line_fields(identity, [], attributes=["val"])
    let index = number(
      identity.node.attribute("val").unwrap_or(""),
      0,
      (points - 1).to_double(),
    )
    guard index == index.floor() && !seen.contains(index.to_int()) else {
      @failure.reject(
        "unsupported-chart", "Invalid inactive native point label identity",
      )
    }
    seen.add(index.to_int())
    for flag in flags {
      guard !point.child(flag, uri=chart_uri).map(line_boolean).unwrap_or(false) else {
        @failure.reject(
          "unsupported-chart", "Visible native point labels require support",
        )
      }
    }
  }
  if source.child("extLst", uri=chart_uri) is Some(extensions) {
    line_fields(extensions, ["ext"])
    let extension = chart_child(extensions, "ext")
    guard extension.node.attribute("uri") ==
      Some("{CE6537A1-D6FC-4f65-9D91-7224C49458BB}") else {
      @failure.reject(
        "unsupported-chart", "Unknown native chart label extension",
      )
    }
    let uri = "http://schemas.microsoft.com/office/drawing/2012/chart"
    line_fields(extension, ["showLeaderLines"], attributes=["uri"], uri~)
    if extension.child("showLeaderLines", uri~) is Some(flag) {
      ignore(line_boolean(flag))
    }
  }
}
