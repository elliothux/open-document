///|
fn ConditionalIcon::paint(
  self : ConditionalIcon,
  page : PagePaint,
  cell : @layout.Border,
  rtl : Bool,
) -> Unit {
  let size = 12.0.min((cell.height - 3).max(0)).min((cell.width - 3).max(0))
  if size <= 0 {
    return
  }
  let x = cell.x + 1.5 + (if rtl { cell.width - size - 3 } else { 0 })
  let y = cell.y + (cell.height - size) / 2
  let color = ["c00000", "ffc000", "00b050"][self.index]
  let style : @layout.PathStyle = {
    fillAlpha: 1,
    strokeAlpha: 1,
    dash: [],
    cap: 0,
    join: 0,
    miter: 8,
  }
  let path : Array[@layout.PathSegment] = if self.kind == "3TrafficLights1" {
    [
      Move(11, 6),
      Cubic(11, 8.7614, 8.7614, 11, 6, 11),
      Cubic(3.2386, 11, 1, 8.7614, 1, 6),
      Cubic(1, 3.2386, 3.2386, 1, 6, 1),
      Cubic(8.7614, 1, 11, 3.2386, 11, 6),
      Close,
    ]
  } else {
    let points : Array[(Double, Double)] = if self.kind == "3Flags" {
      [(2, 1), (11, 1), (9, 4), (11, 7), (2, 7)]
    } else {
      [(6, 0), (12, 6), (8.5, 6), (8.5, 12), (3.5, 12), (3.5, 6), (0, 6)]
    }
    let points = if self.kind == "3Arrows" {
      points.map(pair => {
        let (x, y) = pair
        if self.index == 0 {
          (x, 12.0 - y)
        } else if self.index == 1 {
          (12.0 - y, x)
        } else {
          (x, y)
        }
      })
    } else {
      points
    }
    let segments : Array[@layout.PathSegment] = []
    for i, (x, y) in points {
      segments.push(if i == 0 { Move(x, y) } else { Line(x, y) })
    }
    segments.push(Close)
    segments
  }
  page.bars.append([
    Clip(cell),
    Transform({ a: size / 12, b: 0, c: 0, d: size / 12, e: x, f: y, }),
    Path(path, color, "404040", 0.45, style),
  ])
  if self.kind == "3Flags" {
    page.bars.push(Path([Move(2, 1), Line(2, 12)], "", "404040", 0.75, style))
  }
  page.bars.append([Restore, Restore])
}
