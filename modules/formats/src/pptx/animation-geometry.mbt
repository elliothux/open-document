///|
fn animation_integer(value : Double) -> Double raise @failure.Failure {
  guard !value.is_nan() &&
    !value.is_inf() &&
    (value - value.round()).abs() < 0.000001 else {
    @failure.reject(
      "protected-content", "Fractional geometry animation parameter",
    )
  }
  value.round()
}

///|
fn read_geometric_animation(
  tree : Tree,
  effect : @xml.Node,
  trigger : String,
  width : Double,
  height : Double,
) -> SlideAnimation raise @failure.Failure {
  let kind = match
    (effect.attribute("presetClass"), effect.attribute("presetID")) {
    (Some("emph"), Some("6")) => "scale"
    (Some("emph"), Some("8")) => "rotate"
    (Some("path"), Some("0" | "35" | "42" | "49" | "56" | "63" | "64")) =>
      "move"
    _ =>
      @failure.reject(
        "protected-content", "Unsupported geometric animation preset",
      )
  }
  let children = animation_child(tree, effect, "childTnLst")
  let tag = match kind {
    "scale" => "animScale"
    "rotate" => "animRot"
    _ => "animMotion"
  }
  let nodes = tree.children.get(children.id).unwrap_or([])
  guard nodes is [node] else {
    @failure.reject(
      "protected-content", "Extended geometric animation behavior",
    )
  }
  let params = match kind {
    "scale" => {
      animation_check(tree, node, tag, [], ["cBhvr", "by"])
      let by = animation_child(tree, node, "by")
      animation_check(tree, by, "by", ["x", "y"], [])
      [
        animation_integer(
          number(by.attribute("x").unwrap_or(""), 1000, 1000000) / 1000,
        ),
        animation_integer(
          number(by.attribute("y").unwrap_or(""), 1000, 1000000) / 1000,
        ),
      ]
    }
    "rotate" => {
      animation_check(tree, node, tag, ["by"], ["cBhvr"])
      [
        animation_integer(
          number(node.attribute("by").unwrap_or(""), -216000000, 216000000) /
          60000,
        ),
      ]
    }
    _ => {
      animation_check(tree, node, tag, ["origin", "path", "pathEditMode"], [
        "cBhvr",
      ])
      animation_value(node, "origin", "layout")
      if node.attribute("pathEditMode") is Some(value) && value != "relative" {
        @failure.reject(
          "protected-content", "Absolute animation path is protected",
        )
      }
      // shortcut: only a straight relative path is editable; extend with the curve playback implementation.
      let path = node
        .attribute("path")
        .unwrap_or("")
        .replace_all(old="\t", new=" ")
        .replace_all(old="\n", new=" ")
        .replace_all(old="\r", new=" ")
        .split(" ")
        .filter(v => !v.is_empty())
        .map(v => v.to_owned())
        .collect()
      guard path is ["M", "0", "0", "L", x, y, "E"] else {
        @failure.reject(
          "protected-content", "Nonlinear animation path is protected",
        )
      }
      [x, y].mapi((index, text) => {
        let value = @string.parse_double(text) catch {
          _ =>
            @failure.reject(
              "malformed-pptx", "Invalid animation path coordinate",
            )
        }
        guard !value.is_nan() && !value.is_inf() && value.abs() <= 1000000000 else {
          @failure.reject(
            "malformed-pptx", "Animation path coordinate exceeds budget",
          )
        }
        animation_integer(value * (if index == 0 { width } else { height }))
      })
    }
  }
  let (object, duration) = animation_behavior(
    tree,
    animation_child(tree, node, "cBhvr"),
    None,
  )
  if effect.attribute("dur") is Some(value) &&
    number(value, 1, 60000).to_int() != duration {
    @failure.reject("protected-content", "Conflicting animation duration")
  }
  let repeat = number(
    effect.attribute("repeatCount").unwrap_or("1000"),
    1000,
    100000,
  ).to_int()
  guard repeat % 1000 == 0 else {
    @failure.reject("protected-content", "Fractional animation repetition")
  }
  {
    object,
    kind,
    trigger,
    params,
    duration,
    repeat: repeat / 1000,
    delay: number(animation_delay(tree, effect), 0, 60000).to_int(),
  }
}

///|
fn geometric_animation_markup(
  item : SlideAnimation,
  id : Int32,
  target : String,
  width : Double,
  height : Double,
) -> String {
  let behavior = "<od:cBhvr><od:cTn id=\"\{id}\" dur=\"\{item.duration}\" fill=\"hold\"/><od:tgtEl><od:spTgt spid=\"\{target}\"/></od:tgtEl></od:cBhvr>"
  match item.kind {
    "scale" =>
      "<od:animScale>\{behavior}<od:by x=\"\{(item.params[0]*1000).to_int()}\" y=\"\{(item.params[1]*1000).to_int()}\"/></od:animScale>"
    "rotate" =>
      "<od:animRot by=\"\{(item.params[0]*60000).to_int()}\">\{behavior}</od:animRot>"
    _ =>
      "<od:animMotion origin=\"layout\" path=\"M 0 0 L \{item.params[0]/width} \{item.params[1]/height} E\" pathEditMode=\"relative\">\{behavior}</od:animMotion>"
  }
}
