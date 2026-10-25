///|
fn table_style_fill(
  theme : Theme,
  layers : Array[TableStylePart],
) -> (String, Double)? raise @failure.Failure {
  for layer in layers {
    guard layer.source.child("tcStyle") is Some(style) else { continue }
    if style.child("fill") is Some(fill) {
      fill.table_children(["noFill", "solidFill"])
      table_profile(
        fill.node.attributes.is_empty() &&
        fill.tree.children.get(fill.node.id).unwrap_or([]).length() == 1,
        "Invalid table style fill",
      )
      return Some(fill_rgba(theme, [fill]))
    }
    if style.child("fillRef") is Some(reference) {
      guard theme_reference(theme, reference, "fill")
        is Some((fill, placeholder)) else {
        return Some(("", 1))
      }
      table_profile(
        ["solidFill", "noFill"].contains(fill.node.name),
        "Unsupported theme table fill",
      )
      return Some(
        if fill.node.name == "noFill" {
          ("", 1)
        } else {
          color_rgba(theme, fill, placeholder=Some(placeholder))
        },
      )
    }
  }
  None
}

///|
fn table_style_line(
  theme : Theme,
  container : Ref,
) -> (Ref, Ref?)? raise @failure.Failure {
  container.table_children(["ln", "lnRef"])
  table_profile(
    container.node.attributes.is_empty() &&
    container.tree.children.get(container.node.id).unwrap_or([]).length() == 1,
    "Invalid table style border",
  )
  let (line, placeholder) = if container.child("ln") is Some(line) {
    (line, None)
  } else if container
    .child("lnRef")
    .bind(reference => theme_reference(theme, reference, "ln"))
    is Some((line, reference)) {
    (line, Some(reference))
  } else {
    return None
  }
  Some((line, placeholder))
}

///|
fn table_style_border(
  theme : Theme,
  container : Ref,
) -> (String, Double, String, Double) raise @failure.Failure {
  guard table_style_line(theme, container) is Some((line, placeholder)) else {
    return ("", 0, "solid", 1)
  }
  line.table_children([
    "noFill", "solidFill", "prstDash", "round", "bevel", "miter",
  ])
  table_profile(
    line.node.attributes.all(a => {
      a.uri.is_empty() &&
      (
        a.name == "w" ||
        (a.name == "cap" && a.value == "flat") ||
        (a.name == "cmpd" && a.value == "sng") ||
        (a.name == "algn" && a.value == "ctr")
      )
    }),
    "Unsupported table style line",
  )
  let dash = line_dash([line])
  let (color, alpha) = fill_rgba(theme, [line], placeholder~)
  (
    color,
    if color.is_empty() {
      0
    } else {
      number(line.node.attribute("w").unwrap_or("12700"), 1, 12700000) / 12700
    },
    dash,
    alpha,
  )
}

///|
fn table_style_borders(
  theme : Theme,
  layers : Array[TableStylePart],
  row : Int,
  column : Int,
  rows : Int,
  columns : Int,
  row_span : Int,
  column_span : Int,
) -> (Array[(String, Double, String, Double)], Array[Int], Array[(Ref, Ref?)?]) raise @failure.Failure {
  let borders : Array[(String, Double, String, Double)] = []
  let priorities : Array[Int] = []
  let sources : Array[(Ref, Ref?)?] = []
  for
    (side, inside, boundary) in [
      ("left", "insideV", column == 0),
      ("top", "insideH", row == 0),
      ("right", "insideV", column + column_span == columns),
      ("bottom", "insideH", row + row_span == rows),
    ] {
    let found = for layer in layers {
      guard layer.source.child("tcStyle").bind(style => style.child("tcBdr"))
        is Some(edges) else {
        continue
      }
      edges.table_children([
        "left", "top", "right", "bottom", "insideH", "insideV",
      ])
      let name = if layer.source.node.name == "wholeTbl" && !boundary {
        inside
      } else {
        side
      }
      if edges.child(name) is Some(edge) {
        break Some(
          (
            table_style_border(theme, edge),
            table_style_regions.search(layer.source.node.name).unwrap_or(0) + 1,
            table_style_line(theme, edge).bind(pair => {
              solid_fill_source([pair.0]).map(fill => (fill, pair.1))
            }),
          ),
        )
      }
    } nobreak {
      None
    }
    let (value, priority, source) = found.unwrap_or(
      (("", 0, "solid", 1), 0, None),
    )
    borders.push(value)
    priorities.push(priority)
    sources.push(source)
  }
  (borders, priorities, sources)
}
