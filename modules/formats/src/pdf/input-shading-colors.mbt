///|
fn shading_color_points(
  points : Array[(Double, Array[Double])],
  space : InputColorSpace,
) -> Array[(Double, String)] raise {
  if !(space is IccColor(_)) && points.length() <= 32 {
    return points.map(p => (p.0, space.color(p.1)))
  }
  let samples : Array[(Double, String)] = []
  let mut previous : Array[Double] = []
  let mut color = ""
  fn append(position : Double, values : Array[Double]) -> Unit raise {
    @pdfcore.sdk_check(1)
    if values != previous {
      @pdfcore.sdk_check(16)
      color = space.color(values)
      previous = values
    }
    let point = (position, color)
    let length = samples.length()
    if length >= 2 &&
      samples[length - 1].1 == color &&
      samples[length - 2].1 == color {
      samples[length - 1] = point
    } else {
      samples.push(point)
    }
    guard samples.length() <= 8192 else {
      @failure.reject(
        "limit-exceeded", "PDF shading color samples exceed budget",
      )
    }
  }
  for i, point in points {
    if i > 0 && space is IccColor(_) {
      let before = points[i - 1]
      let steps = point.1
        .mapi((c, value) => (value - before.1[c]).abs())
        .fold(init=0.0, (a, b) => a.max(b)) *
        256
      for step in 1..<steps.ceil().to_int() {
        let t = step.to_double() / steps.ceil()
        append(
          before.0 + (point.0 - before.0) * t,
          point.1.mapi((c, value) => before.1[c] + (value - before.1[c]) * t),
        )
      }
    }
    append(point.0, point.1)
  }
  let colors = samples.map(p => @string.parse_int(p.1, base=16))
  let result : Array[(Double, String)] = []
  fn reduce(first : Int32, last : Int32, depth : Int32) -> Unit raise {
    guard depth < 32 else {
      @failure.reject(
        "limit-exceeded", "PDF shading subdivision exceeds budget",
      )
    }
    @pdfcore.sdk_check(last - first + 1)
    let left = samples[first].0
    let span = samples[last].0 - left
    let mut split = first
    let mut error = 1.0
    for i in (first + 1)..<last {
      let t = if span == 0 { 0.0 } else { (samples[i].0 - left) / span }
      for shift in [16, 8, 0] {
        let a = ((colors[first] >> shift) & 255).to_double()
        let b = ((colors[last] >> shift) & 255).to_double()
        let delta = (((colors[i] >> shift) & 255).to_double() -
        (a + (b - a) * t)).abs()
        if delta > error {
          error = delta
          split = i
        }
      }
    }
    if split != first {
      reduce(first, split, depth + 1)
      reduce(split, last, depth + 1)
    } else {
      result.push(samples[first])
      guard result.length() < 32 else {
        @failure.reject("limit-exceeded", "PDF shading stops exceed budget")
      }
    }
  }
  reduce(0, samples.length() - 1, 0)
  result.push(samples.last().unwrap())
  result
}
