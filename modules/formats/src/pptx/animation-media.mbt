///|
fn read_media_animation(
  tree : Tree,
  effect : @xml.Node,
  trigger : String,
) -> SlideAnimation raise @failure.Failure {
  let children = animation_child(tree, effect, "childTnLst")
  guard tree.children.get(children.id).unwrap_or([]) is [command] else {
    @failure.reject("protected-content", "Extended media animation behavior")
  }
  animation_check(tree, command, "cmd", ["type", "cmd"], ["cBhvr"])
  animation_value(command, "type", "call")
  let kind = match command.attribute("cmd") {
    Some("playFrom(0.0)") => "mediaPlay"
    Some("pause") => "mediaPause"
    Some("stop") => "mediaStop"
    _ =>
      @failure.reject(
        "protected-content", "Media bookmarks, trim and extended commands are protected",
      )
  }
  let (object, duration) = animation_behavior(
    tree,
    animation_child(tree, command, "cBhvr"),
    None,
  )
  guard duration == 1 &&
    effect.attribute("dur").unwrap_or("1") == "1" &&
    effect.attribute("repeatCount").unwrap_or("1000") == "1000" &&
    [Some("1"), Some("2"), Some("3")].contains(effect.attribute("presetID")) else {
    @failure.reject("protected-content", "Extended media command timing")
  }
  {
    object,
    kind,
    trigger,
    delay: number(animation_delay(tree, effect), 0, 60000).to_int(),
    duration: 1,
    repeat: 1,
    params: [],
  }
}

///|
fn media_animation_markup(
  item : SlideAnimation,
  id : Int32,
  target : String,
) -> String {
  let command = match item.kind {
    "mediaPlay" => "playFrom(0.0)"
    "mediaPause" => "pause"
    _ => "stop"
  }
  "<od:cmd type=\"call\" cmd=\"\{command}\"><od:cBhvr><od:cTn id=\"\{id}\" dur=\"1\" fill=\"hold\"/><od:tgtEl><od:spTgt spid=\"\{target}\"/></od:tgtEl></od:cBhvr></od:cmd>"
}

///|
fn Session::show_media_cues(
  self : Session,
  show : ShowState?,
  initial~ : Int32 = self.media_sequence,
) -> (ShowState?, Int32) raise @failure.Failure {
  guard show is Some(show) else { return (None, initial) }
  let order = Array::makei(show.starts.length(), i => i)
  order.sort_by((a, b) => {
    if show.starts[a] < show.starts[b] {
      -1
    } else if show.starts[a] > show.starts[b] {
      1
    } else {
      a - b
    }
  })
  let applied = show.media_cues.copy()
  let mut next = show
  let mut sequence = initial
  for index in order {
    let item = show.animations[index]
    if !item.kind.has_prefix("media") ||
      applied.contains(index) ||
      (index >= show.finished && show.starts[index] > show.elapsed) {
      continue
    }
    let old = next.media_state(item.object)
    let action = match item.kind {
      "mediaPlay" => "play"
      "mediaPause" => "pause"
      _ => "stop"
    }
    if action != "pause" || ["playing", "paused"].contains(old.state) {
      let (changed, identity) = self.change_show_media(
        next,
        { object: item.object, token: old.token, action, message: "", },
        sequence~,
        scripted=true,
      ) catch {
        @failure.Failure(code="limit-exceeded", message~, ..) if sequence <
          2147483647 => {
          let players = next.media.copy()
          players[item.object] = {
            token: sequence + 1,
            state: "error",
            reason: message,
          }
          ({ ..next, media: players, }, sequence + 1)
        }
        error => raise error
      }
      next = changed
      sequence = identity
    }
    applied[index] = true
  }
  (Some({ ..next, media_cues: applied, }), sequence)
}

///|
fn ShowState::pending_media_cues(self : ShowState) -> Bool {
  for i in 0..<self.starts.length() {
    if self.animations[i].kind.has_prefix("media") &&
      !self.media_cues.contains(i) {
      return true
    }
  }
  false
}
