///|
pub(all) struct CellBorder {
  style : String
  color : String
} derive(ToJson)

///|
pub extend CellBorder with ToJson::{to_json}

///|
pub struct CellFormat {
  family : String?
  size : Double?
  bold : Bool?
  italic : Bool?
  color : String?
  fill : String?
  horizontal : String?
  vertical : String?
  wrap : Bool?
  numberFormat : String?
  left : CellBorder?
  right : CellBorder?
  top : CellBorder?
  bottom : CellBorder?
}

///|
pub fn CellFormat::new(
  family~ : String? = None,
  size~ : Double? = None,
  bold~ : Bool? = None,
  italic~ : Bool? = None,
  color~ : String? = None,
  fill~ : String? = None,
  horizontal~ : String? = None,
  vertical~ : String? = None,
  wrap~ : Bool? = None,
  numberFormat~ : String? = None,
  left~ : CellBorder? = None,
  right~ : CellBorder? = None,
  top~ : CellBorder? = None,
  bottom~ : CellBorder? = None,
) -> CellFormat {
  {
    family,
    size,
    bold,
    italic,
    color,
    fill,
    horizontal,
    vertical,
    wrap,
    numberFormat,
    left,
    right,
    top,
    bottom,
  }
}

///|
fn CellFormat::validate(self : CellFormat) -> Unit raise @failure.Failure {
  if self.family is Some(value) {
    guard !value.is_empty() &&
      value.length() <= 256 &&
      @xml.valid_text(value) &&
      value.iter().all(c => c >= ' ' && c != '|' && c != '\u007f') else {
      @failure.reject("invalid-operation", "Invalid cell font family")
    }
  }
  if self.size is Some(value) {
    guard !value.is_nan() && !value.is_inf() && value >= 1 && value <= 409 else {
      @failure.reject("invalid-operation", "Invalid cell font size")
    }
  }
  for value in [self.color, self.fill].iter().filter_map(v => v) {
    guard (value.is_empty() && self.fill == Some(value)) ||
      (value.length() == 6 && value.iter().all(c => c.is_ascii_hexdigit())) else {
      @failure.reject(
        "invalid-operation", "Cell colors require six hexadecimal digits",
      )
    }
  }
  guard self.color != Some("") else {
    @failure.reject("invalid-operation", "Cell text color cannot be empty")
  }
  if self.horizontal is Some(value) {
    guard ["general", "left", "center", "right"].contains(value) else {
      @failure.reject("invalid-operation", "Invalid horizontal alignment")
    }
  }
  if self.vertical is Some(value) {
    guard ["top", "center", "bottom"].contains(value) else {
      @failure.reject("invalid-operation", "Invalid vertical alignment")
    }
  }
  if self.numberFormat is Some(value) {
    guard supported_format(value) else {
      @failure.reject("invalid-operation", "Unsupported cell number format")
    }
  }
  for
    border in [self.left, self.right, self.top, self.bottom]
    .iter()
    .filter_map(v => v) {
    guard ["none", "thin", "medium", "thick"].contains(border.style) &&
      border.color.length() == 6 &&
      border.color.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject("invalid-operation", "Invalid cell border")
    }
  }
}

///|
fn column_style(columns : Array[(Int, Int, Int)], column : Int) -> Int {
  for low = 0, high = columns.length(); low < high; {
    let middle = low + (high - low) / 2
    let (first, last, style) = columns[middle]
    if column < first {
      continue low, middle
    }
    if column > last {
      continue middle + 1, high
    }
    return style
  }
  0
}

///|
fn Sheet::style_at(
  self : Sheet,
  address : Address,
) -> Int raise @failure.Failure {
  self.cells
  .get(address.name())
  .map(cell => cell.style)
  .unwrap_or_else(() => {
    self.row_styles
    .get(address.row)
    .unwrap_or(column_style(self.column_styles, address.column))
  })
}

///|
fn CellFormat::applied(self : CellFormat, source : CellStyle) -> CellStyle {
  let pieces = source.font.split("|").map(v => v.to_owned()).to_array()
  let font = self.family.unwrap_or(pieces[0]) +
    (if self.bold.unwrap_or(pieces.contains("bold")) { "|bold" } else { "" }) +
    (if self.italic.unwrap_or(pieces.contains("italic")) {
      "|italic"
    } else {
      ""
    })
  let borders = source.borders.copy()
  for i, patch in [self.left, self.right, self.top, self.bottom] {
    if patch is Some(border) {
      borders[i] = (
        if border.style == "none" {
          ""
        } else {
          border.color.to_lower()
        },
        match border.style {
          "thin" => 0.75
          "medium" => 1.5
          "thick" => 2.25
          _ => 0.0
        },
      )
    }
  }
  {
    ..source,
    font,
    size: self.size.unwrap_or(source.size),
    color: self.color.map(v => v.to_lower()).unwrap_or(source.color),
    fill: self.fill.map(v => v.to_lower()).unwrap_or(source.fill),
    horizontal: self.horizontal.unwrap_or(source.horizontal),
    vertical: self.vertical.unwrap_or(source.vertical),
    wrap: self.wrap.unwrap_or(source.wrap),
    format: self.numberFormat.unwrap_or(source.format),
    borders,
  }
}
