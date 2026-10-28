///|
fn Context::math_operation(
  self : Context,
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
  if operation == "docxMathScripts" {
    return session.math_scripts(revision)
  }
  if operation == "docxMathExpressions" {
    return session.math_expressions(revision)
  }
  let expression = operation == "editDocxMath"
  let scripts = operation == "editDocxMathScript"
  guard request is Object(requests) &&
    requests.get(
      if expression {
        "math"
      } else if scripts {
        "script"
      } else {
        "fraction"
      },
    )
    is Some(fraction) &&
    fraction is Object(fields) else {
    @failure.reject("invalid-operation", "Math settings are required")
  }
  let action = field_string(fraction, "action")
  guard ["insert", "update", "delete"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown math action")
  }
  let keys = ["action"]
  let display = if expression &&
    action == "insert" &&
    fields.contains("display") {
    keys.push("display")
    field_boolean(fraction, "display")
  } else {
    false
  }
  if action != "insert" {
    keys.push("id")
  }
  if action != "delete" {
    keys.append(
      if expression {
        ["latex"]
      } else if scripts {
        ["base", "subscript", "superscript"]
      } else {
        ["numerator", "denominator"]
      },
    )
  }
  if action != "delete" && fields.contains("format") {
    keys.push("format")
  }
  guard fields.length() == keys.length() &&
    fields.keys().all(key => keys.contains(key)) else {
    @failure.reject("invalid-operation", "Unknown math settings")
  }
  let format = fields
    .get("format")
    .map(value => {
      guard value is Object(values) &&
        values.length() == 3 &&
        values.keys().all(key => ["family", "size", "color"].contains(key)) else {
        @failure.reject("invalid-operation", "Invalid fraction format")
      }
      @model.CharacterFormat::new(
        family=Set(field_string(value, "family")),
        size=format_number(values, "size"),
        color=Set(field_string(value, "color")),
      )
    })
  let id = if action == "insert" { -1 } else { field_int(fraction, "id") }
  let argument = fn(key) raise @failure.Failure {
    if action == "delete" {
      ""
    } else {
      field_string(fraction, key)
    }
  }
  let result = if expression {
    session.edit_math(
      revision,
      action,
      id,
      argument("latex"),
      probe=self.probe,
      profile=font_profile(request),
      images=self.images,
      format?,
      display~,
    )
  } else if scripts {
    session.edit_math_script(
      revision,
      action,
      id,
      argument("base"),
      argument("subscript"),
      argument("superscript"),
      probe=self.probe,
      profile=font_profile(request),
      images=self.images,
      format?,
    )
  } else {
    session.edit_math_fraction(
      revision,
      action,
      id,
      argument("numerator"),
      argument("denominator"),
      probe=self.probe,
      profile=font_profile(request),
      images=self.images,
      format?,
    )
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
