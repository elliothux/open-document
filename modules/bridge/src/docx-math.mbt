///|
fn Foundation::math_operation(
  self : Foundation,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.docx is Some(session) else {
    @failure.reject("invalid-operation", "Open a DOCX session first")
  }
  let revision = field_int(request, "revision")
  if operation == "docxMathFractions" {
    return session.math_fractions(revision)
  }
  guard request is { "fraction": fraction, .. } && fraction is Object(fields) else {
    @failure.reject("invalid-operation", "Fraction settings are required")
  }
  let action = field_string(fraction, "action")
  let keys = match action {
    "insert" => ["action", "numerator", "denominator"]
    "update" => ["action", "id", "numerator", "denominator"]
    "delete" => ["action", "id"]
    _ => @failure.reject("invalid-operation", "Unknown fraction action")
  }
  guard fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Unknown fraction settings")
  }
  let result = session.edit_math_fraction(
    revision,
    action,
    if action == "insert" {
      -1
    } else {
      field_int(fraction, "id")
    },
    if action == "delete" {
      ""
    } else {
      field_string(fraction, "numerator")
    },
    if action == "delete" {
      ""
    } else {
      field_string(fraction, "denominator")
    },
    probe=self.probe,
    profile=xlsx_profile(request),
    images=self.images,
  )
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
