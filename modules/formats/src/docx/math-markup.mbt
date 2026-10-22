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
fn math_content_markup(
  content : @layout.DrawingContent,
  inherited~ : Bool = false,
) -> String raise @failure.Failure {
  let texts = match content {
    Fraction(fraction) => [fraction.numerator, fraction.denominator]
    Scripts(scripts) => {
      guard !scripts.base.is_empty() &&
        (!scripts.subscript.is_empty() || !scripts.superscript.is_empty()) else {
        @failure.reject(
          "invalid-operation", "Script requires a base and at least one index",
        )
      }
      [scripts.base, scripts.subscript, scripts.superscript].filter(text => {
        !text.is_empty()
      })
    }
    _ => @failure.reject("invalid-operation", "Expected mathematical content")
  }
  guard texts.fold(init=0, (sum, text) => sum + text.length()) <= 4096 else {
    @failure.reject("limit-exceeded", "Mathematical arguments exceed budget")
  }
  guard texts.all(text => {
    !text.is_empty() &&
    @xml.valid_text(text) &&
    text.iter().all(ch => ch.to_int() >= 32 && ch != '\u2028' && ch != '\u2029')
  }) else {
    @failure.reject(
      "invalid-operation", "Mathematical arguments require single-line text",
    )
  }
  match content {
    Fraction(fraction) =>
      math_fraction_markup(
        fraction.numerator,
        fraction.denominator,
        style=if inherited { None } else { Some(fraction.style) },
      )
    Scripts(scripts) => {
      let frame : @layout.DrawingFrame = {
        width: 0,
        height: 0,
        anchor: None,
        content,
      }
      frame.validate()
      let kind = if scripts.subscript.is_empty() {
        "sSup"
      } else if scripts.superscript.is_empty() {
        "sSub"
      } else {
        "sSubSup"
      }
      let style = if inherited { None } else { Some(scripts.style) }
      let base = math_run_markup(scripts.base, style)
      let lower = if scripts.subscript.is_empty() {
        ""
      } else {
        "<m:sub>\{math_run_markup(scripts.subscript, style)}</m:sub>"
      }
      let upper = if scripts.superscript.is_empty() {
        ""
      } else {
        "<m:sup>\{math_run_markup(scripts.superscript, style)}</m:sup>"
      }
      "<m:oMath xmlns:m=\"\{math_uri}\"><m:\{kind}><m:e>\{base}</m:e>\{lower}\{upper}</m:\{kind}></m:oMath>"
    }
    _ =>
      @failure.reject(
        "protected-content", "Expected a supported native math expression",
      )
  }
}

///|
fn math_content_style(
  content : @layout.DrawingContent,
) -> @layout.TextStyle raise @failure.Failure {
  match content {
    Fraction(fraction) => fraction.style
    Scripts(scripts) => scripts.style
    _ => @failure.reject("invalid-operation", "Expected mathematical content")
  }
}

///|
fn math_with_style(
  content : @layout.DrawingContent,
  style : @layout.TextStyle,
) -> @layout.DrawingContent raise @failure.Failure {
  match content {
    Fraction(fraction) =>
      Fraction(
        @layout.MathFraction::new(
          fraction.numerator,
          fraction.denominator,
          style,
        ),
      )
    Scripts(scripts) =>
      Scripts(
        @layout.MathScripts::new(
          scripts.base,
          scripts.subscript,
          scripts.superscript,
          style,
        ),
      )
    _ => @failure.reject("invalid-operation", "Expected mathematical content")
  }
}
