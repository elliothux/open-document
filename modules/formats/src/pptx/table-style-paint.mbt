///|
fn table_style_fill(
  theme : Theme,
  layers : Array[TableStylePart],
) -> (String, Double, (Ref, Ref?)?)? raise @failure.Failure {
  for layer in layers {
    guard layer.source.child("tcStyle") is Some(style) else { continue }
    if style.child("fill") is Some(fill) {
      fill.table_children(["noFill", "solidFill"])
      table_profile(
        fill.node.attributes.is_empty() &&
        fill.tree.children.get(fill.node.id).unwrap_or([]).length() == 1,
        "Invalid table style fill",
      )
      let (color, alpha) = fill_rgba(theme, [fill])
      return Some(
        (color, alpha, solid_fill_source([fill]).map(source => (source, None))),
      )
    }
    if style.child("fillRef") is Some(reference) {
      guard theme_reference(theme, reference, "fill")
        is Some((fill, placeholder)) else {
        return Some(("", 1, None))
      }
      table_profile(
        ["solidFill", "noFill"].contains(fill.node.name),
        "Unsupported theme table fill",
      )
      return Some(
        if fill.node.name == "noFill" {
          ("", 1, None)
        } else {
          let (color, alpha) = color_rgba(
            theme,
            fill,
            placeholder=Some(placeholder),
          )
          (color, alpha, Some((fill, Some(placeholder))))
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
fn Ref::table_pen(self : Ref) -> Unit raise @failure.Failure {
  self.table_children([
    "noFill", "solidFill", "prstDash", "round", "bevel", "miter", "headEnd", "tailEnd",
  ])
  table_profile(
    self.node.text.trim().is_empty() &&
    self.node.attributes.all(a => {
      a.uri.is_empty() &&
      (
        a.name == "w" ||
        (a.name == "cap" && a.value == "flat") ||
        (a.name == "cmpd" && a.value == "sng") ||
        (a.name == "algn" && a.value == "ctr")
      )
    }),
    "Unsupported table cell pen",
  )
  // Shared table edges are straight paths; a join does not change their paint.
  ignore(join_override(self))
  for name in ["headEnd", "tailEnd"] {
    let ends = self.tree.children
      .get(self.node.id)
      .unwrap_or([])
      .filter(n => n.uri == drawing_uri && n.name == name)
    table_profile(ends.length() <= 1, "Duplicate table border end")
    for end in ends {
      table_profile(
        end.text.trim().is_empty() &&
        self.tree.children.get(end.id).unwrap_or([]).is_empty() &&
        end.attributes.all(a => {
          a.uri.is_empty() &&
          (
            (a.name == "type" && a.value == "none") ||
            (
              ["w", "len"].contains(a.name) &&
              ["sm", "med", "lg"].contains(a.value)
            )
          )
        }),
        "Unsupported table border end",
      )
    }
  }
}

///|
fn table_style_border(
  theme : Theme,
  container : Ref,
) -> (String, Double, String, Double) raise @failure.Failure {
  guard table_style_line(theme, container) is Some((line, placeholder)) else {
    return ("", 0, "solid", 1)
  }
  line.table_pen()
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
  unstyled : Bool,
  row : Int32,
  column : Int32,
  rows : Int32,
  columns : Int32,
  row_span : Int32,
  column_span : Int32,
  rtl : Bool,
) -> (
  Array[(String, Double, String, Double)],
  Array[Int32],
  Array[(Ref, Ref?)?],
) raise @failure.Failure {
  let borders : Array[(String, Double, String, Double)] = []
  let priorities : Array[Int32] = []
  let sources : Array[(Ref, Ref?)?] = []
  for
    (side, inside, boundary) in [
      (
        "left",
        "insideV",
        if rtl {
          column + column_span == columns
        } else {
          column == 0
        },
      ),
      ("top", "insideH", row == 0),
      (
        "right",
        "insideV",
        if rtl {
          column == 0
        } else {
          column + column_span == columns
        },
      ),
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
    // ONLYOFFICE's absent-style table fallback retains a one-point black grid.
    let fallback = if unstyled {
      ("000000", 1.0, "solid", 1.0)
    } else {
      ("", 0.0, "solid", 1.0)
    }
    let (value, priority, source) = found.unwrap_or((fallback, 0, None))
    borders.push(value)
    priorities.push(priority)
    sources.push(source)
  }
  (borders, priorities, sources)
}
