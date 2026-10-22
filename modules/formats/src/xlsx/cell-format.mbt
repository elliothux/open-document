///|
pub(all) struct CellBorder {
  style : String
  color : String
} derive(ToJson, Eq, Hash)

///|
pub extend CellBorder with ToJson::{to_json}

///|
pub extend CellBorder with Eq::{equal, not_equal}

///|
pub extend CellBorder with Hash::{hash, hash_combine}

///|
pub struct CellFormat {
  family : String?
  size : Double?
  bold : Bool?
  italic : Bool?
  underline : Bool?
  strike : Bool?
  script : String?
  color : String?
  fill : String?
  horizontal : String?
  vertical : String?
  wrap : Bool?
  shrinkToFit : Bool?
  indent : Int?
  locked : Bool?
  formulaHidden : Bool?
  numberFormat : String?
  left : CellBorder?
  right : CellBorder?
  top : CellBorder?
  bottom : CellBorder?
} derive(Eq, Hash)

///|
pub extend CellFormat with Eq::{equal, not_equal}

///|
pub extend CellFormat with Hash::{hash, hash_combine}

///|
fn CellFormat::complete(self : CellFormat) -> Unit raise @failure.Failure {
  self.validate()
  guard self.family is Some(_) &&
    self.size is Some(_) &&
    self.bold is Some(_) &&
    self.italic is Some(_) &&
    self.underline is Some(_) &&
    self.strike is Some(_) &&
    self.script is Some(_) &&
    self.color is Some(_) &&
    self.fill is Some(_) &&
    self.horizontal is Some(_) &&
    self.vertical is Some(_) &&
    self.wrap is Some(_) &&
    self.shrinkToFit is Some(_) &&
    self.indent is Some(_) &&
    self.locked is Some(_) &&
    self.formulaHidden is Some(_) &&
    self.numberFormat is Some(_) &&
    self.left is Some(_) &&
    self.right is Some(_) &&
    self.top is Some(_) &&
    self.bottom is Some(_) else {
    @failure.reject(
      "invalid-operation", "Copied cell formats require every property",
    )
  }
}

///|
pub fn CellFormat::new(
  family~ : String? = None,
  size~ : Double? = None,
  bold~ : Bool? = None,
  italic~ : Bool? = None,
  underline~ : Bool? = None,
  strike~ : Bool? = None,
  script~ : String? = None,
  color~ : String? = None,
  fill~ : String? = None,
  horizontal~ : String? = None,
  vertical~ : String? = None,
  wrap~ : Bool? = None,
  shrinkToFit~ : Bool? = None,
  indent~ : Int? = None,
  locked~ : Bool? = None,
  formulaHidden~ : Bool? = None,
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
    underline,
    strike,
    script,
    color,
    fill,
    horizontal,
    vertical,
    wrap,
    shrinkToFit,
    indent,
    locked,
    formulaHidden,
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
  if self.script is Some(value) {
    guard ["baseline", "superscript", "subscript"].contains(value) else {
      @failure.reject("invalid-operation", "Invalid cell script")
    }
  }
  if self.horizontal is Some(value) {
    guard [
      "general", "left", "center", "right", "justify", "centerContinuous", "distributed",
      "fill",
    ].contains(value) else {
      @failure.reject("invalid-operation", "Invalid horizontal alignment")
    }
  }
  if self.vertical is Some(value) {
    guard ["top", "center", "bottom", "justify", "distributed"].contains(value) else {
      @failure.reject("invalid-operation", "Invalid vertical alignment")
    }
  }
  if self.indent is Some(value) {
    guard value >= 0 && value <= 250 else {
      @failure.reject(
        "invalid-operation", "Cell indent must be between 0 and 250",
      )
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
    guard ["none", "thin", "medium", "thick", "double"].contains(border.style) &&
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
  let border_priority = source.border_priority.copy()
  for i, patch in [self.left, self.right, self.top, self.bottom] {
    if patch is Some(border) {
      borders[i] = {
        ..border,
        color: if border.style == "none" {
          "000000"
        } else {
          border.color.to_lower()
        },
      }
      border_priority[i] = if border.style == "none" { 0 } else { 1 }
    }
  }
  {
    ..source,
    font,
    underline: self.underline.unwrap_or(source.underline),
    strike: self.strike.unwrap_or(source.strike),
    script: self.script.unwrap_or(source.script),
    size: self.size.unwrap_or(source.size),
    color: self.color.map(v => v.to_lower()).unwrap_or(source.color),
    fill: self.fill.map(v => v.to_lower()).unwrap_or(source.fill),
    horizontal: self.horizontal.unwrap_or(source.horizontal),
    vertical: self.vertical.unwrap_or(source.vertical),
    wrap: self.wrap.unwrap_or(source.wrap),
    shrink: self.shrinkToFit.unwrap_or(source.shrink),
    indent: self.indent.unwrap_or(source.indent),
    locked: self.locked.unwrap_or(source.locked),
    formula_hidden: self.formulaHidden.unwrap_or(source.formula_hidden),
    format: self.numberFormat.unwrap_or(source.format),
    borders,
    border_priority,
  }
}
