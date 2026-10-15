///|
fn numbering_value(
  format : String,
  value : Int,
) -> String raise @failure.Failure {
  guard value >= 0 else {
    @failure.reject("invalid-numbering", "Negative numbering value")
  }
  match format {
    "bullet" => ""
    "decimal" => value.to_string()
    "decimalZero" => (if value < 10 { "0" } else { "" }) + value.to_string()
    "lowerLetter" | "upperLetter" => {
      if value == 0 {
        return ""
      }
      let alphabet = if format == "lowerLetter" {
        "abcdefghijklmnopqrstuvwxyz"
      } else {
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      }
      // Word numbering repeats a letter (aa, bb), rather than naming spreadsheet columns.
      let ordinal = (value - 1) % 780
      let index = ordinal % 26
      Array::make(ordinal / 26 + 1, alphabet[index:index + 1].to_owned()).join(
        "",
      )
    }
    "lowerRoman" | "upperRoman" => {
      if value == 0 {
        return ""
      }
      let output = StringBuilder()
      let mut rest = (value - 1) % 32767 + 1
      for
        (number, text) in [
          (1000, "M"),
          (900, "CM"),
          (500, "D"),
          (400, "CD"),
          (100, "C"),
          (90, "XC"),
          (50, "L"),
          (40, "XL"),
          (10, "X"),
          (9, "IX"),
          (5, "V"),
          (4, "IV"),
          (1, "I"),
        ] {
        while rest >= number {
          output.write_string(text)
          rest -= number
        }
      }
      let text = output.to_string()
      if format == "lowerRoman" {
        text.to_lower()
      } else {
        text
      }
    }
    _ =>
      @failure.reject("unsupported-numbering", "Unsupported numbering format")
  }
}

///|
fn numbering_label(
  levels : Map[Int, NumberLevel],
  values : Array[Int],
  level : Int,
) -> String raise @failure.Failure {
  let definition = levels[level]
  let output = StringBuilder()
  let mut i = 0
  let mut units = 0
  while i < definition.pattern.length() {
    if definition.pattern[i] == '%' &&
      i + 1 < definition.pattern.length() &&
      definition.pattern[i + 1] >= '1' &&
      definition.pattern[i + 1] <= '9' {
      let index = definition.pattern[i + 1].to_int() - 49
      guard index <= level && levels.get(index) is Some(target) else {
        @failure.reject(
          "unsupported-numbering", "Unsupported numbering placeholder",
        )
      }
      let text = numbering_value(target.format, values[index])
      units += text.length()
      output.write_string(text)
      i += 1
    } else {
      let count = if definition.pattern[i] >= 0xd800 &&
        definition.pattern[i] <= 0xdbff {
        2
      } else {
        1
      }
      output.write_string(definition.pattern[i:i + count].to_owned())
      units += count
      i += count - 1
    }
    guard units <= 256 else {
      @failure.reject("limit-exceeded", "Numbering label exceeds budget")
    }
    i += 1
  }
  output.to_string()
}
