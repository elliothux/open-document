///|
fn mathml_indices(
  base : String,
  lower : String?,
  upper : String?,
  limits : Bool,
) -> String {
  let tag = match (lower, upper) {
    (Some(_), Some(_)) => if limits { "munderover" } else { "msubsup" }
    (Some(_), None) => if limits { "munder" } else { "msub" }
    (None, Some(_)) => if limits { "mover" } else { "msup" }
    (None, None) => return base
  }
  "<\{tag}>\{base}\{lower.unwrap_or("")}\{upper.unwrap_or("")}</\{tag}>"
}

///|
fn mathml_expression(
  value : @layout.MathExpression,
  display : Bool,
) -> String raise @failure.Failure {
  match value {
    Text(text) =>
      "<mtext style=\"white-space:pre\">\{@xml.escape_text(text)}</mtext>"
    Row(children) =>
      "<mrow>\{children.map(child => mathml_expression(child, display)).join("")}</mrow>"
    Fraction(numerator, denominator) =>
      "<mfrac>\{mathml_expression(numerator, false)}\{mathml_expression(denominator, false)}</mfrac>"
    Scripts(base, lower, upper) =>
      mathml_indices(
        mathml_expression(base, display),
        lower.map(value => mathml_expression(value, false)),
        upper.map(value => mathml_expression(value, false)),
        false,
      )
    Root(degree, body) => {
      let body = mathml_expression(body, display)
      match degree {
        None => "<msqrt>\{body}</msqrt>"
        Some(degree) =>
          "<mroot>\{body}\{mathml_expression(degree, false)}</mroot>"
      }
    }
    Delimited(open, close, separator, arguments) => {
      let fence = fn(text : String) raise @failure.Failure {
        if text.is_empty() {
          ""
        } else {
          "<mo fence=\"true\" stretchy=\"true\" symmetric=\"true\">\{@xml.escape_text(text)}</mo>"
        }
      }
      let separator = if separator.is_empty() {
        ""
      } else {
        "<mo separator=\"true\">\{@xml.escape_text(separator)}</mo>"
      }
      "<mrow>\{fence(open)}\{arguments.map(value => mathml_expression(value, display)).join(separator)}\{fence(close)}</mrow>"
    }
    Nary(operator, location, lower, upper, body) => {
      let sign = "<mo largeop=\"\{display}\" movablelimits=\"false\">\{@xml.escape_text(operator)}</mo>"
      let sign = mathml_indices(
        sign,
        lower.map(value => mathml_expression(value, false)),
        upper.map(value => mathml_expression(value, false)),
        display && location == "undOvr",
      )
      "<mrow>\{sign}\{mathml_expression(body, display)}</mrow>"
    }
    Matrix(base, columns, rows) => {
      let rows = rows
        .map(row => {
          "<mtr>" +
          row
          .mapi((index, cell) => {
            let text = cell
              .map(value => mathml_expression(value, false))
              .unwrap_or("<mtext>⬚</mtext>")
            "<mtd style=\"\{mathml_alignment(columns[index])}\">\{text}</mtd>"
          })
          .join("") +
          "</mtr>"
        })
        .join("")
      mathml_table(base, rows)
    }
    EquationArray(base, rows) => {
      let rows = rows
        .map(row => {
          let blank = row.iter().all(value => value is None)
          "<mtr>" +
          row
          .mapi((index, cell) => {
            let lone = index % 2 == 0 && index + 1 == row.length()
            let align = if lone {
              "center"
            } else if index % 2 == 0 {
              "right"
            } else {
              "left"
            }
            let span = if lone { " columnspan=\"2\"" } else { "" }
            let text = cell
              .map(value => mathml_expression(value, display))
              .unwrap_or(
                if blank && index == 0 {
                  "<mtext>⬚</mtext>"
                } else {
                  "<mrow></mrow>"
                },
              )
            "<mtd\{span} style=\"padding:0.25ex 0;\{mathml_alignment(align)}\">\{text}</mtd>"
          })
          .join("") +
          "</mtr>"
        })
        .join("")
      mathml_table(base, rows, display~)
    }
  }
}

///|
fn mathml_alignment(value : String) -> String {
  // Chromium aligns anonymous math rows with its legacy table alignment values.
  "text-align:\{value};text-align:-webkit-\{value}"
}

///|
fn mathml_table(
  base : String,
  rows : String,
  display~ : Bool = false,
) -> String {
  let alignment = if base == "center" { "" } else { "vertical-align:\{base};" }
  "<mtable style=\"\{alignment}border-spacing:0;math-style:\{if display { "normal" } else { "compact" }}\">\{rows}</mtable>"
}

///|
fn mathml_markup(
  formula : @layout.MathFormula,
) -> String raise @failure.Failure {
  let family = formula.style.font.split("|").head().unwrap().to_owned()
  let css = "font-family:\{markup_css_string(family)};font-size:\{formula.style.size}pt;color:#\{formula.style.color}"
  "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" dir=\"ltr\" display=\"\{if formula.display { "block" } else { "inline" }}\" aria-label=\"\{property_attribute(formula.expression.linear_text())}\" style=\"\{property_attribute(css)}\">\{mathml_expression(formula.expression, formula.display)}</math>"
}
