///|
pub(all) struct ShowMediaChange {
  object : String
  token : Int32
  action : String
  message : String
}

///|
priv struct ShowMediaPlayback {
  token : Int32
  state : String
  reason : String
}

///|
fn ShowState::media_state(
  self : ShowState,
  object : String,
) -> ShowMediaPlayback {
  self.media.get(object).unwrap_or({ token: 0, state: "stopped", reason: "", })
}

///|
fn show_media_visible(object : Object, show : ShowState) -> Bool {
  show.effect is None &&
  object.geometry is Some(_) &&
  show
  .animation_state()
  .get(object.id)
  .map(value => value.opacity > 0)
  .unwrap_or(true)
}

///|
fn Session::show_media_query(
  self : Session,
  show : ShowState,
) -> Array[Json] raise @failure.Failure {
  let result : Array[Json] = []
  let mut units = 0
  let visibility = show.animation_state()
  let (settings, settings_reason) = (
    read_media_nodes(self.slides[show.index].tree),
    "",
  ) catch {
    @failure.Failure(message~, ..) => (Map([]), message)
  }
  for object in self.slides[show.index].objects {
    guard object.media is Some(media) else { continue }
    let state = show.media_state(object.id)
    let reason = if !media.reason.is_empty() {
      media.reason
    } else if !object.diagnostic.is_empty() {
      object.diagnostic
    } else if settings_reason.is_empty() {
      state.reason
    } else {
      settings_reason
    }
    units += object.id.length() +
      object.name.length() +
      media.key.length() +
      media.content_type.length() +
      reason.length()
    guard units <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Slideshow media descriptions exceed budget",
      )
    }
    result.push({
      "object": object.id,
      "label": object.name,
      "kind": media.kind,
      "key": media.key,
      "contentType": media.content_type,
      "token": state.token,
      "state": state.state,
      "reason": reason,
      "visible": show.effect is None &&
      object.geometry is Some(_) &&
      visibility.get(object.id).map(value => value.opacity > 0).unwrap_or(true),
      "playback": settings
      .get(object.id)
      .map(value => value.1)
      .unwrap_or(MediaPlaybackSettings::initial())
      .json(),
    })
  }
  result
}

///|
fn Session::change_show_media(
  self : Session,
  show : ShowState,
  change : ShowMediaChange,
  sequence~ : Int32 = self.media_sequence,
  scripted~ : Bool = false,
) -> (ShowState, Int32) raise @failure.Failure {
  let object = self.slides[show.index].object(change.object)
  guard object.media is Some(media) else {
    @failure.reject("invalid-operation", "Target is not a media object")
  }
  let old = show.media_state(change.object)
  guard old.token == change.token else {
    @failure.reject("stale-media", "Media playback identity has changed")
  }
  let action = change.action
  guard ["play", "pause", "stop", "ended", "paused", "blocked", "error"].contains(
      action,
    ) &&
    (if action == "error" {
      !change.message.is_empty() &&
      change.message.length() <= 1024 &&
      @xml.valid_text(change.message)
    } else {
      change.message.is_empty()
    }) else {
    @failure.reject("invalid-operation", "Invalid media action or message")
  }
  let feedback = ["ended", "paused", "blocked", "error"].contains(action)
  if feedback {
    guard old.token > 0 && ["playing", "paused", "blocked"].contains(old.state) else {
      @failure.reject(
        "stale-media", "Media feedback requires an active playback instance",
      )
    }
  } else {
    ignore(read_media_nodes(self.slides[show.index].tree))
    guard media.reason.is_empty() &&
      object.diagnostic.is_empty() &&
      object.image is Some(_) else {
      @failure.reject(
        "protected-content", "Media source or poster is unavailable",
      )
    }
    if action == "play" && !scripted {
      guard show_media_visible(object, show) else {
        @failure.reject("invalid-operation", "Media is not currently visible")
      }
    }
  }
  let restart = action == "play" &&
    (scripted || !["playing", "paused"].contains(old.state))
  let token = if restart || action == "stop" {
    guard sequence < 2147483647 else {
      @failure.reject("limit-exceeded", "Media playback identity exhausted")
    }
    sequence + 1
  } else {
    old.token
  }
  let state = match action {
    "play" => "playing"
    "pause" => "paused"
    "stop" => "stopped"
    _ => action
  }
  guard action != "pause" || ["playing", "paused"].contains(old.state) else {
    @failure.reject("invalid-operation", "Start media before pausing")
  }
  let players = show.media.copy()
  players[object.id] = {
    token,
    state,
    reason: if action == "error" {
      change.message
    } else if action == "blocked" {
      "Playback was blocked; select Play to retry"
    } else {
      ""
    },
  }
  guard players
    .values()
    .filter(item => {
      ["playing", "paused", "ended", "blocked"].contains(item.state)
    })
    .count() <=
    16 else {
    @failure.reject(
      "limit-exceeded", "Slideshow retains at most 16 media players; stop a player first",
    )
  }
  (
    { ..show, media: players, },
    if restart || action == "stop" {
      token
    } else {
      sequence
    },
  )
}

///|
/// Applies displayed-frame user actions or token-bound decoder feedback without editing the document.
pub fn Session::media_show(
  self : Session,
  revision : Int32,
  layout : Int32?,
  time : Double,
  change : ShowMediaChange,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let feedback = ["ended", "paused", "blocked", "error"].contains(change.action)
  if feedback {
    guard layout is None else {
      @failure.reject(
        "invalid-operation", "Decoder feedback uses its playback token",
      )
    }
  } else {
    guard layout is Some(layout) else {
      @failure.reject(
        "stale-layout", "Media controls require the displayed frame",
      )
    }
    let drawing = self.current_show_frame(layout)
    if change.action == "play" {
      guard show_media_visible(
        self.slides[drawing.frame.index].object(change.object),
        drawing.frame,
      ) else {
        @failure.reject(
          "invalid-operation", "Media is not visible in the displayed frame",
        )
      }
    }
  }
  guard self.showing is Some(show) else {
    @failure.reject("show-required", "Start the slideshow first")
  }
  let (advanced, sequence) = if feedback {
    (Some(show.advance(time)), self.media_sequence)
  } else {
    self.show_media_cues(Some(show.advance(time)))
  }
  let (next, sequence) = self.change_show_media(
    advanced.unwrap(),
    change,
    sequence~,
  )
  let result = self.show_state(Some(next))
  self.showing = Some(next)
  self.media_sequence = sequence
  result
}
