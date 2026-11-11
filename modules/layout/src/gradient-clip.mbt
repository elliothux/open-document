///|
fn gradient_clip(
  commands : Array[DrawCommand],
  start : Int32,
  device : Bool,
) -> GradientClip? {
  if !device {
    let first = commands.get(start)
    if first is Some(GradientRect(_, _) | RadialGradientRect(_, _)) ||
      (
        first is Some(Transform(_)) &&
        commands.get(start + 1) is Some(GradientRect(_, _))
      ) {
      return Some({ axial: None, })
    }
    return None
  }
  let transforms : Array[Matrix] = []
  let mut next = start
  while next < commands.length() {
    match commands[next] {
      Style(_) => ()
      Transform(value) => transforms.push(value)
      _ => break
    }
    next += 1
  }
  let gradient = commands.get(next)
  if !(gradient is Some(GradientRect(_, _) | RadialGradientRect(_, _))) {
    return None
  }
  let axial = match gradient {
    Some(GradientRect(rect, stops)) if rect.width > 0 && stops.length() >= 2 => {
      let start = stops[0].position
      let end = stops[stops.length() - 1].position
      Some({
        transforms,
        startX: rect.x + rect.width * start,
        endX: rect.x + rect.width * end,
        y: rect.y,
        startBounded: start == 0,
        endBounded: end == 1,
      })
    }
    _ => None
  }
  Some({ axial, })
}

///|
/// Attach gradient domains after the paint order is known, keeping command indices.
pub fn annotate_gradient_clips(
  commands : Array[DrawCommand],
  device~ : Bool = false,
) -> Unit {
  for index, command in commands {
    match command {
      ClipRect(rect) if device =>
        if gradient_clip(commands, index + 1, device) is Some(shading) {
          commands[index] = GradientClipRect(rect, shading)
        }
      ClipPath(path, even_odd) =>
        if gradient_clip(commands, index + 1, device) is Some(shading) {
          commands[index] = GradientClipPath(path, even_odd, shading)
        }
      Layer(_, children) | Tile(_, _, _, _, _, _, _, children) =>
        annotate_gradient_clips(children, device~)
      Mask(mask, children) => {
        annotate_gradient_clips(mask, device~)
        annotate_gradient_clips(children, device~)
      }
      _ => ()
    }
  }
}
