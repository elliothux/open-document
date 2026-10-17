///|
/// Keep leaves a direct property unchanged; Clear restores inheritance.
pub(all) enum FormatChange[T] {
  Keep
  Clear
  Set(T)
} derive(Eq)

///|
pub extend FormatChange with Eq::{equal, not_equal}

///|
pub(all) struct CharacterFormat {
  style : FormatChange[String]
  family : FormatChange[String]
  size : FormatChange[Double]
  color : FormatChange[String]
  bold : FormatChange[Bool]
  italic : FormatChange[Bool]
  underline : FormatChange[Bool]
  strike : FormatChange[Bool]
  highlight : FormatChange[String]
  vertAlign : FormatChange[String]
} derive(Eq)

///|
pub extend CharacterFormat with Eq::{equal, not_equal}

///|
pub fn CharacterFormat::new(
  style~ : FormatChange[String] = Keep,
  family~ : FormatChange[String] = Keep,
  size~ : FormatChange[Double] = Keep,
  color~ : FormatChange[String] = Keep,
  bold~ : FormatChange[Bool] = Keep,
  italic~ : FormatChange[Bool] = Keep,
  underline~ : FormatChange[Bool] = Keep,
  strike~ : FormatChange[Bool] = Keep,
  highlight~ : FormatChange[String] = Keep,
  vertAlign~ : FormatChange[String] = Keep,
) -> CharacterFormat {
  {
    style,
    family,
    size,
    color,
    bold,
    italic,
    underline,
    strike,
    highlight,
    vertAlign,
  }
}

///|
fn CharacterFormat::validate(
  self : CharacterFormat,
) -> Unit raise @failure.Failure {
  if self.highlight is Set(value) {
    ignore(
      highlight_color(value) catch {
        _ => @failure.reject("invalid-operation", "Invalid highlight color")
      },
    )
  }
  if self.vertAlign is Set(value) {
    guard ["baseline", "superscript", "subscript"].contains(value) else {
      @failure.reject("invalid-operation", "Invalid vertical alignment")
    }
  }
  if self.family is Set(family) {
    guard !family.trim().is_empty() &&
      family.length() <= 200 &&
      @xml.valid_text(family) else {
      @failure.reject("invalid-operation", "Invalid font family")
    }
  }
  if self.size is Set(size) {
    guard size >= 0.5 &&
      size <= 1024 &&
      size * 2 == (size * 2).to_int().to_double() else {
      @failure.reject(
        "invalid-operation", "Font size must be a half point between 0.5 and 1024",
      )
    }
  }
  if self.color is Set(color) {
    guard color == "auto" ||
      (color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit())) else {
      @failure.reject("invalid-operation", "Invalid character color")
    }
  }
}

///|
fn[T] merge_format(
  old : FormatChange[T],
  change : FormatChange[T],
) -> FormatChange[T] {
  match change {
    Keep => old
    _ => change
  }
}

///|
fn CharacterFormat::merge(
  self : CharacterFormat,
  patch : CharacterFormat,
) -> CharacterFormat {
  {
    style: merge_format(self.style, patch.style),
    family: merge_format(self.family, patch.family),
    size: merge_format(self.size, patch.size),
    color: merge_format(self.color, patch.color),
    bold: merge_format(self.bold, patch.bold),
    italic: merge_format(self.italic, patch.italic),
    underline: merge_format(self.underline, patch.underline),
    strike: merge_format(self.strike, patch.strike),
    highlight: merge_format(self.highlight, patch.highlight),
    vertAlign: merge_format(self.vertAlign, patch.vertAlign),
  }
}

///|
fn[T] format_value(current : T, inherited : T, change : FormatChange[T]) -> T {
  match change {
    Keep => current
    Clear => inherited
    Set(value) => value
  }
}

///|
fn RunStyle::formatted(
  self : RunStyle,
  inherited : RunStyle,
  patch : CharacterFormat,
) -> RunStyle {
  {
    family: format_value(self.family, inherited.family, patch.family),
    fonts: {
      ..self.fonts,
      slots: match patch.family {
        Keep => self.fonts.slots
        Clear => inherited.fonts.slots
        Set(value) =>
          Map::from_array(
            ["ascii", "hAnsi", "eastAsia", "cs"].map(slot => {
              (slot, (value, false))
            }),
          )
      },
      bold: format_value(self.fonts.bold, inherited.fonts.bold, patch.bold),
      italic: format_value(
        self.fonts.italic,
        inherited.fonts.italic,
        patch.italic,
      ),
      size: format_value(self.fonts.size, inherited.fonts.size, patch.size),
    },
    size: format_value(self.size, inherited.size, patch.size),
    color: format_value(self.color, inherited.color, patch.color),
    bold: format_value(self.bold, inherited.bold, patch.bold),
    italic: format_value(self.italic, inherited.italic, patch.italic),
    underline: format_value(
      self.underline,
      inherited.underline,
      patch.underline,
    ),
    strike: format_value(self.strike, inherited.strike, patch.strike),
    highlight: format_value(
      self.highlight,
      inherited.highlight,
      patch.highlight,
    ),
    vertAlign: format_value(
      self.vertAlign,
      inherited.vertAlign,
      patch.vertAlign,
    ),
  }
}

///|
fn CharacterFormat::properties(
  self : CharacterFormat,
) -> Map[String, Map[String, String?]?] {
  let result = Map([])
  match self.style {
    Keep => ()
    Clear => result["rStyle"] = None
    Set(value) =>
      result["rStyle"] = Some(Map::from_array([("val", Some(value))]))
  }
  for
    (name, change) in [
      (
        "u",
        match self.underline {
          Keep => Keep
          Clear => Clear
          Set(value) => Set(if value { "single" } else { "none" })
        },
      ),
      (
        "strike",
        match self.strike {
          Keep => Keep
          Clear => Clear
          Set(value) => Set(if value { "1" } else { "0" })
        },
      ),
      ("highlight", self.highlight),
      ("vertAlign", self.vertAlign),
    ] {
    match change {
      Keep => ()
      Clear => result[name] = None
      Set(value) => result[name] = Some(Map::from_array([("val", Some(value))]))
    }
  }
  match self.family {
    Keep => ()
    Clear => result["rFonts"] = None
    Set(value) =>
      result["rFonts"] = Some(
        Map::from_array([
          ("ascii", Some(value)),
          ("hAnsi", Some(value)),
          ("eastAsia", Some(value)),
          ("cs", Some(value)),
          ("asciiTheme", None),
          ("hAnsiTheme", None),
          ("eastAsiaTheme", None),
          ("cstheme", None),
        ]),
      )
  }
  match self.size {
    Keep => ()
    Clear => {
      result["sz"] = None
      result["szCs"] = None
    }
    Set(value) =>
      for name in ["sz", "szCs"] {
        result[name] = Some(
          Map::from_array([("val", Some((value * 2).to_int().to_string()))]),
        )
      }
  }
  match self.color {
    Keep => ()
    Clear => result["color"] = None
    Set(value) =>
      result["color"] = Some(
        Map::from_array([
          ("val", Some(value.to_lower())),
          ("themeColor", None),
          ("themeTint", None),
          ("themeShade", None),
        ]),
      )
  }
  for
    (names, change) in [(["b", "bCs"], self.bold), (["i", "iCs"], self.italic)] {
    for name in names {
      match change {
        Keep => ()
        Clear => result[name] = None
        Set(value) =>
          result[name] = Some(
            Map::from_array([("val", Some(if value { "1" } else { "0" }))]),
          )
      }
    }
  }
  result
}
