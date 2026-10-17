///|
pub struct ImageTile {
  sx : Double
  sy : Double
  tx : Double
  ty : Double
  align : String
  flip : String
} derive(Eq, Debug)

///|
pub extend ImageTile with Eq::{equal, not_equal}

///|
pub extend ImageTile with Debug::{to_repr}

///|
priv struct TileGrid {
  width : Double
  height : Double
  x : Double
  y : Double
  left : Double
  top : Double
  columns : Int
  rows : Int
}

///|
fn ImageTile::default() -> ImageTile {
  { sx: 100000, sy: 100000, tx: 0, ty: 0, align: "tl", flip: "none", }
}

///|
fn read_image_tile(tile : Ref) -> ImageTile raise @failure.Failure {
  guard tile.node.attributes.all(a => {
      a.uri.is_empty() &&
      ["sx", "sy", "tx", "ty", "algn", "flip"].contains(a.name)
    }) &&
    tile.tree.children.get(tile.node.id).unwrap_or([]).is_empty() else {
    @failure.reject(
      "unsupported-style", "Unknown image tile metadata is protected",
    )
  }
  let align = tile.node.attribute("algn").unwrap_or("tl")
  let flip = tile.node.attribute("flip").unwrap_or("none")
  guard ["tl", "t", "tr", "l", "ctr", "r", "bl", "b", "br"].contains(align) &&
    ["none", "x", "y", "xy"].contains(flip) else {
    @failure.reject("unsupported-style", "Unknown image tile alignment or flip")
  }
  {
    sx: number(tile.node.attribute("sx").unwrap_or("100000"), 1, 100000000),
    sy: number(tile.node.attribute("sy").unwrap_or("100000"), 1, 100000000),
    tx: number(tile.node.attribute("tx").unwrap_or("0"), -182880000, 182880000),
    ty: number(tile.node.attribute("ty").unwrap_or("0"), -182880000, 182880000),
    align,
    flip,
  }
}

///|
fn ImageTile::markup(self : ImageTile) -> String {
  "<a:tile xmlns:a=\"\{drawing_uri}\" sx=\"\{self.sx.round().to_int64()}\" sy=\"\{self.sy.round().to_int64()}\" tx=\"\{self.tx.round().to_int64()}\" ty=\"\{self.ty.round().to_int64()}\" algn=\"\{self.align}\" flip=\"\{self.flip}\"/>"
}

///|
fn ImageTile::grid(
  self : ImageTile,
  shape_width : Double,
  shape_height : Double,
  pixels : (Int, Int),
) -> TileGrid raise @failure.Failure {
  // ONLYOFFICE uses 96 DPI rather than embedded image DPI for texture sizing.
  let width = pixels.0.to_double() * 0.75 * self.sx / 100000
  let height = pixels.1.to_double() * 0.75 * self.sy / 100000
  let ax = if ["t", "ctr", "b"].contains(self.align) {
    0.5
  } else if ["tr", "r", "br"].contains(self.align) {
    1.0
  } else {
    0.0
  }
  let ay = if ["l", "ctr", "r"].contains(self.align) {
    0.5
  } else if ["bl", "b", "br"].contains(self.align) {
    1.0
  } else {
    0.0
  }
  let x = (shape_width - width) * ax + self.tx / 12700
  let y = (shape_height - height) * ay + self.ty / 12700
  let left = (-x / width).floor()
  let top = (-y / height).floor()
  let columns = ((shape_width - x) / width).ceil() - left
  let rows = ((shape_height - y) / height).ceil() - top
  guard columns > 0 && rows > 0 && columns * rows <= 65536 else {
    @failure.reject("limit-exceeded", "Slide image tiles exceed 65536")
  }
  {
    width,
    height,
    x: x + left * width,
    y: y + top * height,
    left,
    top,
    columns: columns.to_int(),
    rows: rows.to_int(),
  }
}

///|
fn Session::tile_sizes(
  self : Session,
  slide : Slide,
  media~ : Map[String, Bytes] = self.media,
  width~ : Double = self.width,
  height~ : Double = self.height,
) -> Map[String, (Int, Int)] raise @failure.Failure {
  let sizes : Map[String, (Int, Int)] = Map([])
  let mut count = 0
  let entries : Array[(String, ImageTile, Double, Double)] = []
  if slide.background is Picture(key, _, _, Some(tile)) {
    entries.push((key, tile, width, height))
  }
  for object in slide.objects {
    if object.tile is Some(tile) &&
      object.geometry is Some(geometry) &&
      object.diagnostic.is_empty() {
      entries.push(
        (object.image.unwrap(), tile, geometry.width, geometry.height),
      )
    }
  }
  for (key, tile, width, height) in entries {
    let pixels = sizes
      .get(key)
      .unwrap_or_else(() => {
        let (_, _, width, height) = @image.type_info(
          media.get(key).unwrap_or_else(() => self.opc.read(key)),
        )
        sizes[key] = (width, height)
        (width, height)
      })
    let grid = tile.grid(width, height, pixels)
    count += grid.columns * grid.rows
    guard count <= 65536 else {
      @failure.reject("limit-exceeded", "Slide image tiles exceed 65536")
    }
  }
  sizes
}

///|
fn ImageTile::paint(
  tile : ImageTile,
  key : String,
  opacity : Double,
  width : Double,
  height : Double,
  pixels : (Int, Int),
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let grid = tile.grid(width, height, pixels)
  let result : Array[@layout.PositionedPrimitive] = []
  for row in 0..<grid.rows {
    let index_y = grid.top + row.to_double()
    let flip_y = ["y", "xy"].contains(tile.flip) &&
      index_y != (index_y / 2).floor() * 2
    for column in 0..<grid.columns {
      let index_x = grid.left + column.to_double()
      let flip_x = ["x", "xy"].contains(tile.flip) &&
        index_x != (index_x / 2).floor() * 2
      result.push(
        Transform({
          a: if flip_x {
            -1
          } else {
            1
          },
          b: 0,
          c: 0,
          d: if flip_y {
            -1
          } else {
            1
          },
          e: grid.x +
          (column.to_double() + (if flip_x { 1.0 } else { 0.0 })) * grid.width,
          f: grid.y +
          (row.to_double() + (if flip_y { 1.0 } else { 0.0 })) * grid.height,
        }),
      )
      result.push(
        Image(
          { key, x: 0, y: 0, width: grid.width, height: grid.height, },
          opacity,
        ),
      )
      result.push(Restore)
    }
  }
  result
}

///|
fn check_image_fill_mode(mode : String) -> Unit raise @failure.Failure {
  guard ["stretch", "tile"].contains(mode) else {
    @failure.reject("invalid-operation", "Unknown image fill mode")
  }
}

///|
fn image_fill_mode_change(
  fill : Ref,
  mode : String,
) -> @xml.SourceChange raise @failure.Failure {
  let previous = fill
    .child(if mode == "tile" { "stretch" } else { "tile" })
    .unwrap()
  paint_child_change(
    fill,
    Some(previous.node),
    if mode == "tile" {
      ImageTile::default().markup()
    } else {
      "<a:stretch xmlns:a=\"\{drawing_uri}\"><a:fillRect/></a:stretch>"
    },
    [],
  )
}

///|
fn Session::set_image_fill_mode(
  self : Session,
  mode : String,
) -> Json raise @failure.Failure {
  check_image_fill_mode(mode)
  let targets = self.image_fill_targets()
  let changes : Array[@xml.SourceChange] = []
  for object in targets {
    guard object.image is Some(_) &&
      object.fill_source is Some((fill, _)) &&
      fill.tree.part == object.source.tree.part else {
      @failure.reject(
        "protected-content", "Set a local image fill before changing its mode",
      )
    }
    guard mode != "tile" || object.crop.all(v => v == 0) else {
      @failure.reject("protected-content", "Cropped tile sources are protected")
    }
    if (if object.tile is Some(_) { "tile" } else { "stretch" }) == mode {
      continue
    }
    changes.push(image_fill_mode_change(fill, mode))
  }
  if changes.is_empty() {
    return self.query()
  }
  let original = self.current()
  let (candidate, edit) = self.prepare(original, changes)
  self.commit(candidate, edit, self.selection)
  self.query()
}
