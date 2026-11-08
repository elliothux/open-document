///|
fn section_number_parts(
  value : Double,
  mask : String,
  places : Int32,
  grouped : Bool,
  percent : Int32,
) -> Array[NumberPart] {
  let raw = number_digits(value, places + 2 * percent, 0)
  if raw == "########" {
    return [Visible(raw)]
  }
  let raw = "0".repeat((places + 1 - raw.length()).max(0)) + raw
  let integer = raw[:raw.length() - places].to_owned()
  let minimum = mask.iter().filter(c => c == '0').count()
  let integer = if integer == "0" && minimum == 0 {
    ""
  } else {
    "0".repeat((minimum - integer.length()).max(0)) + integer
  }
  let parts : Array[NumberPart] = []
  for c in mask[:(mask.length() - integer.length()).max(0)].iter() {
    if c == '?' {
      parts.push(Skip("0"))
    }
  }
  let digits = StringBuilder()
  for i in 0..<integer.length() {
    if grouped && i > 0 && (integer.length() - i) % 3 == 0 {
      digits.write_char(',')
    }
    digits.write_char(integer.get_char(i).unwrap())
  }
  if places > 0 {
    digits.write_char('.')
    digits.write_string(raw[raw.length() - places:].to_owned())
  }
  parts.push(Visible(digits.to_string()))
  parts
}

///|
fn section_display(value : Value, format : String) -> NumberSection? {
  guard section_format(format) is Some(sections) else { return None }
  let has_text = fn(section : NumberSection) {
    section.parts.any(part => part is SourceText)
  }
  let (index, automatic_minus) = match value {
    Text(_) => {
      let index = if sections.length() == 4 {
        3
      } else if sections.length() >= 2 && has_text(sections.last().unwrap()) {
        sections.length() - 1
      } else {
        0
      }
      guard sections.length() == 4 || has_text(sections[index]) else {
        return None
      }
      (index, false)
    }
    Number(number) => {
      let separate_negative = sections.length() >= 2 && !has_text(sections[1])
      (
        if number < 0 && separate_negative {
          1
        } else if number == 0 &&
          sections.length() >= 3 &&
          !has_text(sections[2]) {
          2
        } else {
          0
        },
        number < 0 && !separate_negative,
      )
    }
    _ => return None
  }
  let section = sections[index]
  if value is Number(number) && (number.is_nan() || number.is_inf()) {
    return Some({ ..section, parts: [Visible("########")], })
  }
  let parts : Array[NumberPart] = []
  if automatic_minus &&
    !has_text(section) &&
    !section.parts.any(part => part is Sign(_)) &&
    value is Number(number) {
    let places = section.parts
      .iter()
      .find_first(part => part is Digits(_, _, _))
      .map(part => {
        match part {
          Digits(_, places, _) => places
          _ => 0
        }
      })
      .unwrap_or(0)
    if number_digits(number, places + 2 * section.percent, 0) != "0" {
      parts.push(Visible("-"))
    }
  }
  for part in section.parts {
    match part {
      SourceText => parts.push(ValueText(value.display()))
      Digits(mask, places, grouped) =>
        if value is Number(number) {
          parts.append(
            section_number_parts(number, mask, places, grouped, section.percent),
          )
        }
      Percent => parts.push(Visible("%"))
      Sign(kind) => {
        let number = match value {
          Number(number) => number
          _ => 0.0
        }
        parts.push(
          Visible(
            if number < 0 {
              "-"
            } else if number > 0 && kind == '+' {
              "+"
            } else {
              " "
            },
          ),
        )
      }
      other => parts.push(other)
    }
  }
  Some({ parts, color: section.color, percent: section.percent, })
}

///|
fn NumberSection::display(self : NumberSection) -> String {
  self.parts
  .iter()
  .filter_map(part => {
    match part {
      Visible(text) | ValueText(text) => Some(text)
      _ => None
    }
  })
  .join("")
}

///|
fn NumberSection::spacing_units(self : NumberSection) -> Int32 {
  self.parts.fold(init=0, (sum, part) => {
    sum +
    (match part {
      Skip(text) => text.length()
      _ => 0
    })
  })
}
