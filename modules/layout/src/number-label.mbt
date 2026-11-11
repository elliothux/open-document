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
    "ideographTraditional" | "ideographZodiac" => {
      let symbols = if format == "ideographTraditional" {
        "甲乙丙丁戊己庚辛壬癸"
      } else {
        "子丑寅卯辰巳午未申酉戌亥"
      }
      if value > 0 && value <= symbols.length() {
        symbols[value - 1:value].to_owned()
      } else {
        value.to_string()
      }
    }
    "ideographLegalTraditional" | "taiwaneseCountingThousand" =>
      chinese_numbering(value, legal=format == "ideographLegalTraditional")
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
fn chinese_numbering(
  value : Int32,
  legal~ : Bool,
) -> String raise @failure.Failure {
  guard value < 1000000 else {
    @failure.reject(
      "unsupported-numbering", "Chinese numbering value exceeds supported range",
    )
  }
  if value == 0 {
    return "零"
  }
  let digits = if legal {
    "零壹貳參肆伍陸柒捌玖"
  } else {
    "零一二三四五六七八九"
  }
  let units = if legal { "仟佰拾" } else { "千百十" }
  let output = StringBuilder()
  let group = fn(number : Int32, omit_one : Bool) {
    let mut gap = false
    let mut started = false
    for i, place in [1000, 100, 10, 1] {
      let digit = number / place % 10
      if digit == 0 {
        gap = started
        continue
      }
      if gap {
        output.write_string("零")
        gap = false
      }
      if !(omit_one && place == 10 && digit == 1) {
        output.write_string(digits[digit:digit + 1].to_owned())
      }
      if place > 1 {
        output.write_string(units[i:i + 1].to_owned())
      }
      started = true
    }
  }
  let lower = value % 10000
  if value >= 10000 {
    group(value / 10000, false)
    output.write_string("萬")
    if lower > 0 &&
      (if legal {
        lower < 10 || (lower < 100 && lower % 10 == 0)
      } else {
        lower < 1000
      }) {
      output.write_string("零")
    }
  }
  group(lower, !legal && value < 20)
  output.to_string()
}
