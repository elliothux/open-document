///|
fn flight_formulas(
  direction : Int,
  axis : Int,
  entrance : Bool,
) -> (String, String) {
  let prefix = if entrance { "#" } else { "" }
  let position = prefix + (if axis == 0 { "ppt_x" } else { "ppt_y" })
  let size = prefix + (if axis == 0 { "ppt_w" } else { "ppt_h" })
  let outside = if (direction & (if axis == 0 { 8 } else { 1 })) != 0 {
    "0-" + size + "/2"
  } else if (direction & (if axis == 0 { 2 } else { 4 })) != 0 {
    "1+" + size + "/2"
  } else {
    position
  }
  if entrance {
    (outside, position)
  } else {
    (position, outside)
  }
}

///|
fn read_flight_animation(
  tree : Tree,
  effect : @xml.Node,
  trigger : String,
) -> SlideAnimation raise @failure.Failure {
  let entrance = effect.attribute("presetClass") == Some("entr")
  let direction = number(effect.attribute("presetSubtype").unwrap_or(""), 1, 12).to_int()
  guard [1, 2, 3, 4, 6, 8, 9, 12].contains(direction) else {
    @failure.reject("protected-content", "Unsupported flight direction")
  }
  if effect.attribute("grpId") is Some(value) && value != "0" {
    @failure.reject("protected-content", "Extended flight animation group")
  }
  let list = animation_child(tree, effect, "childTnLst")
  let children = tree.children.get(list.id).unwrap_or([])
  guard children.length() == 3 &&
    children.filter(node => node.name == "anim").length() == 2 else {
    @failure.reject("protected-content", "Extended flight animation behavior")
  }
  let axes : Map[String, Bool] = Map([])
  let mut target = ""
  let mut duration = 0
  for anim in children.filter(node => node.name == "anim") {
    animation_check(tree, anim, "anim", ["calcmode", "valueType"], [
      "cBhvr", "tavLst",
    ])
    animation_value(anim, "calcmode", "lin")
    animation_value(anim, "valueType", "num")
    let behavior = animation_child(tree, anim, "cBhvr")
    let attributes = animation_child(tree, behavior, "attrNameLst")
    let property = animation_child(tree, attributes, "attrName").text
      .trim()
      .to_owned()
    guard ["ppt_x", "ppt_y"].contains(property) && !axes.contains(property) else {
      @failure.reject("protected-content", "Unsupported flight axis")
    }
    axes[property] = true
    let (object, span) = animation_behavior(tree, behavior, Some(property))
    if target.is_empty() {
      target = object
      duration = span
    } else {
      guard target == object && duration == span else {
        @failure.reject(
          "protected-content", "Mixed flight targets or durations",
        )
      }
    }
    let values = animation_child(tree, anim, "tavLst")
    animation_check(tree, values, "tavLst", [], ["tav"])
    let points = tree.children.get(values.id).unwrap_or([])
    guard points.length() == 2 else {
      @failure.reject("protected-content", "Extended flight keyframes")
    }
    let (from, to) = flight_formulas(
      direction,
      if property == "ppt_x" {
        0
      } else {
        1
      },
      entrance,
    )
    for index, point in points {
      animation_check(tree, point, "tav", ["tm"], ["val"])
      animation_value(point, "tm", if index == 0 { "0" } else { "100000" })
      let value = animation_child(tree, point, "val")
      animation_check(tree, value, "val", [], ["strVal"])
      let string = animation_child(tree, value, "strVal")
      animation_check(tree, string, "strVal", ["val"], [])
      animation_value(string, "val", if index == 0 { from } else { to })
    }
  }
  guard animation_visibility(
      tree,
      animation_child(tree, list, "set"),
      entrance,
      delay=if entrance { 0 } else { duration - 1 },
    ) ==
    target else {
    @failure.reject("protected-content", "Mixed flight visibility target")
  }
  if effect.attribute("dur") is Some(value) &&
    number(value, 1, 60000).to_int() != duration {
    @failure.reject("protected-content", "Conflicting flight duration")
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
    kind: if entrance {
      "flyIn"
    } else {
      "flyOut"
    },
    trigger,
    delay: number(animation_delay(tree, effect), 0, 60000).to_int(),
    duration,
    repeat: repeat / 1000,
    params: [direction.to_double()],
  }
}

///|
fn flight_animation_markup(
  item : SlideAnimation,
  id : Int,
  target : String,
) -> String {
  let entrance = item.kind == "flyIn"
  let result = StringBuilder()
  result.write_string(
    animation_set(
      id,
      target,
      entrance,
      delay=if entrance { 0 } else { item.duration - 1 },
    ),
  )
  for axis in 0..<2 {
    let identity = id + axis + 1
    let property = if axis == 0 { "ppt_x" } else { "ppt_y" }
    let (from, to) = flight_formulas(item.params[0].to_int(), axis, entrance)
    result.write_string(
      "<od:anim calcmode=\"lin\" valueType=\"num\"><od:cBhvr><od:cTn id=\"\{identity}\" dur=\"\{item.duration}\" fill=\"hold\"/><od:tgtEl><od:spTgt spid=\"\{target}\"/></od:tgtEl><od:attrNameLst><od:attrName>\{property}</od:attrName></od:attrNameLst></od:cBhvr><od:tavLst><od:tav tm=\"0\"><od:val><od:strVal val=\"\{from}\"/></od:val></od:tav><od:tav tm=\"100000\"><od:val><od:strVal val=\"\{to}\"/></od:val></od:tav></od:tavLst></od:anim>",
    )
  }
  result.to_string()
}

///|
fn Session::flight_offsets(
  self : Session,
  slide : Slide,
  animations : Array[SlideAnimation],
) -> Array[(Double, Double)] {
  animations.map(item => {
    if !["flyIn", "flyOut"].contains(item.kind) {
      return (0.0, 0.0)
    }
    let object = slide.objects
      .iter()
      .find_first(object => object.id == item.object)
      .unwrap()
    let geometry = object.geometry.unwrap()
    let matrix = geometry.matrix
    let (cx, cy) = matrix.point(geometry.width / 2, geometry.height / 2)
    let width = (matrix.a * geometry.width).abs() +
      (matrix.c * geometry.height).abs()
    let height = (matrix.b * geometry.width).abs() +
      (matrix.d * geometry.height).abs()
    let direction = item.params[0].to_int()
    (
      if (direction & 8) != 0 {
        -width / 2 - cx
      } else if (direction & 2) != 0 {
        self.width + width / 2 - cx
      } else {
        0.0
      },
      if (direction & 1) != 0 {
        -height / 2 - cy
      } else if (direction & 4) != 0 {
        self.height + height / 2 - cy
      } else {
        0.0
      },
    )
  })
}
