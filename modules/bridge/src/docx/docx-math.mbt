///|
#derive(@json.FromJson)
priv struct MathEditCommandRequest {
  revision : @common.RequestInt
  profile : @common.RequestProfile
  math : Json?
  script : Json?
  fraction : Json?
}

///|
#derive(@json.FromJson)
priv struct MathFontRequest {
  family : String
  color : String
}

///|
#derive(@json.FromJson)
priv struct MathExpressionRequest {
  latex : String
}

///|
#derive(@json.FromJson)
priv struct MathScriptRequest {
  base : String
  subscript : String
  superscript : String
}

///|
#derive(@json.FromJson)
priv struct MathFractionRequest {
  numerator : String
  denominator : String
}

///|
fn Context::edit_math_command(
  self : Context,
  session : @model.Session,
  kind : String,
  request : Json,
) -> Json raise @failure.Failure {
  let input : MathEditCommandRequest = @common.request(request)
  let revision = input.revision.value
  let expression = kind == "math"
  let scripts = kind == "script"
  let settings = if expression {
    input.math
  } else if scripts {
    input.script
  } else {
    input.fraction
  }
  guard settings is Some(Object(fields) as fraction) else {
    @failure.reject("invalid-operation", "Math settings are required")
  }
  let command : @common.ActionRequest = @common.request(fraction)
  let action = command.action
  guard ["insert", "update", "delete"].contains(action) else {
    @failure.reject("invalid-operation", "Unknown math action")
  }
  let keys = ["action"]
  let display = if expression &&
    action == "insert" &&
    fields.contains("display") {
    keys.push("display")
    let display : Bool = @common.request(fields["display"])
    display
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
      let font : MathFontRequest = @common.request(value)
      @model.CharacterFormat::new(
        family=Set(font.family),
        size=format_number(values, "size"),
        color=Set(font.color),
      )
    })
  let id = if action == "insert" {
    -1
  } else {
    let id : @common.RequestInt = @common.request(fields["id"])
    id.value
  }
  let result = if expression {
    let latex = if action == "delete" {
      ""
    } else {
      let input : MathExpressionRequest = @common.request(fraction)
      input.latex
    }
    session.edit_math(
      revision,
      action,
      id,
      latex,
      probe=self.probe,
      profile=input.profile.value,
      images=self.images,
      format?,
      display~,
    )
  } else if scripts {
    let (base, subscript, superscript) = if action == "delete" {
      ("", "", "")
    } else {
      let input : MathScriptRequest = @common.request(fraction)
      (input.base, input.subscript, input.superscript)
    }
    session.edit_math_script(
      revision,
      action,
      id,
      base,
      subscript,
      superscript,
      probe=self.probe,
      profile=input.profile.value,
      images=self.images,
      format?,
    )
  } else {
    let (numerator, denominator) = if action == "delete" {
      ("", "")
    } else {
      let input : MathFractionRequest = @common.request(fraction)
      (input.numerator, input.denominator)
    }
    session.edit_math_fraction(
      revision,
      action,
      id,
      numerator,
      denominator,
      probe=self.probe,
      profile=input.profile.value,
      images=self.images,
      format?,
    )
  }
  self.clear_edit_layout(result, previous=revision)
}
