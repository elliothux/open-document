///|
priv struct MathBox {
  width : Double
  height : Double
  ascent : Double
  primitives : Array[PositionedPrimitive]
  textAscent : Double?
}

///|
fn MathBox::place(
  self : MathBox,
  into : Array[PositionedPrimitive],
  x : Double,
  y : Double,
) -> Unit {
  into.push(Transform({ a: 1, b: 0, c: 0, d: 1, e: x, f: y, }))
  into.append(self.primitives)
  into.push(Restore)
}

///|
fn MathExpression::measure(
  self : MathExpression,
  style : TextStyle,
  probe : TextProbe,
  profile : Map[String, String],
  paths : Ref[Int],
) -> MathBox raise @failure.Failure {
  let box = match self {
    Matrix(base, columns, rows) =>
      measure_math_matrix(
        base,
        columns,
        rows.map(row => {
          row.map(value => {
            value.map(value => value.measure(style, probe, profile, paths))
          })
        }),
        style,
        probe,
        profile,
        paths,
      )
    Nary(operator, _, lower, upper, body) => {
      let sign = probe.math_nary_sign(operator, style, profile, paths)
      let argument = { ..style, size: style.size * 0.76, }
      let operator = if lower is None && upper is None {
        sign
      } else {
        measure_math_scripts(
          sign,
          lower.map(value => value.measure(argument, probe, profile, paths)),
          upper.map(value => value.measure(argument, probe, profile, paths)),
          style,
          probe,
          profile,
        )
      }
      measure_math_nary(
        operator,
        body.measure(style, probe, profile, paths),
        style.size,
      )
    }
    Delimited(open, close, separator, arguments) =>
      measure_math_delimited(
        open,
        close,
        separator,
        arguments.map(value => value.measure(style, probe, profile, paths)),
        style,
        probe,
        profile,
        paths,
      )
    Text(text) => {
      let block = probe.text_block(text, style, profile, 14400, false)
      let (ascent, _) = probe.line_metrics(
        probe.math_font_index(style, profile),
        style.size,
      )
      {
        width: block.widths[0],
        height: block.height,
        ascent,
        primitives: block.lines[0],
        textAscent: Some(ascent),
      }
    }
    Row(children) => {
      let boxes = children.map(child => {
        child.measure(style, probe, profile, paths)
      })
      let ascent = boxes.fold(init=0.0, (value, box) => value.max(box.ascent))
      let descent = boxes.fold(init=0.0, (value, box) => {
        value.max(box.height - box.ascent)
      })
      let mut width = 0.0
      let primitives : Array[PositionedPrimitive] = []
      for box in boxes {
        box.place(primitives, width, ascent - box.ascent)
        width += box.width
      }
      {
        width,
        height: ascent + descent,
        ascent,
        primitives,
        textAscent: boxes.last().bind(box => box.textAscent),
      }
    }
    Fraction(num, den) => {
      let argument = { ..style, size: style.size * 0.76, }
      measure_math_fraction(
        num.measure(argument, probe, profile, paths),
        den.measure(argument, probe, profile, paths),
        argument,
        probe,
        profile,
      )
    }
    Scripts(base, sub, sup) => {
      let argument = { ..style, size: style.size * 0.76, }
      measure_math_scripts(
        base.measure(style, probe, profile, paths),
        sub.map(value => value.measure(argument, probe, profile, paths)),
        sup.map(value => value.measure(argument, probe, profile, paths)),
        style,
        probe,
        profile,
      )
    }
    Root(degree, radicand) => {
      let index_style = { ..style, size: style.size * 0.6498, }
      measure_math_root(
        degree.map(value => value.measure(index_style, probe, profile, paths)),
        radicand.measure(style, probe, profile, paths),
        style,
        probe,
        profile,
      )
    }
  }
  guard [box.width, box.height, box.ascent].all(value => {
      !value.is_nan() && !value.is_inf() && value >= 0 && value <= 14400
    }) &&
    box.width > 0 &&
    box.height > 0 &&
    box.ascent <= box.height else {
    @failure.reject(
      "limit-exceeded", "Mathematical expression exceeds drawing dimensions",
    )
  }
  box
}

///|
fn MathFormula::prepare(
  self : MathFormula,
  probe : TextProbe,
  profile : Map[String, String],
) -> DrawingFrame raise @failure.Failure {
  self.validate()
  let box = self.expression.measure(self.style, probe, profile, Ref(0))
  {
    width: box.width,
    height: box.height,
    anchor: None,
    content: Math({ ..self, ascent: box.ascent, primitives: box.primitives, }),
  }
}
