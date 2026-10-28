///|
/// Border source properties; a theme slot overrides the input RGB when present.
pub(all) struct TableBorderStyle {
  style : String
  width : Double
  color : String
  themeColor : String?
}

///|
fn Session::set_table_borders(
  self : Session,
  revision : Int32,
  selection : Selection,
  value : Map[String, TableBorderStyle?],
  whole_table~ : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard !value.is_empty() else {
    @failure.reject("invalid-operation", "Border changes are empty")
  }
  for side, border in value {
    guard ["top", "left", "bottom", "right"].contains(side) ||
      (whole_table && ["insideH", "insideV"].contains(side)) else {
      @failure.reject("invalid-operation", "Unknown border side")
    }
    if border is Some(border) {
      guard [
          "single", "double", "dashed", "dotted", "dashSmallGap", "dotDash", "dotDotDash",
        ].contains(border.style) &&
        (border.width == 0 || border.width >= 0.25) &&
        border.width <= 12 &&
        border.width * 8 == (border.width * 8).round() &&
        border.color.length() == 6 &&
        border.color.iter().all(c => c.is_ascii_hexdigit()) else {
        @failure.reject(
          "invalid-operation", "Borders require RGB and 0 or 0.25..12pt eighth-point widths",
        )
      }
      if border.themeColor is Some(slot) {
        guard border.width > 0 &&
          [
            "dark1", "light1", "dark2", "light2", "accent1", "accent2", "accent3",
            "accent4", "accent5", "accent6", "hyperlink", "followedHyperlink", "text1",
            "text2", "background1", "background2",
          ].contains(slot) else {
          @failure.reject(
            "invalid-operation", "Invalid table border theme slot",
          )
        }
      }
    }
  }
  self.change_table_property(
    revision,
    selection,
    if whole_table {
      "tblBorders"
    } else {
      "tcBorders"
    },
    None,
    whole_table~,
    border_patch=Some(value),
  )
}

///|
fn WordTree::border_markup(
  self : WordTree,
  document : @xml.Document,
  owner : Int32,
  name : String,
  patch : Map[String, TableBorderStyle?],
  themes : Map[String, String],
) -> String raise @failure.Failure {
  let properties = self.child(
    owner,
    if name == "tblBorders" {
      "tblPr"
    } else {
      "tcPr"
    },
  )
  let stored : Map[String, Int32] = Map([])
  let current = properties
    .map(props => self.read_borders(props, name, Some(themes)))
    .unwrap_or(Map([]))
  if properties is Some(properties) {
    if self.child(properties, name) is Some(borders) {
      for id in self.children[borders] {
        stored[match self.nodes[id].name {
          "start" => "left"
          "end" => "right"
          side => side
        }] = id
      }
    }
  }
  if patch
    .iter()
    .all(entry => {
      let (side, value) = entry
      match (current.get(side), value) {
        (None, None) => true
        (Some(a), Some(b)) =>
          stored
          .get(side)
          .bind(id => self.nodes[id].attribute("themeColor", uri=word_uri))
          .filter(slot => slot != "none")
          .map(word_theme_color_name) ==
          b.themeColor &&
          a.width == b.width &&
          (
            a.width == 0 ||
            (
              a.style == b.style &&
              (b.themeColor is Some(_) || a.color == b.color.to_lower())
            )
          )
        _ => false
      }
    }) {
    return properties
      .bind(props => self.child(props, name))
      .map(id => {
        let node = self.nodes[id]
        document.source()[node.start:node.end].to_owned()
      })
      .unwrap_or("")
  }
  let out = StringBuilder()
  for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
    if patch.get(side) is Some(value) {
      if value is Some(value) {
        out.write_string(
          if value.width == 0 {
            "<od:\{side} od:val=\"nil\"/>"
          } else {
            let attributes = StringBuilder()
            let original = stored.get(side)
            let previous = original
              .bind(id => self.nodes[id].attribute("themeColor", uri=word_uri))
              .filter(slot => slot != "none")
              .map(word_theme_color_name)
            if value.themeColor is Some(slot) && previous == Some(slot) {
              // Keep imported tint, shade and cache when the binding is unchanged.
              for field in ["color", "themeColor", "themeTint", "themeShade"] {
                if original.bind(id => {
                    self.nodes[id].attribute(field, uri=word_uri)
                  })
                  is Some(text) {
                  attributes.write_string(
                    " od:\{field}=\"\{property_attribute(text)}\"",
                  )
                }
              }
            } else {
              let color = value.themeColor
                .map(slot => {
                  themes
                  .get(theme_color_name(slot))
                  .unwrap_or_else(() => {
                    @failure.reject(
                      "protected-content",
                      "Missing or unsupported theme color: " + slot,
                    )
                  })
                })
                .unwrap_or(value.color)
                .to_lower()
              attributes.write_string(" od:color=\"\{color}\"")
              if value.themeColor is Some(slot) {
                attributes.write_string(" od:themeColor=\"\{slot}\"")
              }
            }
            "<od:\{side} od:val=\"\{value.style}\" od:sz=\"\{(value.width * 8).to_int()}\"\{attributes.to_string()}/>"
          },
        )
      }
    } else if stored.get(side) is Some(id) {
      out.write_string(self.standalone_markup(document, id))
    }
  }
  let inner = out.to_string()
  if inner.is_empty() {
    ""
  } else {
    "<od:\{name} xmlns:od=\"\{word_uri}\">\{inner}</od:\{name}>"
  }
}

///|
fn cell_border_query(
  table : @layout.Table,
  row : Int32,
  cell : Int32,
) -> Map[String, Json] {
  let start = table.columnSpans[row][:cell].fold(init=0, (sum, n) => sum + n)
  let end = start + table.columnSpans[row][cell]
  let mut first = row
  let mut count = table.rowSpans[row][cell]
  for r = row; r >= 0 && count == 0; r = r - 1 {
    let mut column = 0
    for c, span in table.columnSpans[r] {
      if column == start &&
        column + span == end &&
        table.rowSpans[r][c] > row - r {
        first = r
        count = table.rowSpans[r][c]
        break
      }
      column += span
    }
  }
  let last = first + count
  fn common(values : Array[@layout.BorderStyle]) -> Json {
    if values.all(v => v == values[0]) {
      Json(values[0])
    } else {
      Json::null()
    }
  }
  {
    "top": common(table.borders.horizontal[first][start:end].to_owned()),
    "bottom": common(table.borders.horizontal[last][start:end].to_owned()),
    "left": common(
      table.borders.vertical[first:last].map(edges => edges[start]),
    ),
    "right": common(table.borders.vertical[first:last].map(edges => edges[end])),
  }
}
