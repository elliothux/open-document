///|
fn animation_container(
  tree : Tree,
  par : @xml.Node,
  effect~ : Bool = false,
) -> @xml.Node raise @failure.Failure {
  animation_check(tree, par, "par", [], ["cTn"])
  let ctn = animation_child(tree, par, "cTn")
  animation_check(
    tree,
    ctn,
    "cTn",
    if effect {
      [
        "id", "fill", "presetID", "presetClass", "presetSubtype", "nodeType", "dur",
        "grpId", "repeatCount",
      ]
    } else {
      ["id", "fill"]
    },
    ["stCondLst", "childTnLst"],
  )
  animation_value(ctn, "fill", "hold")
  let children = animation_child(tree, ctn, "childTnLst")
  animation_check(
    tree,
    children,
    "childTnLst",
    [],
    if effect {
      ["set", "anim", "animScale", "animRot", "animMotion"]
    } else {
      ["par"]
    },
  )
  ctn
}

///|
fn animation_delay(
  tree : Tree,
  ctn : @xml.Node,
) -> String raise @failure.Failure {
  let conditions = animation_child(tree, ctn, "stCondLst")
  animation_check(tree, conditions, "stCondLst", [], ["cond"])
  let condition = animation_child(tree, conditions, "cond")
  animation_check(tree, condition, "cond", ["delay"], [])
  condition.attribute("delay").unwrap_or("")
}

///|
fn animation_automatic(
  tree : Tree,
  ctn : @xml.Node,
  main : @xml.Node,
) -> Bool raise @failure.Failure {
  let conditions = animation_child(tree, ctn, "stCondLst")
  animation_check(tree, conditions, "stCondLst", [], ["cond"])
  let nodes = tree.children.get(conditions.id).unwrap_or([])
  if nodes is [node] {
    animation_check(tree, node, "cond", ["delay"], [])
    return match node.attribute("delay") {
      Some("indefinite") => false
      Some("0") => true
      _ => @failure.reject("protected-content", "Unsupported animation start")
    }
  }
  guard nodes is [wait, begin] else {
    @failure.reject("protected-content", "Unsupported animation conditions")
  }
  animation_check(tree, wait, "cond", ["delay"], [])
  animation_value(wait, "delay", "indefinite")
  animation_check(tree, begin, "cond", ["evt", "delay"], ["tn"])
  animation_value(begin, "evt", "onBegin")
  animation_value(begin, "delay", "0")
  let reference = animation_child(tree, begin, "tn")
  animation_check(tree, reference, "tn", ["val"], [])
  guard reference.attribute("val") == main.attribute("id") else {
    @failure.reject("protected-content", "External animation time reference")
  }
  true
}

///|
fn animation_behavior(
  tree : Tree,
  behavior : @xml.Node,
  property : String?,
  delay~ : Int = 0,
) -> (String, Int) raise @failure.Failure {
  animation_check(tree, behavior, "cBhvr", ["override"], [
    "cTn", "tgtEl", "attrNameLst",
  ])
  if behavior.attribute("override") is Some(value) && value != "childStyle" {
    @failure.reject("protected-content", "Unsupported animation override")
  }
  let clock = animation_child(tree, behavior, "cTn")
  animation_check(tree, clock, "cTn", ["id", "dur", "fill"], ["stCondLst"])
  if clock.attribute("fill") is Some(value) && value != "hold" {
    @failure.reject("protected-content", "Unsupported animation fill")
  }
  if tree.one(clock.id, "stCondLst", uri=presentation_uri) is Some(_) {
    guard animation_delay(tree, clock) == delay.to_string() else {
      @failure.reject("protected-content", "Delayed animation behavior")
    }
  } else if delay != 0 {
    @failure.reject("protected-content", "Missing animation behavior delay")
  }
  let target = animation_child(tree, behavior, "tgtEl")
  animation_check(tree, target, "tgtEl", [], ["spTgt"])
  let object = animation_child(tree, target, "spTgt")
  animation_check(tree, object, "spTgt", ["spid"], [])
  if property is Some(property) {
    let attributes = animation_child(tree, behavior, "attrNameLst")
    animation_check(tree, attributes, "attrNameLst", [], ["attrName"])
    let attribute = animation_child(tree, attributes, "attrName")
    guard attribute.text.trim() == property &&
      attribute.attributes.is_empty() &&
      tree.children.get(attribute.id).unwrap_or([]).is_empty() else {
      @failure.reject("protected-content", "Unsupported animated property")
    }
  } else {
    guard tree.one(behavior.id, "attrNameLst", uri=presentation_uri) is None else {
      @failure.reject(
        "protected-content", "Extended geometric animation property",
      )
    }
  }
  (
    tree.part + "#" + source_identity(object.attribute("spid").unwrap_or("")),
    number(clock.attribute("dur").unwrap_or(""), 1, 60000).to_int(),
  )
}

///|
fn animation_visibility(
  tree : Tree,
  set : @xml.Node,
  visible : Bool,
  delay~ : Int = 0,
) -> String raise @failure.Failure {
  animation_check(tree, set, "set", [], ["cBhvr", "to"])
  let (target, duration) = animation_behavior(
    tree,
    animation_child(tree, set, "cBhvr"),
    Some("style.visibility"),
    delay~,
  )
  guard duration == 1 else {
    @failure.reject("protected-content", "Extended visibility duration")
  }
  let to = animation_child(tree, set, "to")
  animation_check(tree, to, "to", [], ["strVal"])
  let value = animation_child(tree, to, "strVal")
  animation_check(tree, value, "strVal", ["val"], [])
  animation_value(value, "val", if visible { "visible" } else { "hidden" })
  target
}

///|
fn read_animation_effect(
  tree : Tree,
  par : @xml.Node,
  width : Double,
  height : Double,
) -> SlideAnimation raise @failure.Failure {
  let effect = animation_container(tree, par, effect=true)
  let trigger = match effect.attribute("nodeType") {
    Some("clickEffect") => "click"
    Some("withEffect") => "with"
    Some("afterEffect") => "after"
    _ => @failure.reject("protected-content", "Unsupported animation trigger")
  }
  if effect.attribute("presetID") == Some("2") &&
    [Some("entr"), Some("exit")].contains(effect.attribute("presetClass")) {
    return read_flight_animation(tree, effect, trigger)
  }
  for (key, expected) in [("presetSubtype", "0"), ("grpId", "0")] {
    if effect.attribute(key) is Some(value) && value != expected {
      @failure.reject("protected-content", "Extended animation preset")
    }
  }
  if [Some("emph"), Some("path")].contains(effect.attribute("presetClass")) {
    return read_geometric_animation(tree, effect, trigger, width, height)
  }
  let entrance = match effect.attribute("presetClass") {
    Some("entr") => true
    Some("exit") => false
    _ => @failure.reject("protected-content", "Unsupported animation class")
  }
  let children = animation_child(tree, effect, "childTnLst")
  let fade = effect.attribute("presetID") == Some("10")
  let (target, duration) = if fade {
    let anim = animation_child(tree, children, "anim")
    animation_check(
      tree,
      anim,
      "anim",
      ["calcmode", "valueType", "from", "to"],
      ["cBhvr"],
    )
    animation_value(anim, "calcmode", "lin")
    animation_value(anim, "valueType", "num")
    animation_value(anim, "from", if entrance { "1" } else { "0" })
    animation_value(anim, "to", if entrance { "0" } else { "1" })
    let (target, duration) = animation_behavior(
      tree,
      animation_child(tree, anim, "cBhvr"),
      Some("style.opacity"),
    )
    if entrance {
      guard animation_visibility(
          tree,
          animation_child(tree, children, "set"),
          true,
        ) ==
        target else {
        @failure.reject("protected-content", "Mixed animation targets")
      }
    } else {
      guard tree.one(children.id, "set", uri=presentation_uri) is None else {
        @failure.reject("protected-content", "Extended exit behavior")
      }
    }
    (target, duration)
  } else {
    animation_value(effect, "presetID", "1")
    guard tree.one(children.id, "anim", uri=presentation_uri) is None else {
      @failure.reject("protected-content", "Extended visibility animation")
    }
    (
      animation_visibility(
        tree,
        animation_child(tree, children, "set"),
        entrance,
      ),
      1,
    )
  }
  guard tree.children
    .get(children.id)
    .unwrap_or([])
    .all(node => ["set", "anim"].contains(node.name)) else {
    @failure.reject("protected-content", "Extended visibility behavior")
  }
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
    object: target,
    kind: if fade {
      if entrance {
        "fadeIn"
      } else {
        "fadeOut"
      }
    } else if entrance {
      "appear"
    } else {
      "disappear"
    },
    trigger,
    delay: number(animation_delay(tree, effect), 0, 60000).to_int(),
    duration,
    repeat: repeat / 1000,
    params: [],
  }
}
