///|
fn numbering_label(
  levels : Map[Int32, NumberLevel],
  values : Array[Int32],
  level : Int32,
  reference~ : Bool = false,
) -> String raise @failure.Failure {
  let definition = levels[level]
  let mut end = definition.pattern.length()
  // ONLYOFFICE CNum.GetText omits only the final literal token for REF \n.
  if reference &&
    end > 0 &&
    !(end >= 2 &&
    definition.pattern[end - 2] == '%' &&
    definition.pattern[end - 1] >= '1' &&
    definition.pattern[end - 1] <= '9') {
    end -= if definition.pattern[end - 1] >= 0xdc00 &&
      definition.pattern[end - 1] <= 0xdfff {
      2
    } else {
      1
    }
  }
  let output = StringBuilder()
  let mut i = 0
  let mut units = 0
  while i < end {
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
      let text = @layout.numbering_value(target.format, values[index])
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
