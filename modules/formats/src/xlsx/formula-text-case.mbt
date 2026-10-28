///|
// Unicode 16 DerivedCoreProperties entries outside the general categories below.
let formula_cased_extra : FixedArray[(Int32, Int32)] = [
  (0xaa, 0xaa),
  (0xba, 0xba),
  (0x2b0, 0x2b8),
  (0x2c0, 0x2c1),
  (0x2e0, 0x2e4),
  (0x345, 0x345),
  (0x37a, 0x37a),
  (0x10fc, 0x10fc),
  (0x1d2c, 0x1d6a),
  (0x1d78, 0x1d78),
  (0x1d9b, 0x1dbf),
  (0x2071, 0x2071),
  (0x207f, 0x207f),
  (0x2090, 0x209c),
  (0x2160, 0x217f),
  (0x24b6, 0x24e9),
  (0x2c7c, 0x2c7d),
  (0xa69c, 0xa69d),
  (0xa770, 0xa770),
  (0xa7f2, 0xa7f4),
  (0xa7f8, 0xa7f9),
  (0xab5c, 0xab5f),
  (0xab69, 0xab69),
  (0x10780, 0x10780),
  (0x10783, 0x10785),
  (0x10787, 0x107b0),
  (0x107b2, 0x107ba),
  (0x1e030, 0x1e06d),
  (0x1f130, 0x1f149),
  (0x1f150, 0x1f169),
  (0x1f170, 0x1f189),
]

///|
let formula_ignorable_extra : FixedArray[Int32] = [
  0x27, 0x2e, 0x3a, 0xb7, 0x387, 0x55f, 0x5f4, 0x2018, 0x2019, 0x2024, 0x2027, 0xfe13,
  0xfe52, 0xfe55, 0xff07, 0xff0e, 0xff1a,
]

///|
fn formula_case_ignorable(character : Char) -> Bool {
  match @ucd.general_category(character) {
    Mn | Me | Cf | Lm | Sk => true
    // Remaining Case_Ignorable punctuation from Unicode 16 DerivedCoreProperties.
    _ => formula_ignorable_extra.contains(character.to_int())
  }
}

///|
fn formula_cased(character : Char) -> Bool {
  match @ucd.general_category(character) {
    Lu | Ll | Lt => true
    _ => {
      let point = character.to_int()
      formula_cased_extra.any(range => point >= range.0 && point <= range.1)
    }
  }
}

///|
fn formula_case(
  text : String,
  upper : Bool,
  work : FormulaWork,
) -> Value raise @failure.Failure {
  work.spend(amount=text.length() * 2)
  let characters = text.to_array()
  let following = Array::make(characters.length(), false)
  let mut cased = false
  if !upper {
    for index = characters.length() - 1; index >= 0; index = index - 1 {
      following[index] = cased
      if !formula_case_ignorable(characters[index]) {
        cased = formula_cased(characters[index])
      }
    }
  }
  let out = FormulaText::new()
  cased = false
  for index, character in characters {
    let mapped = if upper {
      @ucd.to_uppercase(character)
    } else if character == 'Σ' && cased && !following[index] {
      "ς"
    } else {
      @ucd.to_lowercase(character)
    }
    if !out.append(mapped, work) {
      return Error("#VALUE!")
    }
    if !formula_case_ignorable(character) {
      cased = formula_cased(character)
    }
  }
  Text(out.output.to_string())
}
