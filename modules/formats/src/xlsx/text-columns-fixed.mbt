///|
fn fixed_column_field(text : String, first : Int, last : Int) -> String {
  let mut last = last
  while last > first && text[last - 1] == 32 {
    last -= 1
  }
  if last - first >= 2 && text[first] == 34 && text[last - 1] == 34 {
    text[first + 1:last - 1].to_owned()
  } else {
    text[first:last].to_owned()
  }
}

///|
fn fixed_column_fields(text : String, breaks : Array[Int]) -> Array[String] {
  let boundaries = @layout.grapheme_boundaries(text)
  let widths = Array::makei(boundaries.length() - 1, index => {
    let mut width = 0
    for character in text[boundaries[index]:boundaries[index + 1]].iter() {
      width += text_column_width(character)
    }
    width
  })
  let fields : Array[String] = []
  let mut cursor = 0
  let mut previous = 0
  for position in breaks {
    let first = boundaries[cursor]
    let mut width = 0
    while cursor < widths.length() && width < position - previous {
      width += widths[cursor]
      cursor += 1
    }
    // Keep ignorable clusters with the preceding field, and never split a grapheme.
    while cursor < widths.length() && widths[cursor] == 0 {
      cursor += 1
    }
    fields.push(fixed_column_field(text, first, boundaries[cursor]))
    previous = position
  }
  fields.push(fixed_column_field(text, boundaries[cursor], text.length()))
  fields
}
