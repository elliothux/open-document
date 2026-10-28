///|
pub(all) enum ShowInkChange {
  BeginInk(String, Double, Array[(Double, Double)])
  AppendInk(Array[(Double, Double)])
  FinishInk(Array[(Double, Double)])
  CancelInk
  ClearInk
}

///|
priv struct ShowInkStroke {
  color : String
  width : Double
  points : Array[(Double, Double)]
}

///|
pub fn Session::ink_show(
  self : Session,
  revision : Int32,
  layout : Int32,
  time : Double,
  change : ShowInkChange,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  ignore(self.current_show_frame(layout))
  let show = self.showing.unwrap().advance(time)
  let points = match change {
    BeginInk(_, _, points) | AppendInk(points) | FinishInk(points) => points
    _ => []
  }
  guard points.length() <= 64 &&
    points.all(point => {
      let (x, y) = point
      !x.is_nan() &&
      !x.is_inf() &&
      !y.is_nan() &&
      !y.is_inf() &&
      x >= 0 &&
      x <= self.width &&
      y >= 0 &&
      y <= self.height
    }) else {
    @failure.reject(
      "invalid-operation", "Ink requires at most 64 points inside the slide",
    )
  }
  let next = match change {
    CancelInk => { ..show, ink_draft: None, }
    ClearInk => {
      let ink = show.ink.copy()
      let strokes = ink.get(show.index).unwrap_or([])
      ink.remove(show.index)
      {
        ..show,
        ink,
        ink_draft: None,
        ink_strokes: show.ink_strokes - strokes.length(),
        ink_points: show.ink_points -
        strokes.fold(init=0, (sum, stroke) => sum + stroke.points.length()),
      }
    }
    _ => {
      let stroke = match change {
        BeginInk(color, width, _) => {
          guard show.ink_draft is None && !points.is_empty() else {
            @failure.reject(
              "invalid-operation", "Finish or cancel the active ink stroke",
            )
          }
          guard color.length() == 6 &&
            color
            .iter()
            .all(c => "0123456789abcdefABCDEF".contains(c.to_string())) &&
            !width.is_nan() &&
            !width.is_inf() &&
            width >= 0.5 &&
            width <= 24 else {
            @failure.reject("invalid-operation", "Invalid ink color or width")
          }
          { color, width, points: points.copy(), }
        }
        _ => {
          guard show.ink_draft is Some(stroke) else {
            @failure.reject("invalid-operation", "Begin an ink stroke first")
          }
          guard change is FinishInk(_) || !points.is_empty() else {
            @failure.reject("invalid-operation", "Ink append requires points")
          }
          { ..stroke, points: stroke.points + points, }
        }
      }
      guard show.ink_strokes < 256 &&
        stroke.points.length() <= 4096 &&
        show.ink_points <= 32768 - stroke.points.length() else {
        @failure.reject(
          "limit-exceeded", "Slideshow ink exceeds stroke or point budget",
        )
      }
      if change is FinishInk(_) {
        let ink = show.ink.copy()
        ink[show.index] = ink.get(show.index).unwrap_or([]) + [stroke]
        {
          ..show,
          ink,
          ink_draft: None,
          ink_strokes: show.ink_strokes + 1,
          ink_points: show.ink_points + stroke.points.length(),
        }
      } else {
        { ..show, ink_draft: Some(stroke), }
      }
    }
  }
  let result = self.show_state(Some(next))
  self.showing = Some(next)
  result
}

///|
fn ink_region(
  region : @layout.DrawingRegion,
  strokes : Array[ShowInkStroke],
  draft~ : ShowInkStroke? = None,
) -> @layout.DrawingRegion {
  let strokes = strokes + draft.map(stroke => [stroke]).unwrap_or([])
  guard !strokes.is_empty() else { return region }
  let commands : Array[@layout.DrawCommand] = [
    ..region.commands,
    ClipRect({ x: 0, y: 0, width: region.width, height: region.height, }),
    Style({ ..@layout.DrawStyle::default(), cap: 1, join: 1, }),
  ]
  for stroke in strokes {
    let path : Array[@layout.PathSegment] = stroke.points.mapi((index, point) => {
      let (x, y) = point
      if index == 0 {
        Move(x, y)
      } else {
        Line(x, y)
      }
    })
    if stroke.points is [(x, y)] {
      path.push(Line(x + 0.01, y))
    }
    commands.push(Path(path, "", stroke.color, stroke.width))
  }
  commands.push(Restore)
  { ..region, commands, }
}
