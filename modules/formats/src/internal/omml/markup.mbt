///|
/// Serializes the uniform font properties shared by math authoring and range edits.
pub fn math_properties_markup(
  style : @layout.TextStyle,
  drawing~ : Bool = false,
) -> String raise @failure.Failure {
  let family = property_attribute(style.font)
  if drawing {
    return "<a:rPr xmlns:a=\"\{drawing_uri}\" sz=\"\{(style.size*100).round().to_int()}\"><a:solidFill><a:srgbClr val=\"\{style.color}\"/></a:solidFill><a:latin typeface=\"\{family}\"/></a:rPr>"
  }
  "<od:rPr xmlns:od=\"\{word_uri}\"><od:rFonts od:ascii=\"\{family}\" od:hAnsi=\"\{family}\"/><od:color od:val=\"\{style.color}\"/><od:sz od:val=\"\{(style.size*2).round().to_int()}\"/></od:rPr>"
}

///|
fn math_run_markup(
  text : String,
  style : @layout.TextStyle?,
  drawing~ : Bool = false,
) -> String raise @failure.Failure {
  let properties = match style {
    None => ""
    Some(style) => math_properties_markup(style, drawing~)
  }
  "<m:r><m:rPr><m:sty m:val=\"p\"/></m:rPr>\{properties}<m:t xml:space=\"preserve\">\{@xml.escape_text(text)}</m:t></m:r>"
}

///|
fn math_expression_markup(
  expression : @layout.MathExpression,
  style : @layout.TextStyle?,
  drawing~ : Bool = false,
) -> String raise @failure.Failure {
  match expression {
    EquationArray(base, rows) => {
      let control = style
        .map(value => {
          "<m:ctrlPr>" + math_properties_markup(value, drawing~) + "</m:ctrlPr>"
        })
        .unwrap_or("")
      let rows = rows
        .map(row => {
          "<m:e>" +
          row
          .map(value => {
            value
            .map(value => equation_cell_markup(value, style, drawing~))
            .unwrap_or("")
          })
          .join(math_run_markup("&", style, drawing~)) +
          "</m:e>"
        })
        .join("")
      "<m:eqArr><m:eqArrPr><m:baseJc m:val=\"" +
      base +
      "\"/>" +
      control +
      "</m:eqArrPr>" +
      rows +
      "</m:eqArr>"
    }
    Matrix(base, columns, rows) => {
      let control = style
        .map(value => {
          "<m:ctrlPr>" + math_properties_markup(value, drawing~) + "</m:ctrlPr>"
        })
        .unwrap_or("")
      let columns = columns
        .map(value => {
          "<m:mc><m:mcPr><m:count m:val=\"1\"/><m:mcJc m:val=\"" +
          value +
          "\"/></m:mcPr></m:mc>"
        })
        .join("")
      let rows = rows
        .map(row => {
          "<m:mr>" +
          row
          .map(value => {
            "<m:e>" +
            value
            .map(value => math_expression_markup(value, style, drawing~))
            .unwrap_or("") +
            "</m:e>"
          })
          .join("") +
          "</m:mr>"
        })
        .join("")
      "<m:m><m:mPr><m:baseJc m:val=\"\{base}\"/><m:mcs>\{columns}</m:mcs>\{control}</m:mPr>\{rows}</m:m>"
    }
    Nary(operator, location, lower, upper, body) => {
      let hidden_lower = if lower is None { "1" } else { "0" }
      let hidden_upper = if upper is None { "1" } else { "0" }
      let lower = lower
        .map(value => math_expression_markup(value, style, drawing~))
        .unwrap_or("")
      let upper = upper
        .map(value => math_expression_markup(value, style, drawing~))
        .unwrap_or("")
      "<m:nary><m:naryPr><m:chr m:val=\"\{property_attribute(operator)}\"/><m:limLoc m:val=\"\{location}\"/><m:subHide m:val=\"\{hidden_lower}\"/><m:supHide m:val=\"\{hidden_upper}\"/></m:naryPr><m:sub>\{lower}</m:sub><m:sup>\{upper}</m:sup><m:e>\{math_expression_markup(body,style,drawing~)}</m:e></m:nary>"
    }
    Delimited(open, close, separator, arguments) => {
      let args = arguments
        .map(value => {
          "<m:e>" + math_expression_markup(value, style, drawing~) + "</m:e>"
        })
        .join("")
      "<m:d><m:dPr><m:begChr m:val=\"\{property_attribute(open)}\"/><m:sepChr m:val=\"\{property_attribute(separator)}\"/><m:endChr m:val=\"\{property_attribute(close)}\"/></m:dPr>\{args}</m:d>"
    }
    Root(degree, radicand) => {
      let hidden = if degree is None { "1" } else { "0" }
      let degree = degree
        .map(value => math_expression_markup(value, style, drawing~))
        .unwrap_or("")
      "<m:rad><m:radPr><m:degHide m:val=\"\{hidden}\"/></m:radPr><m:deg>\{degree}</m:deg><m:e>\{math_expression_markup(radicand,style,drawing~)}</m:e></m:rad>"
    }
    Text(text) => math_run_markup(text, style, drawing~)
    Row(children) =>
      children
      .map(child => math_expression_markup(child, style, drawing~))
      .join("")
    Fraction(num, den) =>
      "<m:f><m:fPr><m:type m:val=\"bar\"/></m:fPr><m:num>\{math_expression_markup(num,style,drawing~)}</m:num><m:den>\{math_expression_markup(den,style,drawing~)}</m:den></m:f>"
    Scripts(base, sub, sup) => {
      let kind = if sub is None {
        "sSup"
      } else if sup is None {
        "sSub"
      } else {
        "sSubSup"
      }
      let lower = sub
        .map(value => {
          "<m:sub>\{math_expression_markup(value,style,drawing~)}</m:sub>"
        })
        .unwrap_or("")
      let upper = sup
        .map(value => {
          "<m:sup>\{math_expression_markup(value,style,drawing~)}</m:sup>"
        })
        .unwrap_or("")
      "<m:\{kind}><m:e>\{math_expression_markup(base,style,drawing~)}</m:e>\{lower}\{upper}</m:\{kind}>"
    }
  }
}

///|
fn property_attribute(value : String) -> String raise @failure.Failure {
  @xml.escape_text(value).split("\"").join("&quot;")
}

///|
pub fn markup(
  formula : @layout.MathFormula,
  inherited~ : Bool = false,
  drawing~ : Bool = false,
) -> String raise @failure.Failure {
  let frame : @layout.DrawingFrame = {
    width: 0,
    height: 0,
    anchor: None,
    content: Math(formula),
  }
  frame.validate() catch {
    @failure.Failure(code="unsupported-math", message~, ..) =>
      @failure.reject("invalid-operation", message)
    error => raise error
  }
  let style = if inherited { None } else { Some(formula.style) }
  "<m:oMath xmlns:m=\"\{math_uri}\">\{math_expression_markup(formula.expression,style,drawing~)}</m:oMath>"
}
