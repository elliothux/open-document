///|
priv struct CellContent {
  value : Value
  formula : String?
  keep_shared : Bool
}

///|
fn cell_content(
  text : String,
  literal : Bool,
) -> CellContent raise @failure.Failure {
  if !literal && text.has_prefix("=") {
    let formula = stored_formula_names(text[1:].to_owned())
    ignore(parse_formula(formula))
    { value: Blank, formula: Some(formula), keep_shared: false, }
  } else {
    { value: input_value(text, literal~), formula: None, keep_shared: false, }
  }
}

///|
fn content_xml(
  prefix : String,
  content : CellContent,
) -> (String, String) raise @failure.Failure {
  guard content.formula is Some(formula) else {
    return value_xml(prefix, content.value)
  }
  let formula = "<\{prefix}f>\{@xml.escape_text(formula)}</\{prefix}f>"
  let (kind, value) = match content.value {
    Blank => ("", "")
    Number(value) => ("", value.to_string())
    Boolean(value) => (" t=\"b\"", if value { "1" } else { "0" })
    Text(value) => (" t=\"str\"", encode_text(value))
    Error(value) => (" t=\"e\"", @xml.escape_text(value))
  }
  (
    kind,
    formula +
    (if content.value == Blank {
      ""
    } else {
      "<\{prefix}v>\{value}</\{prefix}v>"
    }),
  )
}
