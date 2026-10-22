///|
fn math_run_markup(
  text : String,
  style : @layout.TextStyle?,
) -> String raise @failure.Failure {
  let properties = match style {
    None => ""
    Some(style) => {
      let family = property_attribute(style.font)
      "<od:rPr xmlns:od=\"\{word_uri}\"><od:rFonts od:ascii=\"\{family}\" od:hAnsi=\"\{family}\"/><od:color od:val=\"\{style.color}\"/><od:sz od:val=\"\{(style.size*2).round().to_int()}\"/></od:rPr>"
    }
  }
  "<m:r><m:rPr><m:sty m:val=\"p\"/></m:rPr>\{properties}<m:t xml:space=\"preserve\">\{@xml.escape_text(text)}</m:t></m:r>"
}

///|
fn math_expression_markup(
  expression : @layout.MathExpression,
  style : @layout.TextStyle?,
) -> String raise @failure.Failure {
  match expression {
    Root(degree, radicand) => {
      let hidden = if degree is None { "1" } else { "0" }
      let degree = degree
        .map(value => math_expression_markup(value, style))
        .unwrap_or("")
      "<m:rad><m:radPr><m:degHide m:val=\"\{hidden}\"/></m:radPr><m:deg>\{degree}</m:deg><m:e>\{math_expression_markup(radicand,style)}</m:e></m:rad>"
    }
    Text(text) => math_run_markup(text, style)
    Row(children) =>
      children.map(child => math_expression_markup(child, style)).join("")
    Fraction(num, den) =>
      "<m:f><m:fPr><m:type m:val=\"bar\"/></m:fPr><m:num>\{math_expression_markup(num,style)}</m:num><m:den>\{math_expression_markup(den,style)}</m:den></m:f>"
    Scripts(base, sub, sup) => {
      let kind = if sub is None {
        "sSup"
      } else if sup is None {
        "sSub"
      } else {
        "sSubSup"
      }
      let lower = sub
        .map(value => "<m:sub>\{math_expression_markup(value,style)}</m:sub>")
        .unwrap_or("")
      let upper = sup
        .map(value => "<m:sup>\{math_expression_markup(value,style)}</m:sup>")
        .unwrap_or("")
      "<m:\{kind}><m:e>\{math_expression_markup(base,style)}</m:e>\{lower}\{upper}</m:\{kind}>"
    }
  }
}

///|
fn math_content_markup(
  content : @layout.DrawingContent,
  inherited~ : Bool = false,
) -> String raise @failure.Failure {
  guard content is Math(formula) else {
    @failure.reject("invalid-operation", "Expected mathematical content")
  }
  let frame : @layout.DrawingFrame = {
    width: 0,
    height: 0,
    anchor: None,
    content,
  }
  frame.validate() catch {
    @failure.Failure(code="unsupported-math", message~, ..) =>
      @failure.reject("invalid-operation", message)
    error => raise error
  }
  let style = if inherited { None } else { Some(formula.style) }
  "<m:oMath xmlns:m=\"\{math_uri}\">\{math_expression_markup(formula.expression,style)}</m:oMath>"
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
