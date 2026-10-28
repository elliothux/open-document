///|
/// Create, replace or delete an inline expression using the supported bounded LaTeX syntax.
pub fn Session::edit_math(
  self : Session,
  revision : Int32,
  action : String,
  id : Int32,
  latex : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
  format? : CharacterFormat,
  display~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard !display || action == "insert" else {
    @failure.reject(
      "invalid-operation", "Display placement is only valid on insertion",
    )
  }
  let expression : @layout.MathExpression = if action == "delete" {
    Text("0")
  } else {
    @omml.parse_latex(latex)
  }
  self.edit_inline_math(
    revision,
    action,
    id,
    Math(
      @layout.MathFormula::new(
        expression,
        @layout.TextStyle::new("Cambria Math", 11, "000000"),
      ),
    ),
    plain=false,
    probe~,
    profile~,
    images~,
    format?,
    display~,
  )
}
