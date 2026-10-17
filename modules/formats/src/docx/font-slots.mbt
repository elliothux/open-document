///|
priv struct FontBindings {
  slots : Map[String, (String, Bool)]
  hint : String
  language : String
  complex : Bool
  rtl : Bool
  bold : Bool
  italic : Bool
  size : Double
} derive(Eq)

///|
fn font_bindings(
  tree : WordTree,
  parent : Int,
  base : FontBindings,
  inherited : Bool,
) -> FontBindings raise @failure.Failure {
  let slots = base.slots.copy()
  let mut hint = base.hint
  if tree.child(parent, "rFonts") is Some(id) {
    let node = tree.nodes[id]
    hint = node.attribute("hint", uri=word_uri).unwrap_or(hint)
    for
      (slot, theme) in [
        ("ascii", "asciiTheme"),
        ("hAnsi", "hAnsiTheme"),
        ("eastAsia", "eastAsiaTheme"),
        ("cs", "cstheme"),
      ] {
      if node.attribute(theme, uri=word_uri) is Some(value) {
        slots[slot] = (value, true)
      } else if node.attribute(slot, uri=word_uri) is Some(value) {
        slots[slot] = (value, false)
      }
    }
  }
  guard ["default", "cs", "eastAsia"].contains(hint) else {
    @failure.reject("invalid-style", "Invalid font hint")
  }
  for field in ["cs", "rtl"] {
    if tree.child(parent, field) is Some(id) && !tree.valid_on_off_property(id) {
      @failure.reject("protected-content", "Invalid font slot flag")
    }
  }
  {
    slots,
    hint,
    language: tree
    .child(parent, "lang")
    .bind(id => tree.nodes[id].attribute("eastAsia", uri=word_uri))
    .unwrap_or(base.language),
    complex: tree
    .value(parent, "cs")
    .map(v => !["0", "false", "off"].contains(v))
    .unwrap_or(
      if tree.child(parent, "cs") is Some(_) {
        true
      } else {
        base.complex
      },
    ),
    rtl: tree
    .value(parent, "rtl")
    .map(v => !["0", "false", "off"].contains(v))
    .unwrap_or(
      if tree.child(parent, "rtl") is Some(_) {
        true
      } else {
        base.rtl
      },
    ),
    bold: tree.character_toggle(parent, "bCs", base.bold, inherited),
    italic: tree.character_toggle(parent, "iCs", base.italic, inherited),
    size: tree
    .number(parent, "szCs", "val")
    .map(v => v / 2)
    .unwrap_or(base.size),
  }
}

///|
fn font_family(
  bindings : Map[String, (String, Bool)],
  slot : String,
  fallback : String,
  themes : Map[String, String],
) -> String raise @failure.Failure {
  guard bindings.get(slot) is Some((value, themed)) else { return fallback }
  if themed {
    guard [
        "majorAscii", "majorHAnsi", "majorEastAsia", "majorBidi", "minorAscii", "minorHAnsi",
        "minorEastAsia", "minorBidi",
      ].contains(value) &&
      themes.get(value) is Some(family) &&
      !family.is_empty() else {
      @failure.reject("invalid-style", "Missing theme font: " + value)
    }
    family
  } else {
    value
  }
}

///|
fn FontBindings::slot(self : FontBindings, text : String) -> String {
  let ch = text.get_char(0).map(c => c.to_int()).unwrap_or(0)
  let ea_hint = self.hint == "eastAsia"
  if ch < 128 {
    return if self.complex || self.rtl { "cs" } else { "ascii" }
  }
  if ch >= 0xe000 && ch <= 0xf8ff {
    return if ea_hint { "eastAsia" } else { "ascii" }
  }
  let zh = ea_hint && self.language.to_lower().has_prefix("zh")
  // Slot ranges and hint precedence follow ONLYOFFICE FontClassification (DR 09-0040).
  let east_asia = [
    (0x1100, 0x11ff),
    (0x2e80, 0x319f),
    (0x3200, 0x4dbf),
    (0x4e00, 0x9faf),
    (0xa000, 0xa4cf),
    (0xac00, 0xd7af),
    (0xf900, 0xfaff),
    (0xfe30, 0xfe6f),
    (0xff00, 0xffef),
    (0x20000, 0x2a6df),
    (0x2f800, 0x2fa1f),
  ].any(r => ch >= r.0 && ch <= r.1)
  let hinted = ea_hint &&
    (
      (ch >= 0x2b0 && ch <= 0x4ff) ||
      (ch >= 0x2000 && ch <= 0x27bf) ||
      (ch >= 0xfb00 && ch <= 0xfb1c) ||
      (ch >= 0xe000 && ch <= 0xf8ff) ||
      [
        0xa1, 0xa4, 0xa7, 0xa8, 0xaa, 0xad, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb6,
        0xb7, 0xb8, 0xb9, 0xba, 0xbc, 0xbd, 0xbe, 0xbf, 0xd7, 0xf7,
      ].contains(ch) ||
      (
        zh &&
        (
          (ch >= 0x100 && ch <= 0x2af) ||
          (ch >= 0x1e00 && ch <= 0x1eff) ||
          [
            0xe0, 0xe1, 0xe8, 0xe9, 0xea, 0xec, 0xed, 0xf2, 0xf3, 0xf9, 0xfa, 0xfc,
          ].contains(ch)
        )
      )
    )
  if ea_hint && ch <= 0xffff && (east_asia || hinted) {
    return "eastAsia"
  }
  if self.complex || self.rtl {
    return "cs"
  }
  if ea_hint && ch >= 0x1f00 && ch <= 0x1fff {
    return "hAnsi"
  }
  if east_asia {
    return "eastAsia"
  }
  if ch > 0xffff {
    return if ch >= 0x1d400 && ch <= 0x1d7ff { "ascii" } else { "hAnsi" }
  }
  if [
      (0xa0, 0x4ff),
      (0x900, 0x10ff),
      (0x1200, 0x13ff),
      (0x1e00, 0x1eff),
      (0x2000, 0x27bf),
      (0xfb00, 0xfb1c),
    ].any(r => ch >= r.0 && ch <= r.1) {
    "hAnsi"
  } else {
    "ascii"
  }
}

///|
fn RunStyle::for_font_slot(
  self : RunStyle,
  slot : String,
  themes : Map[String, String],
) -> RunStyle raise @failure.Failure {
  {
    ..self,
    family: font_family(self.fonts.slots, slot, self.family, themes),
    bold: if slot == "cs" {
      self.fonts.bold
    } else {
      self.bold
    },
    italic: if slot == "cs" {
      self.fonts.italic
    } else {
      self.italic
    },
    size: if slot == "cs" {
      self.fonts.size
    } else {
      self.size
    },
  }
}

///|
fn RunStyle::font_runs(
  self : RunStyle,
  text : String,
  themes : Map[String, String],
) -> Array[(RunStyle, String)] raise @failure.Failure {
  let bounds = @layout.grapheme_boundaries(text)
  let result : Array[(RunStyle, String)] = []
  let mut start = 0
  let mut style = self.for_font_slot(self.fonts.slot(text), themes)
  for i in 0..<(bounds.length() - 1) {
    let a = bounds[i]
    let next = self.for_font_slot(
      self.fonts.slot(text[a:bounds[i + 1]].to_owned()),
      themes,
    )
    if a > start && next != style {
      result.push((style, text[start:a].to_owned()))
      start = a
    }
    style = next
  }
  result.push((style, text[start:].to_owned()))
  result
}

///|
fn RunStyle::caret_font(
  self : RunStyle,
  text : String,
  offset : Int,
  before : Bool,
  themes : Map[String, String],
) -> RunStyle raise @failure.Failure {
  let bounds = @layout.grapheme_boundaries(text)
  let mut start = 0
  let mut end = text.length()
  for i in 0..<(bounds.length() - 1) {
    if offset < bounds[i + 1] ||
      (before && offset == bounds[i + 1]) ||
      i == bounds.length() - 2 {
      start = bounds[i]
      end = bounds[i + 1]
      break
    }
  }
  self.font_runs(text[start:end].to_owned(), themes)[0].0
}
