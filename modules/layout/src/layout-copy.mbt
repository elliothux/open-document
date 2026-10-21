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
    marker: self.marker.map(run => run.copy_geometry()),
    carets: self.carets.copy(),
    bars: self.bars.copy(),
    drawings: self.drawings.map(image => {
      ..image,
      content: image.content.copy(),
    }),
  }
}

///|
fn CellArea::copy_geometry(self : CellArea) -> CellArea {
  { ..self, paragraphs: self.paragraphs.copy(), }
}

///|
fn PageFrame::copy_geometry(self : PageFrame) -> PageFrame {
  {
    ..self,
    lines: self.lines.map(line => line.copy_geometry()),
    borders: self.borders.copy(),
    fills: self.fills.copy(),
    cellAreas: self.cellAreas.map(area => area.copy_geometry()),
  }
}

///|
fn PageFrame::validate_images(
  self : PageFrame,
  images : Images,
) -> Unit raise @failure.Failure {
  for line in self.lines {
    for image in line.drawings {
      if image.content is Picture(key, _) {
        ignore(images.get(key))
      }
    }
  }
}
