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
  let count = conditional_icon_count(self.kind)
  let direction = match count {
    4 => [0, 1, 3, 4][self.index]
    5 => self.index
    _ => [0, 2, 4][self.index]
  }
  let color = if self.kind.has_suffix("Gray") {
    "505050"
  } else if direction == 0 {
    "c00000"
  } else if direction == 4 {
    "00b050"
  } else {
    "ffc000"
  }
  let style : @layout.PathStyle = {
    fillAlpha: 1,
    strokeAlpha: 1,
    dash: [],
    cap: 0,
    join: 0,
    miter: 8,
  }
  if self.symbol_paths(style) is Some(paths) {
    page.bars.append(
      [
        Clip(cell),
        Transform({ a: size / 12, b: 0, c: 0, d: size / 12, e: x, f: y, }),
        ..paths,
        Restore,
        Restore,
      ],
    )
    return
  }
  let path : Array[@layout.PathSegment] = if self.kind == "3TrafficLights1" {
    conditional_icon_circle(5)
  } else {
    let points : Array[(Double, Double)] = if self.kind == "3Flags" {
      [(2, 1), (11, 1), (9, 4), (11, 7), (2, 7)]
    } else {
      [(6, 0), (12, 6), (8.5, 6), (8.5, 12), (3.5, 12), (3.5, 6), (0, 6)]
    }
    let points = if self.kind.contains("Arrows") {
      if direction == 1 || direction == 3 {
        let diagonal : Array[(Double, Double)] = [
          (1, 0),
          (12, 0),
          (12, 11),
          (8, 7),
          (3, 12),
          (0, 9),
          (5, 4),
        ]
        diagonal.map(pair => {
          if direction == 1 {
            (pair.0, 12.0 - pair.1)
          } else {
            pair
          }
        })
      } else {
        points.map(pair => {
          let (x, y) = pair
          if direction == 0 {
            (x, 12.0 - y)
          } else if direction == 2 {
            (12.0 - y, x)
          } else {
            (x, y)
          }
        })
      }
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
