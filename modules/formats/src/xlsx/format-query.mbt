///|
fn CellStyle::cell_format(self : CellStyle) -> CellFormat {
  let pieces = self.font.split("|").map(v => v.to_owned()).to_array()
  {
    family: Some(pieces[0]),
    size: Some(self.size),
    bold: Some(pieces.contains("bold")),
    italic: Some(pieces.contains("italic")),
    underline: Some(self.underline),
    strike: Some(self.strike),
    script: Some(self.script),
    color: Some(self.color),
    fill: Some(self.fill),
    horizontal: Some(self.horizontal),
    vertical: Some(self.vertical),
    wrap: Some(self.wrap),
    shrinkToFit: Some(self.shrink),
    indent: Some(self.indent),
    textRotation: Some(self.rotation),
    locked: Some(self.locked),
    formulaHidden: Some(self.formula_hidden),
    numberFormat: Some(self.format),
    left: Some(self.borders[0]),
    right: Some(self.borders[1]),
    top: Some(self.borders[2]),
    bottom: Some(self.borders[3]),
  }
}

///|
fn[T : Eq] common_format_value(value : T?, other : T?) -> T? {
  if value == other {
    value
  } else {
    None
  }
}

///|
fn CellFormat::common(self : CellFormat, other : CellFormat) -> CellFormat {
  {
    family: common_format_value(self.family, other.family),
    size: common_format_value(self.size, other.size),
    bold: common_format_value(self.bold, other.bold),
    italic: common_format_value(self.italic, other.italic),
    underline: common_format_value(self.underline, other.underline),
    strike: common_format_value(self.strike, other.strike),
    script: common_format_value(self.script, other.script),
    color: common_format_value(self.color, other.color),
    fill: common_format_value(self.fill, other.fill),
    horizontal: common_format_value(self.horizontal, other.horizontal),
    vertical: common_format_value(self.vertical, other.vertical),
    wrap: common_format_value(self.wrap, other.wrap),
    shrinkToFit: common_format_value(self.shrinkToFit, other.shrinkToFit),
    indent: common_format_value(self.indent, other.indent),
    textRotation: common_format_value(self.textRotation, other.textRotation),
    locked: common_format_value(self.locked, other.locked),
    formulaHidden: common_format_value(self.formulaHidden, other.formulaHidden),
    numberFormat: common_format_value(self.numberFormat, other.numberFormat),
    left: common_format_value(self.left, other.left),
    right: common_format_value(self.right, other.right),
    top: common_format_value(self.top, other.top),
    bottom: common_format_value(self.bottom, other.bottom),
  }
}

///|
fn[T : ToJson] format_field(value : T?) -> Json {
  Json(QueryNullable::{ value, })
}

///|
fn CellFormat::format_values(self : CellFormat) -> Map[String, Json] {
  {
    "family": format_field(self.family),
    "size": format_field(self.size),
    "bold": format_field(self.bold),
    "italic": format_field(self.italic),
    "underline": format_field(self.underline),
    "strike": format_field(self.strike),
    "script": format_field(self.script),
    "color": format_field(self.color),
    "fill": format_field(self.fill),
    "horizontal": format_field(self.horizontal),
    "vertical": format_field(self.vertical),
    "wrap": format_field(self.wrap),
    "shrinkToFit": format_field(self.shrinkToFit),
    "indent": format_field(self.indent),
    "textRotation": format_field(self.textRotation),
    "locked": format_field(self.locked),
    "formulaHidden": format_field(self.formulaHidden),
    "numberFormat": format_field(self.numberFormat),
    "left": format_field(self.left),
    "right": format_field(self.right),
    "top": format_field(self.top),
    "bottom": format_field(self.bottom),
  }
}

///|
impl ToJson for QueryFormatting with fn to_json(self) {
  let fields = self.format.format_values()
  fields["readOnlyReason"] = Json(self.readOnlyReason)
  fields["fontKeys"] = Json(self.fontKeys)
  Json::object(fields)
}

///|
fn Session::formatting(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> QueryFormatting raise @failure.Failure {
  let range = sheet.merge_target(range)
  let reason = self.format_reason(sheet, range)
  let table_styles = self.table_styles(
    sheet,
    {
      remaining: 1048576,
      date1904: self.date1904,
      random: None,
      origin: self.focus,
      names: self.formula_names(),
    },
    self.parts,
  )
  let mut common : CellFormat? = None
  let fonts : Array[String] = []
  if (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096L {
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        let address = Address::{ row, column, }
        let style = table_styles.applied(
          self.styles[sheet.style_at(address)],
          sheet,
          address,
        )
        let format = style.cell_format()
        common = Some(
          if common is Some(previous) {
            previous.common(format)
          } else {
            format
          },
        )
        if !fonts.contains(style.font) {
          fonts.push(style.font)
        }
      }
    }
  }
  let format = common.unwrap_or_else(() => CellFormat::new())
  let format = if sheet.merges.any(merged => merged == range) {
    let style = self.merged_style(sheet, range)
    {
      ..format,
      left: Some(style.borders[0]),
      right: Some(style.borders[1]),
      top: Some(style.borders[2]),
      bottom: Some(style.borders[3]),
    }
  } else {
    format
  }
  {
    format,
    readOnlyReason: if !reason.is_empty() {
      reason
    } else if table_styles.tables.any(table => table.range.intersects(range)) {
      table_styles.reason
    } else {
      ""
    },
    fontKeys: fonts,
  }
}
