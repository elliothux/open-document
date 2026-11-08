///|
priv struct NativeColumn {
  fill : String
  gap : Double
  order : Int32
  points : Map[Int32, (String, (String, Double))]
}

///|
fn read_native_column(
  source : Ref,
  fill : String,
  pen : (String, Double),
  gap : Double,
  count : Int32,
) -> NativeColumn raise @failure.Failure {
  let points : Map[Int32, (String, (String, Double))] = Map([])
  for node in source.tree.all(source.node.id, "dPt", uri=chart_uri) {
    let point : Ref = { tree: source.tree, node, }
    line_fields(point, ["idx", "spPr"])
    let index = chart_child(point, "idx")
    line_fields(index, [], attributes=["val"])
    let index = number(
      index.node.attribute("val").unwrap_or(""),
      0,
      (count - 1).to_double(),
    )
    guard index == index.floor() && !points.contains(index.to_int()) else {
      @failure.reject(
        "unsupported-chart", "Duplicate or invalid column point style",
      )
    }
    points[index.to_int()] = point
      .child("spPr", uri=chart_uri)
      .map(properties => {
        let (point_fill, point_pen, dash) = line_paint_box(properties)
        guard dash.is_empty() else {
          @failure.reject(
            "unsupported-chart", "Dashed column outlines require support",
          )
        }
        (
          if properties.child("solidFill") is Some(_) ||
            properties.child("noFill") is Some(_) {
            point_fill
          } else {
            fill
          },
          if properties.child("ln") is Some(_) {
            point_pen
          } else {
            pen
          },
        )
      })
      .unwrap_or((fill, pen))
  }
  {
    fill,
    gap,
    order: number(
      chart_child(source, "order").node.attribute("val").unwrap_or(""),
      0,
      31,
    ).to_int(),
    points,
  }
}

///|
fn line_columns(
  out : Array[@layout.PositionedPrimitive],
  data : @layout.ChartData,
  styles : Array[NativeLineCurve],
  ranges : Array[(Double, Double, Double)],
  plot : @layout.Border,
) -> Unit {
  let slot = plot.width / data.categories.length().to_double()
  for axis, (low, high, _) in ranges {
    let columns = styles
      .mapi((i, curve) => (i, curve))
      .filter_map(pair => {
        if pair.1.axis == axis && pair.1.column is Some(_) {
          Some(pair.0)
        } else {
          None
        }
      })
    if columns.is_empty() {
      continue
    }
    let width = slot /
      (columns.length().to_double() + styles[columns[0]].column.unwrap().gap)
    let y = fn(value : Double) {
      plot.y + plot.height * (1.0 - (value - low) / (high - low)).max(0).min(1)
    }
    let ordered = columns.mapi((ordinal, index) => (ordinal, index))
    ordered.sort_by((a, b) => {
      styles[a.1].column.unwrap().order - styles[b.1].column.unwrap().order
    })
    // Native columns retain source cluster positions while painting by series order.
    for (ordinal, index) in ordered {
      let curve = styles[index]
      let column = curve.column.unwrap()
      for i, value in data.series[index].values {
        guard value is Some(value) else { continue }
        let x = plot.x +
          i.to_double() * slot +
          width * (column.gap / 2 + ordinal.to_double())
        let (fill, pen) = column.points
          .get(i)
          .unwrap_or((column.fill, (curve.paint.color, curve.paint.width)))
        out.push(
          bar_polygon(
            [
              (x, y(0), 0),
              (x, y(value), 0),
              (x + width, y(value), 0),
              (x + width, y(0), 0),
            ],
            fill,
            pen,
          ),
        )
      }
    }
  }
}
