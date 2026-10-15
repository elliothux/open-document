///|
struct MeasuredLine {
  line : Line
  textHeight : Double
}

///|
fn LineSpacing::percent(self : LineSpacing) -> Double {
  match self {
    Auto(value) => {
      let percent = (value * 100 / 240).round()
      if percent == 0 {
        100
      } else {
        percent.max(50)
      }
    }
    _ => 100
  }
}

///|
fn LineSpacing::gap(
  self : LineSpacing,
  text_height : Double,
) -> Double raise @failure.Failure {
  let gap = ((text_height * 20).round() * (self.percent() - 100).max(0) / 100).floor() /
    20
  guard !gap.is_nan() && !gap.is_inf() else {
    @failure.reject("invalid-style", "Invalid automatic line spacing")
  }
  gap
}

///|
fn LineSpacing::terminal_gap(
  self : LineSpacing,
  size : Double,
) -> Double raise @failure.Failure {
  // Writer's final cell/header spacing uses the paragraph font and its 1.15 factor.
  let gap = (size * 20 * (self.percent() - 100).max(0) * 1.15 / 100).floor() /
    20
  guard !gap.is_nan() && !gap.is_inf() else {
    @failure.reject("invalid-style", "Invalid terminal line spacing")
  }
  gap
}

///|
fn MeasuredLine::spaced(
  self : MeasuredLine,
  spacing : LineSpacing,
  first : Bool,
) -> Line {
  guard spacing is Auto(_) else { return self.line }
  let line = self.line
  let percent = spacing.percent()
  let change = if first {
    0.0
  } else {
    let twips = (self.textHeight * 20).round() * (percent - 100) / 100
    (if twips < 0 { twips.ceil() } else { twips.floor() }) / 20
  }
  let height = if percent < 100 && first {
    (line.height * 20 * percent / 100).floor().max(1) / 20
  } else {
    (line.height + change).max(0.05)
  }
  let delta = if percent < 100 {
    let ascent = match line.runs.get(0) {
      Some(run) => run.baseline + run.rise
      None =>
        line.images.get(0).map(image => image.y + image.height).unwrap_or(0)
    }
    (height * 20 * 4 / 5).floor() / 20 - ascent
  } else {
    change
  }
  {
    ..line,
    height,
    runs: line.runs.map(run => { ..run, baseline: run.baseline + delta, }),
    images: line.images.map(image => { ..image, y: image.y + delta, }),
  }
}
