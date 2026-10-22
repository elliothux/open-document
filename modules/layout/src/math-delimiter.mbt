///|
fn math_delimiter_character(value : String) -> Bool {
  value.is_empty() ||
  (value.length() == 1 && "()[]{}|‖⌈⌉⌊⌋⟨⟩".contains(value))
}

///|
fn measure_math_delimited(
  open : String,
  close : String,
  separator : String,
  arguments : ReadOnlyArray[MathBox],
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
  paths : Ref[Int],
) -> MathBox raise @failure.Failure {
  let index = probe.math_font_index(style, profile)
  let axis = 0.6 * probe.math_glyph_height(index, 0x2217, style.size)
  let ascent = arguments.fold(init=0.0, (value, box) => value.max(box.ascent))
  let descent = arguments.fold(init=0.0, (value, box) => {
    value.max(box.height - box.ascent)
  })
  let placeholder = probe.math_glyph_height(index, 0x2b1a, style.size)
  // ONLYOFFICE operators.js centers delimiters around the mathematical axis.
  let target = if ascent < 1.01 * placeholder && descent < 0.4 * placeholder {
    ascent + descent
  } else {
    2 * (ascent - axis).max(descent + axis)
  }
  let make = ch => probe.math_delimiter(index, ch, target, style, paths)
  let left = make(open)
  let right = make(close)
  let middle = if arguments.length() > 1 { make(separator) } else { make("") }
  let upper = ascent
    .max(left.height / 2 + axis)
    .max(right.height / 2 + axis)
    .max(middle.height / 2 + axis)
  let lower = descent
    .max(left.height / 2 - axis)
    .max(right.height / 2 - axis)
    .max(middle.height / 2 - axis)
  let primitives : Array[PositionedPrimitive] = []
  let place = (box : MathBox, x) => {
    box.place(primitives, x, upper - axis - box.height / 2)
  }
  place(left, 0)
  let mut width = left.width
  for i, box in arguments {
    if i != 0 {
      place(middle, width)
      width += middle.width
    }
    box.place(primitives, width, upper - box.ascent)
    width += box.width
  }
  place(right, width)
  {
    width: width + right.width,
    height: upper + lower,
    ascent: upper,
    primitives,
    textAscent: None,
  }
}
