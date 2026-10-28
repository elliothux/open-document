///|
/// Format a supported Office list ordinal.
pub fn numbering_value(
  format : String,
  value : Int32,
) -> String raise @failure.Failure {
  guard value >= 0 else {
    @failure.reject("invalid-numbering", "Negative numbering value")
  }
  match format {
    "bullet" => ""
    "decimal" => value.to_string()
    "decimalFullWidth" => {
      let out = StringBuilder()
      for digit in value.to_string() {
        out.write_char((digit.to_int() - 48 + 0xff10).to_char().unwrap())
      }
      out.to_string()
    }
    "decimalEnclosedCircle" =>
      if value >= 1 && value <= 20 {
        String::from_array([(0x2460 + value - 1).to_char().unwrap()])
      } else {
        value.to_string()
      }
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
