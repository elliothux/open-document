///|
fn conditional_icon_circle(radius : Double) -> Array[@layout.PathSegment] {
  let k = radius * 0.55228
  [
    Move(6 + radius, 6),
    Cubic(6 + radius, 6 + k, 6 + k, 6 + radius, 6, 6 + radius),
    Cubic(6 - k, 6 + radius, 6 - radius, 6 + k, 6 - radius, 6),
    Cubic(6 - radius, 6 - k, 6 - k, 6 - radius, 6, 6 - radius),
    Cubic(6 + k, 6 - radius, 6 + radius, 6 - k, 6 + radius, 6),
    Close,
  ]
}

///|
fn conditional_icon_polygon(
  points : Array[(Double, Double)],
) -> Array[@layout.PathSegment] {
  let segments : Array[@layout.PathSegment] = []
  for i, (x, y) in points {
    segments.push(if i == 0 { Move(x, y) } else { Line(x, y) })
  }
  segments.push(Close)
  segments
}

///|
fn ConditionalIcon::symbol_paths(
  self : ConditionalIcon,
  style : @layout.PathStyle,
) -> Array[@layout.PositionedPrimitive]? {
  let paths : Array[@layout.PositionedPrimitive] = []
  let colors = ["c00000", "ffc000", "00b050"]
  match self.kind {
    "3Signs" => {
      let path = match self.index {
        0 => conditional_icon_polygon([(6, 1), (11, 6), (6, 11), (1, 6)])
        1 => conditional_icon_polygon([(6, 1), (11, 11), (1, 11)])
        _ => conditional_icon_circle(5)
      }
      paths.push(Path(path, colors[self.index], "404040", 0.45, style))
    }
    "3Symbols" | "3Symbols2" => {
      let framed = self.kind == "3Symbols"
      let color = colors[self.index]
      if framed {
        paths.push(
          Path(conditional_icon_circle(5), color, "404040", 0.45, style),
        )
      }
      let mark = if framed { "ffffff" } else { color }
      let lines : Array[@layout.PathSegment] = match self.index {
        0 => [Move(3, 3), Line(9, 9), Move(9, 3), Line(3, 9)]
        1 => [Move(6, 2.5), Line(6, 7.5), Move(6, 9), Line(6, 10)]
        _ => [Move(2.5, 6), Line(5, 9), Line(10, 3)]
      }
      paths.push(Path(lines, "", mark, 1.8, style))
    }
    "3TrafficLights2" =>
      paths.append([
        Path(
          conditional_icon_polygon([(1, 1), (11, 1), (11, 11), (1, 11)]),
          "505050",
          "404040",
          0.45,
          style,
        ),
        Path(conditional_icon_circle(4.5), "ffffff", "", 0, style),
        Path(conditional_icon_circle(3.5), colors[self.index], "", 0, style),
      ])
    "4RedToBlack" | "4TrafficLights" => {
      let colors = if self.kind == "4RedToBlack" {
        ["505050", "9b9b9b", "ff8080", "c00000"]
      } else {
        ["505050", "c00000", "ffc000", "00b050"]
      }
      paths.push(
        Path(
          conditional_icon_circle(5),
          colors[self.index],
          "404040",
          0.45,
          style,
        ),
      )
    }
    "4Rating" | "5Rating" => {
      let filled = self.index + (if self.kind == "4Rating" { 1 } else { 0 })
      for i in 0..<4 {
        let x = i.to_double() * 3
        let y = 9.0 - i.to_double() * 2.5
        paths.push(
          Path(
            conditional_icon_polygon([
              (x, y),
              (x + 2.25, y),
              (x + 2.25, 12),
              (x, 12),
            ]),
            if i < filled {
              "2361be"
            } else {
              "cccccc"
            },
            "404040",
            0.3,
            style,
          ),
        )
      }
    }
    "5Quarters" => {
      paths.push(Path(conditional_icon_circle(5), "505050", "", 0, style))
      if self.index < 4 {
        paths.push(Path(conditional_icon_circle(4.2), "ffffff", "", 0, style))
      }
      if self.index > 0 && self.index < 4 {
        let quarters : Array[@layout.PathSegment] = [
          Cubic(8.319576, 1.8, 10.2, 3.680424, 10.2, 6),
          Cubic(10.2, 8.319576, 8.319576, 10.2, 6, 10.2),
          Cubic(3.680424, 10.2, 1.8, 8.319576, 1.8, 6),
        ]
        paths.push(
          Path(
            [
              Move(6, 6),
              Line(6, 1.8),
              ..quarters[:self.index],
              Line(6, 6),
              Close,
            ],
            "505050",
            "",
            0,
            style,
          ),
        )
      }
    }
    _ => return None
  }
  Some(paths)
}
