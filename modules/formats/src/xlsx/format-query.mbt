///|
fn CellStyle::format_values(self : CellStyle) -> Map[String, Json] {
  let pieces = self.font.split("|").map(v => v.to_owned()).to_array()
  let result : Map[String, Json] = {
    "family": Json(pieces[0]),
    "size": Json(self.size),
    "bold": Json(pieces.contains("bold")),
    "italic": Json(pieces.contains("italic")),
    "color": Json(self.color),
    "fill": Json(self.fill),
    "horizontal": Json(self.horizontal),
    "vertical": Json(self.vertical),
    "wrap": Json(self.wrap),
    "numberFormat": Json(self.format),
  }
  for i, side in ["left", "right", "top", "bottom"] {
    result[side] = cell_border(self.borders[i]).to_json()
  }
  result
}

///|
fn Session::formatting(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> Json raise @failure.Failure {
  let range = sheet.merge_target(range)
  let reason = self.format_reason(sheet, range)
  let fields = default_style().format_values()
  let fonts : Array[String] = []
  if (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096L {
    let used : Map[Int, Bool] = Map([])
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        used[sheet.style_at({ row, column, })] = true
      }
    }
    for index, id in used.keys().collect() {
      let style = self.styles[id]
      for key, value in style.format_values() {
        if index == 0 {
          fields[key] = value
        } else if fields[key] != value {
          fields[key] = Json::null()
        }
      }
      if !fonts.contains(style.font) {
        fonts.push(style.font)
      }
    }
  } else {
    for key in fields.keys() {
      fields[key] = Json::null()
    }
  }
  if sheet.merges.any(merged => merged == range) {
    let style = self.merged_style(sheet, range)
    for side, name in ["left", "right", "top", "bottom"] {
      fields[name] = cell_border(style.borders[side]).to_json()
    }
  }
  fields["readOnlyReason"] = Json(reason)
  fields["fontKeys"] = Json(fonts)
  Json::object(fields)
}
