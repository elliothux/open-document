///|
fn PlacedRun::copy_geometry(self : PlacedRun) -> PlacedRun {
  {
    ..self,
    sources: self.sources.copy(),
    glyphs: self.glyphs.copy(),
    bidi: self.bidi.copy(),
    decorations: self.decorations.copy(),
  }
}

///|
fn Line::copy_geometry(self : Line) -> Line {
  {
    ..self,
    runs: self.runs.map(run => run.copy_geometry()),
    carets: self.carets.copy(),
    bars: self.bars.copy(),
    images: self.images.copy(),
  }
}

///|
fn PageFrame::copy_geometry(self : PageFrame) -> PageFrame {
  {
    ..self,
    lines: self.lines.map(line => line.copy_geometry()),
    borders: self.borders.copy(),
    fills: self.fills.copy(),
  }
}

///|
fn PageFrame::validate_images(
  self : PageFrame,
  images : Images,
) -> Unit raise @failure.Failure {
  for line in self.lines {
    for image in line.images {
      ignore(images.get(image.key))
    }
  }
}
