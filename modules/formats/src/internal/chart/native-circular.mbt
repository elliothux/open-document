///|
priv struct CircularLabels {
  text : @layout.TextStyle
  position : String
  category : Bool
  series : Bool
  value : Bool
  percent : Bool
  separator : String
  leader : (String, Double)?
} derive(ToJson)

///|
priv struct CircularPoint {
  fill : CircularFill
  explicit_fill : Bool
  pen : (String, Double)
  join : Int32
  explosion : Double
  legend_fill : String
}

///|
struct CircularSeries {
  points : Array[CircularPoint]
  labels : CircularLabels?
  explosion : Double
}

///|
pub struct NativeCircular {
  frame_fill : CircularFill
  frame_pen : (String, Double)
  frame_join : Int32
  frame_default_fill : Bool
  frame_default_pen : Bool
  plot_fill : CircularFill
  plot_pen : (String, Double)
  plot_join : Int32
  title : (String, @layout.TextStyle)?
  legend : NativeLegend?
  first_angle : Double
  series : Array[CircularSeries]
}

///|
fn circular_text_style(style : @layout.TextStyle) -> @layout.TextStyle {
  // The native DrawingML importer rounds circular chart text to half-point sizes.
  { ..style, size: (style.size * 2).round() / 2, }
}

///|
fn circular_label_style(
  source : Ref,
  doughnut : Bool,
  point~ : Bool = false,
) -> CircularLabels raise @failure.Failure {
  line_fields(
    source,
    [
      "txPr", "dLblPos", "showLegendKey", "showVal", "showCatName", "showSerName",
      "showPercent", "showBubbleSize", "separator", "numFmt",
    ] +
    (if point { ["idx"] } else { ["dLbl", "showLeaderLines", "leaderLines"] }),
  )
  if source.child("numFmt", uri=chart_uri) is Some(format) {
    line_fields(format, [], attributes=["formatCode", "sourceLinked"])
    guard format.node.attribute("formatCode") == Some("General") &&
      ["1", "true"].contains(
        format.node.attribute("sourceLinked").unwrap_or("1"),
      ) else {
      @failure.reject(
        "unsupported-chart", "Native circular label format requires support",
      )
    }
  }
  let position = source
    .child("dLblPos", uri=chart_uri)
    .map(label => {
      line_fields(label, [], attributes=["val"])
      label.node.attribute("val").unwrap_or("")
    })
    .unwrap_or(if doughnut { "ctr" } else { "bestFit" })
  guard ["ctr", "inBase", "inEnd", "outEnd", "bestFit"].contains(position) &&
    (!doughnut || ["ctr", "inBase"].contains(position)) &&
    !circular_bool(source.child("showBubbleSize", uri=chart_uri)) else {
    @failure.reject(
      "unsupported-chart", "Native circular label placement requires support",
    )
  }
  // The native circular label content contains text only, including with showLegendKey.
  ignore(circular_bool(source.child("showLegendKey", uri=chart_uri)))
  let separator = source
    .child("separator", uri=chart_uri)
    .map(separator => {
      line_fields(separator, [])
      guard separator.node.text.length() <= 32 &&
        !separator.node.text.contains("\n") &&
        !separator.node.text.contains("\r") else {
        @failure.reject(
          "unsupported-chart", "Native label separator exceeds text limits",
        )
      }
      separator.node.text
    })
    .map(value => value + " ")
    .unwrap_or(
      if circular_bool(source.child("showCatName", uri=chart_uri)) &&
        circular_bool(source.child("showPercent", uri=chart_uri)) &&
        !circular_bool(source.child("showSerName", uri=chart_uri)) &&
        !circular_bool(source.child("showVal", uri=chart_uri)) {
        "\n"
      } else {
        ", "
      },
    )
  {
    text: circular_text_style(line_text(chart_child(source, "txPr"))),
    position,
    category: circular_bool(source.child("showCatName", uri=chart_uri)),
    series: circular_bool(source.child("showSerName", uri=chart_uri)),
    value: circular_bool(source.child("showVal", uri=chart_uri)),
    percent: circular_bool(source.child("showPercent", uri=chart_uri)),
    separator,
    leader: None,
  }
}

///|
fn circular_labels(
  source : Ref,
  doughnut : Bool,
  count : Int32,
) -> CircularLabels raise @failure.Failure {
  let style = circular_label_style(source, doughnut)
  let leaders = circular_bool(source.child("showLeaderLines", uri=chart_uri))
  let pen = source
    .child("leaderLines", uri=chart_uri)
    .map(lines => {
      line_fields(lines, ["spPr"])
      let paint = chart_child(lines, "spPr")
      line_fields(paint, ["ln"], uri=drawing_uri)
      line_pen(line_child(paint, "ln"), round_join=true)
    })
    .unwrap_or(("000000", 0))
  // Some producers serialize the series label style again for each point.
  let indices : Set[Int32] = Set([])
  let expected = Json(style)
  let legend_key = circular_bool(source.child("showLegendKey", uri=chart_uri))
  for node in source.tree.all(source.node.id, "dLbl", uri=chart_uri) {
    let label : Ref = { tree: source.tree, node, }
    let index = chart_child(label, "idx")
    line_fields(index, [], attributes=["val"])
    let i = number(
      index.node.attribute("val").unwrap_or(""),
      0,
      (count - 1).to_double(),
    ).to_int()
    guard !indices.contains(i) &&
      Json(circular_label_style(label, doughnut, point=true)) == expected &&
      circular_bool(label.child("showLegendKey", uri=chart_uri)) == legend_key else {
      @failure.reject(
        "unsupported-chart", "Native circular label override requires support",
      )
    }
    indices.add(i)
  }
  { ..style, leader: if leaders { Some(pen) } else { None }, }
}

///|
fn read_circular_worksheet(
  part : String,
  document : @xml.Document,
) -> WorksheetChart raise @failure.Failure {
  let (root, data) = read_chart(part, document, worksheet=true, native=true)
  guard ["pie", "doughnut"].contains(data.kind) else {
    @failure.reject("unsupported-chart", "Expected a native circular chart")
  }
  guard !data.categories.is_empty() &&
    (data.kind != "pie" || data.series.length() == 1) &&
    data.series.all(series => series.values.length() == data.categories.length()) else {
    @failure.reject(
      "unsupported-chart", "Native circular caches require aligned points and one pie series",
    )
  }
  line_fields(root, ["lang", "roundedCorners", "chart", "spPr", "printSettings"])
  if root.child("lang", uri=chart_uri) is Some(language) {
    line_fields(language, [], attributes=["val"])
  }
  if root.child("roundedCorners", uri=chart_uri) is Some(rounded) {
    native_flag(rounded, "0")
  }
  if root.child("printSettings", uri=chart_uri) is Some(settings) {
    line_fields(settings, ["headerFooter", "pageMargins", "pageSetup"])
    for name in ["headerFooter", "pageSetup"] {
      if settings.child(name, uri=chart_uri) is Some(child) {
        line_fields(child, [])
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
    "title", "autoTitleDeleted", "plotArea", "legend", "plotVisOnly", "dispBlanksAs",
  ])
  ignore(circular_bool(chart.child("autoTitleDeleted", uri=chart_uri)))
  guard circular_bool(chart.child("plotVisOnly", uri=chart_uri), default=true) else {
    @failure.reject(
      "unsupported-chart", "Hidden native chart values require support",
    )
  }
  if chart.child("dispBlanksAs", uri=chart_uri) is Some(blanks) {
    native_flag(blanks, "zero")
  }
  let plot = chart_child(chart, "plotArea")
  let name = if plot.child("ofPieChart", uri=chart_uri) is Some(_) {
    "ofPieChart"
  } else if data.kind == "pie" {
    "pieChart"
  } else {
    "doughnutChart"
  }
  line_fields(plot, ["layout", name, "spPr"])
  if plot.child("layout", uri=chart_uri) is Some(layout) {
    line_fields(layout, [])
  }
  let source = chart_child(plot, name)
  line_fields(
    source,
    if name == "ofPieChart" {
      [
        "ofPieType", "varyColors", "ser", "gapWidth", "splitType", "splitPos", "custSplit",
        "secondPieSize", "serLines",
      ]
    } else {
      ["varyColors", "ser", "dLbls", "firstSliceAng", "holeSize"]
    },
  )
  let of_pie = name == "ofPieChart"
  if of_pie {
    validate_circular_split(source, data.categories.length())
  }
  guard circular_bool(source.child("varyColors", uri=chart_uri), default=true) else {
    @failure.reject(
      "unsupported-chart", "Native circular palette requires point colors",
    )
  }
  let first_angle = source
    .child("firstSliceAng", uri=chart_uri)
    .map(angle => {
      line_fields(angle, [], attributes=["val"])
      number(angle.node.attribute("val").unwrap_or(""), 0, 360)
    })
    .unwrap_or(0)
  if source.child("holeSize", uri=chart_uri) is Some(hole) {
    line_fields(hole, [], attributes=["val"])
    guard data.kind == "doughnut" else {
      @failure.reject("unsupported-chart", "Pie chart cannot have a hole")
    }
  }
  let global_labels = source
    .child("dLbls", uri=chart_uri)
    .map(labels => {
      circular_labels(labels, data.kind == "doughnut", data.categories.length())
    })
  let names : Array[String] = []
  let values : Array[String] = []
  let categories : Array[String] = []
  let identities : Map[String, Bool] = Map([])
  let series = source.tree
    .all(source.node.id, "ser", uri=chart_uri)
    .mapi((index, node) => {
      let series : Ref = { tree: source.tree, node, }
      line_fields(series, [
        "idx", "order", "tx", "spPr", "explosion", "dPt", "dLbls", "cat", "val",
      ])
      for name in ["idx", "order"] {
        let id = chart_child(series, name)
        line_fields(id, [], attributes=["val"])
        let value = number(
          id.node.attribute("val").unwrap_or(""),
          0,
          4294967295,
        )
        if name == "idx" {
          guard !identities.contains(value.to_string()) else {
            @failure.reject(
              "unsupported-chart", "Duplicate native circular series identity",
            )
          }
          identities[value.to_string()] = true
        }
        if name == "order" && value != index.to_double() {
          @failure.reject(
            "unsupported-chart", "Native circular series order requires support",
          )
        }
      }
      names.push(
        series
        .child("tx", uri=chart_uri)
        .map(title => {
          line_cache(title, false)
          chart_child(chart_child(title, "strRef"), "f").node.text
        })
        .unwrap_or(""),
      )
      let value = chart_child(series, "val")
      line_cache(value, true)
      values.push(chart_child(chart_child(value, "numRef"), "f").node.text)
      categories.push(
        series
        .child("cat", uri=chart_uri)
        .map(category => {
          let numeric = category.child("numRef", uri=chart_uri) is Some(_)
          line_cache(category, numeric)
          chart_child(
            chart_child(category, if numeric { "numRef" } else { "strRef" }),
            "f",
          ).node.text
        })
        .unwrap_or(""),
      )
      let properties = chart_child(series, "spPr")
      let (fill, pen, join) = circular_box(properties, shadows=true)
      guard fill is Some(fill) else {
        @failure.reject(
          "unsupported-chart", "Native circular series requires an explicit fill",
        )
      }
      let explosion = series
        .child("explosion", uri=chart_uri)
        .map(circular_explosion)
        .unwrap_or(0)
      let base : CircularPoint = {
        fill,
        explicit_fill: false,
        pen: pen.unwrap_or(("", 0)),
        join,
        explosion,
        legend_fill: "",
      }
      let points = Array::make(data.series[index].values.length(), base)
      let seen : Map[Int32, Bool] = Map([])
      for node in series.tree.all(series.node.id, "dPt", uri=chart_uri) {
        let point : Ref = { tree: series.tree, node, }
        line_fields(point, ["idx", "spPr", "explosion"])
        let id = chart_child(point, "idx")
        line_fields(id, [], attributes=["val"])
        let i = number(
          id.node.attribute("val").unwrap_or(""),
          0,
          (points.length() - 1).to_double(),
        ).to_int()
        guard !seen.contains(i) else {
          @failure.reject(
            "unsupported-chart", "Duplicate native circular point",
          )
        }
        seen[i] = true
        let properties = point.child("spPr", uri=chart_uri)
        let (fill, pen, join) = properties
          .map(properties => circular_box(properties, shadows=true))
          .unwrap_or((None, None, 0))
        points[i] = {
          fill: fill.unwrap_or(base.fill),
          explicit_fill: fill is Some(_),
          pen: pen.unwrap_or(base.pen),
          join: if pen is None {
            base.join
          } else {
            join
          },
          legend_fill: "",
          explosion: point
          .child("explosion", uri=chart_uri)
          .map(circular_explosion)
          .unwrap_or(explosion),
        }
      }
      let labels = series
        .child("dLbls", uri=chart_uri)
        .map(labels => {
          if of_pie {
            circular_split_inactive_labels(labels, points.length())
            None
          } else {
            Some(
              circular_labels(labels, data.kind == "doughnut", points.length()),
            )
          }
        })
      { points, explosion, labels: labels.unwrap_or(global_labels), }
    })
  guard categories.all(value => value == categories[0]) else {
    @failure.reject(
      "unsupported-chart", "Native circular series require a common category source",
    )
  }
  if of_pie {
    guard series.all(s => {
      s.labels is None &&
      s.explosion == 0 &&
      s.points.all(p => p.explosion == 0)
    }) else {
      @failure.reject(
        "unsupported-chart", "Split-pie labels and explosion require support",
      )
    }
  }
  let (frame_fill, frame_pen, frame_join) = root
    .child("spPr", uri=chart_uri)
    .map(properties => circular_box(properties))
    .unwrap_or((None, None, 0))
  let (plot_fill, plot_pen, plot_join) = plot
    .child("spPr", uri=chart_uri)
    .map(properties => circular_box(properties))
    .unwrap_or((None, None, 0))
  let title = chart
    .child("title", uri=chart_uri)
    .map(title => {
      let (text, style) = if of_pie && title.child("tx", uri=chart_uri) is None {
        line_fields(title, ["layout"])
        line_fields(chart_child(title, "layout"), [])
        (
          data.series[0].name,
          {
            ..@layout.TextStyle::new("Arial|bold", 18, "000000"),
            fontLeading: true,
            kerning: "none",
          },
        )
      } else {
        native_title(title, true)
      }
      (text, circular_text_style(style))
    })
  {
    data: { ..data, title: title.map(title => title.0).unwrap_or(""), },
    categories: categories[0],
    names,
    values,
    colors: [],
    native_line: None,
    native_bar: None,
    native_surface: None,
    native_radar: None,
    native_area: None,
    native_bubble: None,
    native_circular: Some({
      frame_fill: frame_fill.unwrap_or(Solid("ffffff")),
      frame_pen: frame_pen.unwrap_or(("898989", 0.75)),
      frame_join,
      frame_default_fill: frame_fill is None,
      frame_default_pen: frame_pen is None,
      plot_fill: plot_fill.unwrap_or(Empty),
      plot_pen: plot_pen.unwrap_or(("", 0)),
      plot_join,
      title,
      legend: chart
      .child("legend", uri=chart_uri)
      .map(legend => {
        let legend = native_legend(legend, round_join=true)
        { ..legend, text: circular_text_style(legend.text), }
      }),
      first_angle,
      series,
    }),
  }
}

///|
fn circular_explosion(source : Ref) -> Double raise @failure.Failure {
  line_fields(source, [], attributes=["val"])
  number(source.node.attribute("val").unwrap_or(""), 0, 400)
}
