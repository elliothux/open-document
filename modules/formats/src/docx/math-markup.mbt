///|
fn math_content_markup(
  content : @layout.DrawingContent,
  inherited~ : Bool = false,
) -> String raise @failure.Failure {
  guard content is Math(formula) else {
    @failure.reject("invalid-operation", "Expected mathematical content")
  }
  @omml.markup(formula, inherited~)
}

///|
fn math_content_style(
  content : @layout.DrawingContent,
) -> @layout.TextStyle raise @failure.Failure {
  match content {
    Math(formula) => formula.style
    _ => @failure.reject("invalid-operation", "Expected mathematical content")
  }
}

///|
fn math_with_style(
  content : @layout.DrawingContent,
  style : @layout.TextStyle,
) -> @layout.DrawingContent raise @failure.Failure {
  match content {
    Math(formula) => Math(@layout.MathFormula::new(formula.expression, style))
    _ => @failure.reject("invalid-operation", "Expected mathematical content")
  }
}

///|
fn math_plain_index(
  value : @layout.MathExpression?,
) -> String raise @failure.Failure {
  match value {
    None => ""
    Some(Text(text)) => text
    _ =>
      @failure.reject(
        "unsupported-math", "Nested math requires structural editing",
      )
  }
}

///|
fn math_plain_arguments(
  content : @layout.DrawingContent,
) -> (Bool, Array[String]) raise @failure.Failure {
  match content {
    Math({ expression: Fraction(Text(num), Text(den)), .. }) =>
      (false, [num, den])
    Math({ expression: Scripts(Text(base), sub, sup), .. }) =>
      (true, [base, math_plain_index(sub), math_plain_index(sup)])
    _ =>
      @failure.reject(
        "unsupported-math", "Nested math requires structural editing",
      )
  }
}
