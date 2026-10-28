///|
pub(all) struct MediaPlaybackSettings {
  cycling : Bool
  volume : Int32
  mute : Bool
} derive(Eq)

///|
pub extend MediaPlaybackSettings with Eq::{equal, not_equal}

///|
fn MediaPlaybackSettings::json(self : MediaPlaybackSettings) -> Json {
  { "loop": self.cycling, "volume": self.volume, "mute": self.mute }
}

///|
fn MediaPlaybackSettings::initial() -> MediaPlaybackSettings {
  { cycling: false, volume: 100000, mute: false, }
}

///|
fn MediaPlaybackSettings::validate(
  self : MediaPlaybackSettings,
) -> Unit raise @failure.Failure {
  guard self.volume >= 0 && self.volume <= 100000 else {
    @failure.reject(
      "invalid-operation", "Media volume must be within 0–100000",
    )
  }
}

///|
fn animation_root(tree : Tree) -> @xml.Node? raise @failure.Failure {
  guard tree.one(tree.root("sld").id, "timing", uri=presentation_uri)
    is Some(timing) else {
    return None
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
  animation_check(tree, children, "childTnLst", [], ["seq", "video", "audio"])
  let ids : Map[String, Bool] = Map([])
  for node in tree.document.nodes() {
    if node.start >= timing.start &&
      node.end <= timing.end &&
      node.name == "cTn" {
      let id = number(node.attribute("id").unwrap_or(""), 1, 2147483647)
        .to_int()
        .to_string()
      guard !ids.contains(id) else {
        @failure.reject("malformed-pptx", "Duplicate animation time identity")
      }
      ids[id] = true
    }
  }
  Some(children)
}

///|
fn read_media_nodes(
  tree : Tree,
) -> Map[String, (String, MediaPlaybackSettings)] raise @failure.Failure {
  let result : Map[String, (String, MediaPlaybackSettings)] = Map([])
  let nodes = tree.document
    .nodes()
    .filter(node => {
      node.uri == presentation_uri && ["video", "audio"].contains(node.name)
    })
  guard !nodes.is_empty() else { return result }
  guard nodes.length() <= 4096 && animation_root(tree) is Some(children) else {
    @failure.reject(
      "protected-content", "Media timing requires a supported root",
    )
  }
  for node in nodes {
    guard node.parent == children.id else {
      @failure.reject(
        "protected-content", "Nested media timelines are protected",
      )
    }
    animation_check(
      tree,
      node,
      node.name,
      [if node.name == "video" { "fullScrn" } else { "isNarration" }],
      ["cMediaNode"],
    )
    guard !flag(
      node,
      if node.name == "video" {
        "fullScrn"
      } else {
        "isNarration"
      },
    ) else {
      @failure.reject(
        "protected-content", "Fullscreen and narration media are protected",
      )
    }
    let media = animation_child(tree, node, "cMediaNode")
    animation_check(
      tree,
      media,
      "cMediaNode",
      ["vol", "mute", "numSld", "showWhenStopped"],
      ["cTn", "tgtEl"],
    )
    guard media.attribute("numSld").unwrap_or("1") == "1" &&
      flag(media, "showWhenStopped", default=true) else {
      @failure.reject(
        "protected-content", "Cross-slide or hidden-poster media is protected",
      )
    }
    let clock = animation_child(tree, media, "cTn")
    animation_check(
      tree,
      clock,
      "cTn",
      ["id", "dur", "fill", "display", "repeatCount"],
      ["stCondLst", "endCondLst"],
    )
    animation_value(clock, "fill", "hold")
    guard !flag(clock, "display") &&
      clock.attribute("dur").unwrap_or("media") == "media" else {
      @failure.reject(
        "protected-content", "Extended media duration is protected",
      )
    }
    animation_value(
      animation_child(tree, animation_child(tree, clock, "stCondLst"), "cond"),
      "delay",
      "indefinite",
    )
    let start = animation_child(tree, clock, "stCondLst")
    animation_check(tree, start, "stCondLst", [], ["cond"])
    animation_check(
      tree,
      animation_child(tree, start, "cond"),
      "cond",
      ["delay"],
      [],
    )
    if tree.one(clock.id, "endCondLst", uri=presentation_uri) is Some(end) {
      animation_check(tree, end, "endCondLst", [], ["cond"])
      let condition = animation_child(tree, end, "cond")
      animation_check(tree, condition, "cond", ["evt", "delay"], ["tgtEl"])
      animation_value(condition, "evt", "onNext")
      animation_value(condition, "delay", "0")
      let target = animation_child(tree, condition, "tgtEl")
      animation_check(tree, target, "tgtEl", [], ["sldTgt"])
      animation_check(
        tree,
        animation_child(tree, target, "sldTgt"),
        "sldTgt",
        [],
        [],
      )
    }
    let target = animation_child(tree, media, "tgtEl")
    animation_check(tree, target, "tgtEl", [], ["spTgt"])
    let shape = animation_child(tree, target, "spTgt")
    animation_check(tree, shape, "spTgt", ["spid"], [])
    let id = tree.part +
      "#" +
      source_identity(shape.attribute("spid").unwrap_or(""))
    guard !result.contains(id) else {
      @failure.reject(
        "protected-content", "Duplicate media playback definitions",
      )
    }
    let volume = number(media.attribute("vol").unwrap_or("100000"), 0, 100000)
    guard volume == volume.round() else {
      @failure.reject("protected-content", "Fractional media volume units")
    }
    let cycling = match clock.attribute("repeatCount") {
      None | Some("1000") => false
      Some("indefinite") => true
      _ =>
        @failure.reject(
          "protected-content", "Finite media repeat counts are protected",
        )
    }
    result[id] = (
      node.name,
      { cycling, volume: volume.to_int(), mute: flag(media, "mute"), },
    )
  }
  result
}

///|
fn media_nodes_markup(
  nodes : Map[String, (String, MediaPlaybackSettings)],
  part : String,
  first : Int32,
) -> String {
  let keys = nodes.keys().to_array()
  keys.sort()
  keys
  .mapi((i, key) => {
    let (kind, settings) = nodes[key]
    let target = key[part.length() + 1:]
    let repeat = if settings.cycling {
      " repeatCount=\"indefinite\""
    } else {
      ""
    }
    "<od:\{kind}><od:cMediaNode vol=\"\{settings.volume}\" mute=\"\{settings.mute}\" numSld=\"1\" showWhenStopped=\"1\"><od:cTn id=\"\{first+i}\" fill=\"hold\" display=\"0\"\{repeat}><od:stCondLst><od:cond delay=\"indefinite\"/></od:stCondLst><od:endCondLst><od:cond evt=\"onNext\" delay=\"0\"><od:tgtEl><od:sldTgt/></od:tgtEl></od:cond></od:endCondLst></od:cTn><od:tgtEl><od:spTgt spid=\"\{target}\"/></od:tgtEl></od:cMediaNode></od:\{kind}>"
  })
  .join("")
}

///|
fn Session::media_playback_query(self : Session) -> Json {
  try {
    guard self.selection.objects is [id] && self.selection.mode == "object" else {
      return { "value": Json::null(), "reason": "Select one media object" }
    }
    let object = self.current().object(id)
    guard object.media is Some(media) else {
      return { "value": Json::null(), "reason": "" }
    }
    let reason = self.object_edit_reason(object, "mediaPlayback")
    guard reason.is_empty() && media.reason.is_empty() else {
      @failure.reject("protected-content", reason + media.reason)
    }
    ignore(self.read_animations(self.current()))
    let nodes = read_media_nodes(self.current().tree)
    let settings = nodes
      .get(id)
      .map(value => value.1)
      .unwrap_or(MediaPlaybackSettings::initial())
    { "value": settings.json(), "reason": "" }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": message }
  }
}

///|
fn Session::set_media_playback(
  self : Session,
  value : MediaPlaybackSettings,
) -> Json raise @failure.Failure {
  value.validate()
  guard self.source_view is None &&
    self.selection.mode == "object" &&
    self.selection.objects is [id] else {
    @failure.reject("invalid-operation", "Select one local media object")
  }
  let slide = self.current()
  let object = slide.object(id)
  guard object.media is Some(media) &&
    media.reason.is_empty() &&
    object.parent.is_empty() &&
    object.image is Some(_) else {
    @failure.reject(
      "protected-content", "Playback settings require local embedded media",
    )
  }
  let reason = self.object_edit_reason(object, "mediaPlayback")
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let items = self.read_animations(slide)
  let nodes = read_media_nodes(slide.tree)
  if nodes
    .get(id)
    .map(item => item.1)
    .unwrap_or(MediaPlaybackSettings::initial()) ==
    value {
    return self.query()
  }
  nodes[id] = (media.kind, value)
  let change = self.animation_change(slide, items, nodes)
  let (candidate, edit) = self.prepare(slide, [change])
  self.commit(candidate, edit, self.selection)
  self.query()
}

///|
fn media_setting_reference(
  tree : Tree,
  node : @xml.Node,
) -> Bool raise @failure.Failure {
  guard node.uri == presentation_uri &&
    node.name == "spTgt" &&
    tree.nodes.get(node.parent) is Some(target) &&
    tree.nodes.get(target.parent) is Some(media) &&
    media.name == "cMediaNode" else {
    return false
  }
  read_media_nodes(tree).contains(
    tree.part + "#" + source_identity(node.attribute("spid").unwrap_or("")),
  )
}

///|
fn Session::copy_media_settings(
  self : Session,
  slide : Slide,
  identities : Map[String, String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard has_media_settings(slide.tree, identities.keys().to_array()) else {
    return []
  }
  let media = read_media_nodes(slide.tree)
  let copies = media.keys().filter(id => identities.contains(id)).to_array()
  guard !copies.is_empty() else { return [] }
  for id in copies {
    media[identities[id]] = media[id]
  }
  [self.animation_change(slide, self.read_animations(slide), media)]
}

///|
fn has_media_settings(
  tree : Tree,
  ids : Array[String],
) -> Bool raise @failure.Failure {
  tree.document
  .nodes()
  .any(node => {
    node.uri == presentation_uri &&
    node.name == "spTgt" &&
    ids.contains(
      tree.part + "#" + source_identity(node.attribute("spid").unwrap_or("")),
    ) &&
    tree.nodes.get(node.parent) is Some(target) &&
    tree.nodes.get(target.parent) is Some(media) &&
    media.name == "cMediaNode"
  })
}
