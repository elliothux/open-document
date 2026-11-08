///|
// Decoration boundaries use shaping carets so they cannot split ligatures.
fn line_decorations(
  carets : Array[Caret],
  spans : Array[MeasuredSpan],
  start : Int32,
  width : Double,
  end~ : Int32,
) -> Array[TextDecoration] {
  let result : Array[TextDecoration] = []
  let mut span = 0
  for i = 0; i + 1 < carets.length(); i = i + 1 {
    let a = carets[i]
    let b = carets[i + 1]
    while span < spans.length() && spans[span].end <= start + a.offset {
      span += 1
    }
    if span == spans.length() {
      break
    }
    let style = spans[span].span.style
    let underline = style.underline && start + a.offset < end
    let strike = style.strike && start + a.offset < end
    if !underline && !strike && style.highlight.is_empty() {
      continue
    }
    let x = a.after.min(b.before).max(0).min(width)
    let end = a.after.max(b.before).max(0).min(width)
    if end <= x {
      continue
    }
    if result.last() is Some(previous) &&
      previous.underline == underline &&
      previous.strike == strike &&
      previous.highlight == style.highlight &&
      (
        (previous.x + previous.width - x).abs() < 0.000001 ||
        (end - previous.x).abs() < 0.000001
      ) {
      result[result.length() - 1] = {
        ..previous,
        x: previous.x.min(x),
        width: (previous.x + previous.width).max(end) - previous.x.min(x),
      }
    } else {
      result.push({
        x,
        width: end - x,
        underline,
        strike,
        highlight: style.highlight,
      })
    }
  }
  result
}
