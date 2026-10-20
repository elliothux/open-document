///|
fn animation_set(
  id : Int,
  target : String,
  visible : Bool,
  delay~ : Int = 0,
) -> String {
  let value = if visible { "visible" } else { "hidden" }
  "<od:set><od:cBhvr><od:cTn id=\"\{id}\" dur=\"1\" fill=\"hold\"><od:stCondLst><od:cond delay=\"\{delay}\"/></od:stCondLst></od:cTn><od:tgtEl><od:spTgt spid=\"\{target}\"/></od:tgtEl><od:attrNameLst><od:attrName>style.visibility</od:attrName></od:attrNameLst></od:cBhvr><od:to><od:strVal val=\"\{value}\"/></od:to></od:set>"
}

///|
fn animation_parallel(
  id : Int,
  delay : Int?,
  content : String,
  automatic~ : Bool = false,
) -> String {
  let delay = delay.map(value => value.to_string()).unwrap_or("indefinite")
  let begin = if automatic {
    "<od:cond evt=\"onBegin\" delay=\"0\"><od:tn val=\"2\"/></od:cond>"
  } else {
    ""
  }
  "<od:par><od:cTn id=\"\{id}\" fill=\"hold\"><od:stCondLst><od:cond delay=\"\{delay}\"/>\{begin}</od:stCondLst><od:childTnLst>\{content}</od:childTnLst></od:cTn></od:par>"
}

///|
fn animation_markup(
  items : Array[SlideAnimation],
  part : String,
  width : Double,
  height : Double,
  media~ : Map[String, (String, MediaPlaybackSettings)] = Map([]),
) -> String {
  guard !items.is_empty() || !media.is_empty() else { return "" }
  let groups : Array[Array[Array[SlideAnimation]]] = []
  for item in items {
    if groups.is_empty() || item.trigger == "click" {
      groups.push([[]])
    } else if item.trigger == "after" {
      groups.last().unwrap().push([])
    }
    groups.last().unwrap().last().unwrap().push(item)
  }
  let sequence = StringBuilder()
  let mut identity = 3
  for group in groups {
    let group_id = identity
    identity += 1
    let content = StringBuilder()
    let mut offset = 0
    for block in group {
      let block_id = identity
      identity += 1
      let effects = StringBuilder()
      let mut span = 0
      for item in block {
        let id = identity
        identity += 1
        let target = item.object[part.length() + 1:].to_owned()
        let entrance = ["appear", "fadeIn", "flyIn"].contains(item.kind)
        let flight = ["flyIn", "flyOut"].contains(item.kind)
        let fade = ["fadeIn", "fadeOut"].contains(item.kind)
        let geometric = ["scale", "rotate", "move"].contains(item.kind)
        let media = item.kind.has_prefix("media")
        let behavior = if media {
          let markup = media_animation_markup(item, identity, target)
          identity += 1
          markup
        } else if flight {
          let markup = flight_animation_markup(item, identity, target)
          identity += 3
          markup
        } else if geometric {
          let markup = geometric_animation_markup(
            item, identity, target, width, height,
          )
          identity += 1
          markup
        } else if fade {
          let visible = if entrance {
            let markup = animation_set(identity, target, true)
            identity += 1
            markup
          } else {
            ""
          }
          let from = if entrance { "1" } else { "0" }
          let to = if entrance { "0" } else { "1" }
          let markup = "\{visible}<od:anim calcmode=\"lin\" valueType=\"num\" from=\"\{from}\" to=\"\{to}\"><od:cBhvr override=\"childStyle\"><od:cTn id=\"\{identity}\" dur=\"\{item.duration}\" fill=\"hold\"/><od:tgtEl><od:spTgt spid=\"\{target}\"/></od:tgtEl><od:attrNameLst><od:attrName>style.opacity</od:attrName></od:attrNameLst></od:cBhvr></od:anim>"
          identity += 1
          markup
        } else {
          let markup = animation_set(identity, target, entrance)
          identity += 1
          markup
        }
        let preset = match item.kind {
          "mediaPlay" => 2
          "mediaPause" => 1
          "mediaStop" => 3
          "scale" => 6
          "rotate" => 8
          "move" => 0
          "flyIn" | "flyOut" => 2
          _ => if fade { 10 } else { 1 }
        }
        let class = if media {
          "mediacall"
        } else if item.kind == "move" {
          "path"
        } else if geometric {
          "emph"
        } else if entrance {
          "entr"
        } else {
          "exit"
        }
        let trigger = match item.trigger {
          "click" => "clickEffect"
          "with" => "withEffect"
          _ => "afterEffect"
        }
        let subtype = if flight { item.params[0].to_int() } else { 0 }
        effects.write_string(
          "<od:par><od:cTn id=\"\{id}\" presetID=\"\{preset}\" presetClass=\"\{class}\" presetSubtype=\"\{subtype}\" fill=\"hold\" nodeType=\"\{trigger}\" dur=\"\{item.duration}\" repeatCount=\"\{item.repeat*1000}\"><od:stCondLst><od:cond delay=\"\{item.delay}\"/></od:stCondLst><od:childTnLst>\{behavior}</od:childTnLst></od:cTn></od:par>",
        )
        span = span.max(item.delay + item.duration * item.repeat)
      }
      content.write_string(
        animation_parallel(block_id, Some(offset), effects.to_string()),
      )
      offset += span
    }
    sequence.write_string(
      animation_parallel(
        group_id,
        None,
        content.to_string(),
        automatic=group[0][0].trigger != "click",
      ),
    )
  }
  let conditions = "<od:prevCondLst><od:cond evt=\"onPrev\" delay=\"0\"><od:tgtEl><od:sldTgt/></od:tgtEl></od:cond></od:prevCondLst><od:nextCondLst><od:cond evt=\"onNext\" delay=\"0\"><od:tgtEl><od:sldTgt/></od:tgtEl></od:cond></od:nextCondLst>"
  "<od:timing xmlns:od=\"\{presentation_uri}\"><od:tnLst><od:par><od:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><od:childTnLst><od:seq concurrent=\"1\" nextAc=\"seek\"><od:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><od:childTnLst>\{sequence.to_string()}</od:childTnLst></od:cTn>\{conditions}</od:seq>\{media_nodes_markup(media, part, identity)}</od:childTnLst></od:cTn></od:par></od:tnLst></od:timing>"
}
