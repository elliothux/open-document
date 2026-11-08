///|
fn circular_split_inactive_labels(
  source : Ref,
  count : Int32,
) -> Unit raise @failure.Failure {
  let flags = [
    "showLegendKey", "showVal", "showCatName", "showSerName", "showPercent", "showBubbleSize",
  ]
  let fields = flags + ["txPr", "separator"]
  line_fields(source, fields + ["dLbl", "showLeaderLines", "leaderLines"])
  let points = source.tree.all(source.node.id, "dLbl", uri=chart_uri)
  let seen : Set[Int32] = Set([])
  for node in points {
    let point : Ref = { tree: source.tree, node, }
    line_fields(point, fields + ["idx"])
    let index = chart_child(point, "idx")
    line_fields(index, [], attributes=["val"])
    let value = number(
      index.node.attribute("val").unwrap_or(""),
      0,
      (count - 1).to_double(),
    )
    guard value == value.floor() && !seen.contains(value.to_int()) else {
      @failure.reject(
        "unsupported-chart", "Invalid inactive split-pie label index",
      )
    }
    seen.add(value.to_int())
  }
  for
    label in [
      source,
      ..points.map(node => ({ tree: source.tree, node, } : Ref)),
    ] {
    for flag in flags {
      guard !circular_bool(label.child(flag, uri=chart_uri)) else {
        @failure.reject("unsupported-chart", "Split-pie labels require support")
      }
    }
  }
}

///|
fn validate_circular_split(
  source : Ref,
  count : Int32,
) -> Unit raise @failure.Failure {
  let value = fn(
    name : String,
    low : Double,
    high : Double,
    default : String,
  ) raise @failure.Failure {
    let raw = source
      .child(name, uri=chart_uri)
      .bind(child => {
        line_fields(child, [], attributes=["val"])
        child.node.attribute("val")
      })
    let value = line_real(raw.unwrap_or(default), low, high)
    guard name == "splitPos" || value == value.floor() else {
      @failure.reject("unsupported-chart", "Split-pie sizes must be integers")
    }
    value
  }
  let kind = chart_child(source, "ofPieType")
  line_fields(kind, [], attributes=["val"])
  let kind = kind.node.attribute("val").unwrap_or("")
  guard ["pie", "bar"].contains(kind) else {
    @failure.reject("unsupported-chart", "Unknown secondary pie chart type")
  }
  let split_type = source
    .child("splitType", uri=chart_uri)
    .bind(split => {
      line_fields(split, [], attributes=["val"])
      split.node.attribute("val")
    })
    .unwrap_or("auto")
  guard split_type == "cust" || source.child("custSplit", uri=chart_uri) is None else {
    @failure.reject("unsupported-chart", "Conflicting split-pie rules")
  }
  match split_type {
    "val" => ignore(value("splitPos", -1.0e300, 1.0e300, ""))
    "percent" => ignore(value("splitPos", 0, 100, ""))
    "pos" | "auto" => {
      let length = if split_type == "pos" {
        value("splitPos", 0, 32000, "")
      } else {
        guard source.child("splitPos", uri=chart_uri) is None else {
          @failure.reject("unsupported-chart", "Conflicting split-pie rules")
        }
        2.0
      }
      guard length == length.floor() else {
        @failure.reject(
          "unsupported-chart", "Positional split count must be an integer",
        )
      }
    }
    "cust" => {
      guard source.child("splitPos", uri=chart_uri) is None else {
        @failure.reject("unsupported-chart", "Conflicting split-pie rules")
      }
      let custom = chart_child(source, "custSplit")
      line_fields(custom, ["secondPiePt"])
      let seen : Set[Int32] = Set([])
      let members = custom.tree
        .all(custom.node.id, "secondPiePt", uri=chart_uri)
        .map(node => {
          let point : Ref = { tree: custom.tree, node, }
          line_fields(point, [], attributes=["val"])
          let value = number(
            node.attribute("val").unwrap_or(""),
            0,
            (count - 1).to_double(),
          )
          guard value == value.floor() else {
            @failure.reject(
              "unsupported-chart", "Secondary pie point must be an integer",
            )
          }
          let index = value.to_int()
          guard !seen.contains(index) else {
            @failure.reject(
              "unsupported-chart", "Duplicate secondary pie point",
            )
          }
          seen.add(index)
          index
        })
      guard !members.is_empty() && members.length() < count else {
        @failure.reject(
          "unsupported-chart", "Custom split requires both pie groups",
        )
      }
    }
    _ => @failure.reject("unsupported-chart", "Split-pie rule requires support")
  }
  if source.child("serLines", uri=chart_uri) is Some(lines) {
    line_fields(lines, ["spPr"])
    let (fill, _, _) = line_paint_box(chart_child(lines, "spPr"))
    guard fill.is_empty() else {
      @failure.reject(
        "unsupported-chart", "Series lines cannot fill a split chart",
      )
    }
  }
  ignore(value("gapWidth", 0, 500, "100"))
  ignore(value("secondPieSize", 5, 200, "75"))
}
