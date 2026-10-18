///|
pub(all) struct SlideAnimation {
  object : String
  kind : String
  trigger : String
  delay : Int
  duration : Int
  repeat : Int
  params : Array[Double]
} derive(Eq, ToJson)

///|
pub extend SlideAnimation with Eq::{equal, not_equal}

///|
pub extend SlideAnimation with ToJson::{to_json}

///|
fn animation_check(
  tree : Tree,
  node : @xml.Node,
  name : String,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == presentation_uri &&
    node.name == name &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(child => child.uri == presentation_uri && children.contains(child.name)) else {
    @failure.reject(
      "protected-content", "Extended object animation is protected",
    )
  }
}

///|
fn animation_value(
  node : @xml.Node,
  name : String,
  value : String,
) -> Unit raise @failure.Failure {
  guard node.attribute(name) == Some(value) else {
    @failure.reject("protected-content", "Unsupported animation " + name)
  }
}

///|
fn animation_child(
  tree : Tree,
  node : @xml.Node,
  name : String,
) -> @xml.Node raise @failure.Failure {
  tree.required(node.id, name, uri=presentation_uri)
}

///|
fn validate_animations(
  slide : Slide,
  items : Array[SlideAnimation],
) -> Unit raise @failure.Failure {
  guard items.length() <= 128 else {
    @failure.reject("limit-exceeded", "Slide animations exceed 128")
  }
  for item in items {
    guard [
        "appear", "disappear", "fadeIn", "fadeOut", "scale", "rotate", "move", "flyIn",
        "flyOut",
      ].contains(item.kind) &&
      ["click", "with", "after"].contains(item.trigger) &&
      item.delay >= 0 &&
      item.delay <= 60000 &&
      item.repeat >= 1 &&
      item.repeat <= 100 &&
      (if ["appear", "disappear"].contains(item.kind) {
        item.duration == 1 && item.repeat == 1
      } else {
        item.duration >= 100 && item.duration <= 60000
      }) else {
      @failure.reject("invalid-operation", "Unknown object animation")
    }
    guard item.params.all(value => {
        !value.is_nan() && !value.is_inf() && value == value.round()
      }) &&
      (match item.kind {
        "scale" =>
          item.params.length() == 2 && item.params.all(v => v >= 1 && v <= 1000)
        "rotate" => item.params.length() == 1 && item.params[0].abs() <= 3600
        "move" =>
          item.params.length() == 2 && item.params.all(v => v.abs() <= 14400)
        "flyIn" | "flyOut" =>
          item.params.length() == 1 &&
          [1.0, 2, 3, 4, 6, 8, 9, 12].contains(item.params[0])
        _ => item.params.is_empty()
      }) else {
      @failure.reject("invalid-operation", "Invalid animation parameters")
    }
    guard slide.objects.iter().find_first(object => object.id == item.object)
      is Some(object) &&
      object.parent.is_empty() &&
      object.source.tree.part == slide.tree.part &&
      ["shape", "image"].contains(object.kind) &&
      object.geometry is Some(_) &&
      object.diagnostic.is_empty() else {
      @failure.reject(
        "protected-content", "Animation requires a local shape or picture",
      )
    }
  }
  let intervals : Map[String, Array[(Int, Int)]] = Map([])
  let mut base = 0
  let mut end = 0
  for index, item in items {
    if index == 0 || item.trigger == "click" {
      intervals.clear()
      base = 0
      end = 0
    } else if item.trigger == "after" {
      base = end
    }
    let start = base + item.delay
    let finish = start + item.duration * item.repeat
    let channels = if ["flyIn", "flyOut"].contains(item.kind) {
      ["move", "visibility"]
    } else if ["scale", "rotate", "move"].contains(item.kind) {
      [item.kind]
    } else {
      ["visibility"]
    }
    for property in channels {
      let channel = item.object + ":" + property
      let previous = intervals.get(channel).unwrap_or([])
      guard !previous.any(pair => start < pair.1 && finish > pair.0) else {
        @failure.reject(
          "protected-content", "Concurrent animations of one property require additional composition support",
        )
      }
      previous.push((start, finish))
      intervals[channel] = previous
    }
    end = end.max(finish)
  }
}

///|
fn Session::read_animations(
  self : Session,
  slide : Slide,
) -> Array[SlideAnimation] raise @failure.Failure {
  let tree = slide.tree
  guard tree.one(tree.root("sld").id, "timing", uri=presentation_uri)
    is Some(timing) else {
    return []
  }
  let source = tree.document.source()[timing.start:timing.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject("protected-content", "Opaque animation source is protected")
  }
  animation_check(tree, timing, "timing", [], ["tnLst"])
  let list = animation_child(tree, timing, "tnLst")
  animation_check(tree, list, "tnLst", [], ["par"])
  let par = animation_child(tree, list, "par")
  animation_check(tree, par, "par", [], ["cTn"])
  let root = animation_child(tree, par, "cTn")
  animation_check(tree, root, "cTn", ["id", "dur", "restart", "nodeType"], [
    "childTnLst",
  ])
  animation_value(root, "dur", "indefinite")
  animation_value(root, "restart", "never")
  animation_value(root, "nodeType", "tmRoot")
  let children = animation_child(tree, root, "childTnLst")
  animation_check(tree, children, "childTnLst", [], ["seq"])
  let seq = animation_child(tree, children, "seq")
  animation_check(tree, seq, "seq", ["concurrent", "nextAc"], [
    "cTn", "prevCondLst", "nextCondLst",
  ])
  guard flag(seq, "concurrent") else {
    @failure.reject(
      "protected-content", "Sequential animation containers are protected",
    )
  }
  animation_value(seq, "nextAc", "seek")
  for (name, event) in [("prevCondLst", "onPrev"), ("nextCondLst", "onNext")] {
    if tree.one(seq.id, name, uri=presentation_uri) is Some(conditions) {
      animation_check(tree, conditions, name, [], ["cond"])
      let condition = animation_child(tree, conditions, "cond")
      animation_check(tree, condition, "cond", ["evt", "delay"], ["tgtEl"])
      animation_value(condition, "evt", event)
      animation_value(condition, "delay", "0")
      let target = animation_child(tree, condition, "tgtEl")
      animation_check(tree, target, "tgtEl", [], ["sldTgt"])
      if tree.one(target.id, "sldTgt", uri=presentation_uri) is Some(node) {
        animation_check(tree, node, "sldTgt", [], [])
      }
    }
  }
  let main = animation_child(tree, seq, "cTn")
  animation_check(tree, main, "cTn", ["id", "dur", "nodeType"], ["childTnLst"])
  animation_value(main, "dur", "indefinite")
  animation_value(main, "nodeType", "mainSeq")
  let effects = animation_child(tree, main, "childTnLst")
  animation_check(tree, effects, "childTnLst", [], ["par"])
  let result : Array[SlideAnimation] = []
  for group in tree.children.get(effects.id).unwrap_or([]) {
    let first = animation_container(tree, group)
    let automatic = animation_automatic(tree, first, main)
    let first_children = animation_child(tree, first, "childTnLst")
    let mut offset = 0
    for group_index, block in tree.children.get(first_children.id).unwrap_or([]) {
      let second = animation_container(tree, block)
      guard number(animation_delay(tree, second), 0, 1000000000).to_int() ==
        offset else {
        @failure.reject(
          "protected-content", "Unsupported animation group delay",
        )
      }
      let children = animation_child(tree, second, "childTnLst")
      let mut span = 0
      for effect_index, node in tree.children.get(children.id).unwrap_or([]) {
        let item = read_animation_effect(tree, node, self.width, self.height)
        let expected = if effect_index > 0 {
          "with"
        } else if group_index > 0 {
          "after"
        } else if automatic {
          item.trigger
        } else {
          "click"
        }
        guard item.trigger == expected &&
          (
            !automatic ||
            (result.is_empty() && item.trigger != "click") ||
            group_index > 0 ||
            effect_index > 0
          ) else {
          @failure.reject(
            "protected-content", "Conflicting animation trigger tree",
          )
        }
        result.push(item)
        guard result.length() <= 128 else {
          @failure.reject("limit-exceeded", "Slide animations exceed 128")
        }
        span = span.max(item.delay + item.duration * item.repeat)
      }
      offset += span
    }
  }
  let identities : Map[String, Bool] = Map([])
  for node in tree.document.nodes() {
    if node.start >= timing.start &&
      node.end <= timing.end &&
      node.name == "cTn" {
      let id = number(node.attribute("id").unwrap_or(""), 1, 2147483647)
        .to_int()
        .to_string()
      guard !identities.contains(id) else {
        @failure.reject("malformed-pptx", "Duplicate animation time identity")
      }
      identities[id] = true
    }
  }
  validate_animations(slide, result)
  result
}
