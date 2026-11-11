///|
priv struct ChartTiles {
  sheet : String
  probe : @layout.TextProbe
  fonts : Int32
  profile : Map[String, String]
  scale : Double?
  objects : Array[SheetObject]
  wire : Bool
  generation : Int32
  entries : Map[(String, Double, Double), Array[@layout.PositionedPrimitive]]
  mut units : Int32
}

///|
fn Session::chart_tiles(
  self : Session,
  sheet : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  scale : Double?,
  objects : Array[SheetObject],
  wire : Bool,
) -> ChartTiles raise @failure.Failure {
  let cache = self.read_cache()
  let fonts = probe.font_info().length()
  if cache.chart_tiles is Some(tiles) &&
    tiles.sheet == sheet &&
    physical_equal(tiles.probe, probe) &&
    tiles.fonts == fonts &&
    tiles.profile == profile &&
    tiles.scale == scale &&
    physical_equal(tiles.objects, objects) &&
    tiles.wire == wire {
    return tiles
  }
  let tiles = {
    sheet,
    probe,
    fonts,
    profile: profile.copy(),
    scale,
    objects,
    wire,
    generation: self.grid_id,
    entries: Map([]),
    units: 0,
  }
  cache.chart_tiles = Some(tiles)
  tiles
}

///|
fn ChartTiles::keep(
  self : ChartTiles,
  key : (String, Double, Double),
  tile : Array[@layout.PositionedPrimitive],
  probe : @layout.TextProbe,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let mut units = 1
  for primitive in tile {
    units += 8
    match primitive {
      Text(text) => {
        units += text.text.length()
        for run in text.runs {
          units += 8 + run.text.length() + run.glyphs.length() * 12
        }
      }
      Path(segments, _, _, _, pen) =>
        units += segments.length() * 8 + pen.dash.length()
      TextRule(segments, _, _) | ClipPath(segments, _) =>
        units += segments.length() * 8
      GradientRectangle(_, stops) | RadialGradientRectangle(_, stops) =>
        units += stops.length() * 8
      PatternRectangle(_, _, mask, _, _, ..) => units += mask.length()
      _ => ()
    }
    if units > 262144 - self.units {
      return tile
    }
  }
  let tile = if self.wire &&
    !tile.is_empty() &&
    !tile.any(primitive => {
      primitive
      is (Image(_, _) | GradientRectangle(_, _) | RadialGradientRectangle(_, _))
    }) {
    let (_, width, height) = key
    let document : @layout.PositionedDocument = {
      pages: [{ width, height, primitives: tile, }],
      fonts: probe.font_info(),
      links: [],
    }
    let region = document.drawing(@layout.Images::new(), clear=false)[0]
    let commands = region.commands[1:region.commands.length() - 1].to_owned()
    [
      @layout.PositionedPrimitive::CachedDrawing(
        "\{self.generation}:\{key.0}",
        grid_commands_json(commands),
      ),
    ]
  } else {
    tile
  }
  self.entries[key] = tile
  self.units += units
  tile
}
