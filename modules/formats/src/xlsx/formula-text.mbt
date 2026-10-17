///|
priv struct FormulaText {
  output : StringBuilder
  mut units : Int
}

///|
fn FormulaText::new() -> FormulaText {
  { output: StringBuilder(), units: 0, }
}

///|
fn FormulaText::append(
  self : FormulaText,
  text : String,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  if text.length() > 32767 - self.units {
    return false
  }
  work.spend(amount=text.length())
  self.output.write_string(text)
  self.units += text.length()
  true
}

///|
fn formula_text_number(
  values : Array[Value],
  index : Int,
  default : Double,
) -> Value {
  numeric_value(values.get(index).unwrap_or(Number(default)))
}

///|
fn text_function(
  name : String,
  args : Array[Expression],
  sheets : Array[Sheet],
  sheet : Int,
  calculated : Map[(Int, String), Value],
  work : FormulaWork,
  depth : Int,
) -> Value raise @failure.Failure {
  if ["CONCAT", "CONCATENATE", "TEXTJOIN"].contains(name) {
    return join_function(name, args, sheets, sheet, calculated, work, depth)
  }
  let values : Array[Value] = []
  for arg in args {
    let value = arg.evaluate(sheets, sheet, calculated, work, depth + 1)
    if value is Error(_) {
      return value
    }
    values.push(value)
  }
  let text = values[0].display()
  match name {
    "EXACT" => {
      let other = values[1].display()
      work.spend(amount=text.length() + other.length())
      Boolean(text == other)
    }
    "REPT" =>
      match numeric_value(values[1]) {
        Number(count) => {
          // ONLYOFFICE checks the raw count and UTF-16 product before repeat truncates it.
          if count < 0 ||
            count > 32767 ||
            text.length().to_double() * count > 32767 {
            return Error("#VALUE!")
          }
          let count = count.to_int()
          work.spend(amount=text.length() * count)
          Text(text.repeat(count))
        }
        value => value
      }
    "LEN" => Number(text.length().to_double())
    "UPPER" | "LOWER" => formula_case(text, name == "UPPER", work)
    "TRIM" => {
      let out = FormulaText::new()
      let mut space = false
      for character in text.iter() {
        work.spend()
        if character == ' ' {
          space = out.units > 0
        } else {
          if space {
            ignore(out.append(" ", work))
          }
          if !out.append(character.to_string(), work) {
            return Error("#VALUE!")
          }
          space = false
        }
      }
      Text(out.output.to_string())
    }
    "LEFT" | "RIGHT" | "MID" => {
      let position = formula_text_number(values, 1, 1)
      guard position is Number(position) else { return position }
      if position < (if name == "MID" { 1 } else { 0 }) {
        return Error("#VALUE!")
      }
      let (start, count) = if name == "MID" {
        let count = formula_text_number(values, 2, 0)
        guard count is Number(count) else { return count }
        if count < 0 {
          return Error("#VALUE!")
        }
        (position.min((text.length() + 1).to_double()).to_int() - 1, count)
      } else {
        let count = position.min(text.length().to_double()).to_int()
        (
          if name == "LEFT" {
            0
          } else {
            text.length() - count
          },
          count.to_double(),
        )
      }
      let end = start + count.min((text.length() - start).to_double()).to_int()
      guard text.get_view(start~, end~) is Some(piece) else {
        return Error("#VALUE!")
      }
      work.spend(amount=end - start)
      Text(piece.to_owned())
    }
    "FIND" | "SEARCH" => {
      let within = values[1].display()
      let start = formula_text_number(values, 2, 1)
      guard start is Number(start) else { return start }
      if start < 1 ||
        start >
        (within.length() + (if name == "FIND" { 1 } else { 0 })).to_double() {
        return Error("#VALUE!")
      }
      let start = start.trunc().to_int() - 1
      let found = if name == "FIND" {
        formula_find(text, within, start, work)
      } else {
        formula_search(text, within, start, work)
      }
      match found {
        Some(index) => Number((index + 1).to_double())
        None => Error("#VALUE!")
      }
    }
    "SUBSTITUTE" => {
      let old = values[1].display()
      let replacement = values[2].display()
      let occurrence = formula_text_number(values, 3, 0)
      guard occurrence is Number(occurrence) else { return occurrence }
      if values.length() == 4 && occurrence < 1 {
        return Error("#VALUE!")
      }
      if old.is_empty() || occurrence > text.length().to_double() {
        return Text(text)
      }
      let occurrence = occurrence.trunc().to_int()
      let out = FormulaText::new()
      let mut cursor = 0
      let mut count = 0
      while formula_find(old, text, cursor, work) is Some(found) {
        count += 1
        if !out.append(text[cursor:found].to_owned(), work) {
          return Error("#VALUE!")
        }
        let inserted = if occurrence == 0 || occurrence == count {
          replacement
        } else {
          old
        }
        if !out.append(inserted, work) {
          return Error("#VALUE!")
        }
        cursor = found + old.length()
        if occurrence == count {
          break
        }
      }
      if !out.append(text[cursor:].to_owned(), work) {
        return Error("#VALUE!")
      }
      Text(out.output.to_string())
    }
    _ => abort("Unexpected text function")
  }
}
