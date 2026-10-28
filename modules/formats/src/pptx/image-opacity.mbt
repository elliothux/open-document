///|
fn image_opacity(blip : Ref) -> Double raise @failure.Failure {
  let effects = blip.tree.children.get(blip.node.id).unwrap_or([])
  if effects.is_empty() {
    return 1
  }
  guard effects is [effect] &&
    effect.uri == drawing_uri &&
    effect.name == "alphaModFix" &&
    effect.attributes.all(a => a.uri.is_empty() && a.name == "amt") &&
    effect.text.trim().is_empty() &&
    blip.tree.children.get(effect.id).unwrap_or([]).is_empty() else {
    @failure.reject("unsupported-style", "Unsupported picture effect")
  }
  number(effect.attribute("amt").unwrap_or("100000"), 0, 100000) / 100000
}

///|
fn image_opacity_amount(value : Double) -> Int32 raise @failure.Failure {
  guard !value.is_nan() && !value.is_inf() && value >= 0 && value <= 1 else {
    @failure.reject("invalid-operation", "Invalid picture opacity")
  }
  (value * 100000).round().to_int()
}

///|
fn image_opacity_change(
  blip : Ref,
  amount : Int32,
) -> @xml.SourceChange raise @failure.Failure {
  let markup = if amount == 100000 {
    ""
  } else {
    "<a:alphaModFix xmlns:a=\"\{drawing_uri}\" amt=\"\{amount}\"/>"
  }
  paint_child_change(
    blip,
    blip.child("alphaModFix").map(item => item.node),
    markup,
    [],
  )
}

///|
fn Session::set_image_opacity(
  self : Session,
  value : Double,
) -> Json raise @failure.Failure {
  let amount = image_opacity_amount(value)
  let object = self.selected_image(false)
  let reason = self.opacity_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if (object.opacity * 100000).round().to_int() == amount {
    return self.query()
  }
  let blip = object.source
    .child("blipFill", uri=presentation_uri)
    .unwrap()
    .child("blip")
    .unwrap()
  let (slide, edit) = self.prepare(self.current(), [
    image_opacity_change(blip, amount),
  ])
  self.commit(slide, edit, self.selection)
  self.query()
}

///|
fn Session::opacity_reason(self : Session, object : Object) -> String {
  let reason = self.image_reason(object, false)
  if !reason.is_empty() {
    return reason
  }
  try {
    let blip = object.source
      .child("blipFill", uri=presentation_uri)
      .unwrap()
      .child("blip")
      .unwrap()
    if blip.child("alphaModFix") is Some(effect) &&
      (source_xml(effect).contains("<!--") || source_xml(effect).contains("<?")) {
      return "Unknown opacity markup is protected"
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}
