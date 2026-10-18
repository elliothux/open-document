///|
pub(all) struct SlideTransition {
  kind : String
  duration : Int
  direction : String
} derive(Eq, ToJson)

///|
pub extend SlideTransition with Eq::{equal, not_equal}

///|
pub extend SlideTransition with ToJson::{to_json}

///|
fn SlideTransition::validate(
  self : SlideTransition,
) -> Unit raise @failure.Failure {
  guard ["none", "fade", "push"].contains(self.kind) &&
    ["left", "right", "up", "down"].contains(self.direction) &&
    (if self.kind == "none" {
      self.duration == 0
    } else {
      self.duration >= 100 && self.duration <= 60000
    }) &&
    (self.kind == "push" || self.direction == "left") else {
    @failure.reject("invalid-operation", "Invalid slide transition")
  }
}

///|
fn read_slide_transition(
  tree : Tree,
) -> SlideTransition? raise @failure.Failure {
  let p14 = "http://schemas.microsoft.com/office/powerpoint/2010/main"
  guard tree.one(tree.root("sld").id, "transition", uri=presentation_uri)
    is Some(node) else {
    return None
  }
  let source = tree.document.source()[node.start:node.end]
  guard !source.contains("<!--") &&
    !source.contains("<?") &&
    node.text.trim().is_empty() &&
    node.attributes.all(a => {
      (a.uri.is_empty() && ["spd", "advClick"].contains(a.name)) ||
      (a.uri == p14 && a.name == "dur")
    }) &&
    flag(node, "advClick", default=true) else {
    @failure.reject(
      "protected-content", "Extended or automatic slide transitions are protected",
    )
  }
  let children = tree.children.get(node.id).unwrap_or([])
  guard children is [effect] &&
    effect.uri == presentation_uri &&
    ["cut", "fade", "push"].contains(effect.name) &&
    effect.text.trim().is_empty() &&
    tree.children.get(effect.id).unwrap_or([]).is_empty() &&
    effect.attributes.all(a => {
      a.uri.is_empty() &&
      (if effect.name == "push" {
        a.name == "dir"
      } else {
        a.name == "thruBlk"
      })
    }) &&
    (effect.name == "push" || !flag(effect, "thruBlk")) else {
    @failure.reject("protected-content", "Unsupported slide transition effect")
  }
  let speed = node.attribute("spd").unwrap_or("fast")
  guard ["fast", "med", "slow"].contains(speed) else {
    @failure.reject("malformed-pptx", "Invalid transition speed")
  }
  let direction = match effect.attribute("dir").unwrap_or("l") {
    "l" => "left"
    "r" => "right"
    "u" => "up"
    "d" => "down"
    _ =>
      @failure.reject("protected-content", "Unsupported transition direction")
  }
  let value : SlideTransition = {
    kind: if effect.name == "cut" {
      "none"
    } else {
      effect.name
    },
    duration: if effect.name == "cut" {
      0
    } else {
      let duration = number(
        node
        .attribute("dur", uri=p14)
        .unwrap_or(
          if speed == "med" {
            "750"
          } else if speed == "slow" {
            "1000"
          } else {
            "500"
          },
        ),
        100,
        60000,
      )
      guard duration == duration.floor() else {
        @failure.reject(
          "malformed-pptx", "Transition duration must be whole milliseconds",
        )
      }
      duration.to_int()
    },
    direction: if effect.name == "push" {
      direction
    } else {
      "left"
    },
  }
  value.validate()
  Some(value)
}

///|
fn Session::transition_query(self : Session, slide : Slide) -> Json {
  try {
    let value = read_slide_transition(slide.tree)
    {
      "value": value.map(v => v.to_json()).unwrap_or(Json::null()),
      "reason": self.slide_visibility_reason(),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": message }
  }
}

///|
fn Session::set_transition(
  self : Session,
  index : Int,
  value : SlideTransition?,
) -> Json raise @failure.Failure {
  if value is Some(v) {
    v.validate()
  }
  let original = self.slides[index]
  let tree = original.tree
  let previous = read_slide_transition(tree)
  if previous == value {
    return self.query()
  }
  let markup = value
    .map(v => {
      let effect = if v.kind == "push" {
        "<od:push dir=\"\{v.direction[:1]}\"/>"
      } else if v.kind == "fade" {
        "<od:fade/>"
      } else {
        "<od:cut/>"
      }
      "<od:transition xmlns:od=\"\{presentation_uri}\" xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\" p14:dur=\"\{v.duration}\" advClick=\"1\">\{effect}</od:transition>"
    })
    .unwrap_or("")
  let root = tree.root("sld")
  let change : @xml.SourceChange = if tree.one(
      root.id,
      "transition",
      uri=presentation_uri,
    )
    is Some(node) {
    {
      node: root.id,
      offset: node.start - root.start,
      length: node.end - node.start,
      xml: markup,
    }
  } else {
    let following = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        node.uri == presentation_uri && ["timing", "extLst"].contains(node.name)
      })
    if following is Some(node) {
      {
        node: root.id,
        offset: node.start - root.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(root, markup)
    }
  }
  let (candidate, edit) = self.prepare(original, [change])
  self.commit(candidate, edit, self.selection)
  self.query()
}
