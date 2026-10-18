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
    result[side] = self.borders[i].to_json()
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
  let table_styles = self.table_styles(
    sheet,
    {
      remaining: 1048576,
      date1904: self.date1904,
      origin: self.focus,
      names: self.formula_names(),
    },
    self.parts,
  )
  let fields = default_style().format_values()
  let fonts : Array[String] = []
  if (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096L {
    let mut index = 0
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        let address = Address::{ row, column, }
        let style = table_styles.applied(
          self.styles[sheet.style_at(address)],
          sheet,
          address,
        )
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
        index += 1
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
      fields[name] = style.borders[side].to_json()
    }
  }
  fields["readOnlyReason"] = Json(
    if !reason.is_empty() {
      reason
    } else if table_styles.tables.any(table => table.range.intersects(range)) {
      table_styles.reason
    } else {
      ""
    },
  )
  fields["fontKeys"] = Json(fonts)
  Json::object(fields)
}
