///|
fn SheetObject::paint(
  self : SheetObject,
  primitives : Array[@layout.PositionedPrimitive],
  rect : @layout.Border,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  slicer_hover~ : Int32? = None,
  view~ : Bool = false,
  after_bar3d~ : Bool = false,
  screen_scale~ : Double? = None,
  chart_tiles~ : ChartTiles? = None,
) -> Unit raise @failure.Failure {
  if self.timeline is Some(timeline) {
    if self.visible && rect.width > 0 && rect.height > 0 {
      timeline.paint(primitives, rect, probe, profile)
    }
    return
  }
  if self.slicer is Some(slicer) {
    if self.visible && rect.width > 0 && rect.height > 0 {
      slicer.paint(primitives, rect, probe, profile, hover=slicer_hover)
    }
    return
  }
  if self.chart is Some((_, chart)) {
    if self.visible && rect.width > 0 && rect.height > 0 {
      primitives.push(Clip(self.paint_bounds(rect)))
      primitives.push(
        Transform({ a: 1, b: 0, c: 0, d: 1, e: rect.x, f: rect.y, }),
      )
      let key = (self.id, rect.width, rect.height)
      if chart_tiles.bind(tiles => tiles.entries.get(key)) is Some(painted) {
        primitives.append(painted)
      } else {
        let painted = chart.paint(
          rect.width,
          rect.height,
          probe,
          profile,
          visible=self.chart_visibility,
          after_bar3d~,
          print=!view,
        )
        if view &&
          (chart.native_circular is Some(_) || chart.native_bubble is Some(_)) &&
          screen_scale is Some(scale) {
          probe.fit_screen_text(painted, scale)
        }
        primitives.append(
          match chart_tiles {
            Some(tiles) => tiles.keep(key, painted, probe)
            None => painted
          },
        )
      }
      primitives.push(Restore)
      primitives.push(Restore)
    }
    return
  }
  if self.shape is Some(shape) {
    if self.visible {
      shape.paint(primitives, rect, probe, profile)
    }
    return
  }
  if !self.visible || rect.width <= 0 || rect.height <= 0 {
    return
  }
  let width = rect.width / (1 - self.crop[0] - self.crop[2])
  let height = rect.height / (1 - self.crop[1] - self.crop[3])
  primitives.push(Clip(rect))
  primitives.push(
    Image(
      {
        key: picture_key(self.media.unwrap()),
        interpolate: if !view && self.crop.any(value => value != 0) {
          Some(false)
        } else {
          None
        },
        x: rect.x - self.crop[0] * width,
        y: rect.y - self.crop[1] * height,
        width,
        height,
      },
      1,
    ),
  )
  primitives.push(Restore)
}

///|
fn drawing_used(
  used : Range,
  pictures : Array[SheetObject],
  dimensions : Dimensions,
) -> Range {
  pictures.fold(init=used, (range, picture) => {
    top: range.top.min(dimensions.rows.locate(picture.rect.y)),
    left: range.left.min(dimensions.columns.locate(picture.rect.x)),
    bottom: range.bottom.max(
      if picture.rect.height == 0 {
        dimensions.rows.locate(picture.rect.y)
      } else {
        dimensions.rows.last_before(picture.rect.y + picture.rect.height)
      },
    ),
    right: range.right.max(
      if picture.rect.width == 0 {
        dimensions.columns.locate(picture.rect.x)
      } else {
        dimensions.columns.last_before(picture.rect.x + picture.rect.width)
      },
    ),
  })
}

///|
fn drawing_diagnostic(
  sheet : Sheet,
  diagnostic : String,
) -> Bool raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  tree
  .one(tree.sheet_root().id, "drawing")
  .map(node => diagnostic == "unrendered:" + sheet.id + ":" + node.qualified)
  .unwrap_or(false)
}

///|
pub fn Session::picture_keys(
  self : Session,
  revision : Int32,
) -> Array[String] raise @failure.Failure {
  self.check_revision(revision)
  let relations = self.relationships()
  let drawings = relations
    .filter(rel => {
      !rel.external &&
      rel.kind == relationship_uri + "drawing" &&
      self.sheets.any(sheet => sheet.id == rel.owner)
    })
    .map(rel => rel.target)
  let keys : Map[String, Unit] = Map([])
  let referenced : Map[(String, String), Unit] = Map([])
  for part in drawings {
    for node in self.part_xml(part).nodes() {
      if node.uri == picture_drawing_uri &&
        node.name == "blip" &&
        node.attribute(
          "embed",
          uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
        )
        is Some(id) {
        referenced[(part, id)] = ()
      }
    }
  }
  for rel in relations {
    if referenced.contains((rel.owner, rel.id)) &&
      !rel.external &&
      rel.kind == relationship_uri + "image" {
      keys[picture_key(rel.target)] = ()
    }
  }
  keys.keys().to_array()
}
