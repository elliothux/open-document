///|
fn Session::math_base_style(
  self : Session,
  style : @layout.TextStyle,
) -> @layout.TextStyle raise @failure.Failure {
  {
    ..style,
    font: self.math_font(),
    script: "baseline",
    spacing: 0,
    underline: false,
    strike: false,
    highlight: "",
  }
}

///|
fn Session::read_inline_math(
  self : Session,
  tree : WordTree,
  id : Int,
  style : @layout.TextStyle,
) -> @layout.DrawingFrame raise @failure.Failure {
  let (root, display) = tree.math_source(id)
  let formula = @omml.read(
    tree.nodes,
    tree.children,
    root,
    self.math_base_style(style),
    operator => self.math_nary_limit(operator),
  )
  {
    width: 0,
    height: 0,
    anchor: None,
    content: Math(
      @layout.MathFormula::new(
        formula.expression,
        formula.style,
        display=display is Some(_),
      ),
    ),
  }
}
