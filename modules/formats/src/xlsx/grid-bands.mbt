///|
priv struct GridBand {
  indices : Array[Int]
  scroll : Double
  start : Double
  size : Double
  frozen : Bool
}

///|
fn Grid::range_geometry(self : Grid, range : Range, frozen : Frozen) -> Json {
  let rects : Array[@layout.Border] = []
  for row in self.rows {
    for column in self.columns {
      let top = range.top.max(if row.frozen { 1 } else { frozen.rows + 1 })
      let bottom = range.bottom.min(
        if row.frozen {
          frozen.rows
        } else {
          1048576
        },
      )
      let left = range.left.max(
        if column.frozen {
          1
        } else {
          frozen.columns + 1
        },
      )
      let right = range.right.min(
        if column.frozen {
          frozen.columns
        } else {
          16384
        },
      )
      if top > bottom || left > right {
        continue
      }
      let rect : @layout.Border = {
        x: self.dimensions.columns.position(left) + 36 - column.scroll,
        y: self.dimensions.rows.position(top) + 18 - row.scroll,
        width: self.dimensions.columns.position(right + 1) -
        self.dimensions.columns.position(left),
        height: self.dimensions.rows.position(bottom + 1) -
        self.dimensions.rows.position(top),
      }
      let clipped = grid_intersection(rect, {
        x: 36 + column.start,
        y: 18 + row.start,
        width: column.size,
        height: row.size,
      })
      if clipped.width > 0 && clipped.height > 0 {
        rects.push(clipped)
      }
    }
  }
  {
    "x": self.dimensions.columns.position(range.left) +
    36 -
    (if range.left <= frozen.columns && self.columns.any(band => band.frozen) {
      0
    } else {
      self.scroll_x
    }),
    "y": self.dimensions.rows.position(range.top) +
    18 -
    (if range.top <= frozen.rows && self.rows.any(band => band.frozen) {
      0
    } else {
      self.scroll_y
    }),
    "width": self.dimensions.columns.position(range.right + 1) -
    self.dimensions.columns.position(range.left),
    "height": self.dimensions.rows.position(range.bottom + 1) -
    self.dimensions.rows.position(range.top),
    "rects": rects,
  }
}

///|
fn Axis::bands(
  self : Axis,
  frozen : Int,
  scroll : Double,
  viewport : Double,
  extent : Int,
) -> Array[GridBand] raise @failure.Failure {
  let result : Array[GridBand] = []
  let size = self.position(frozen + 1).min(viewport)
  if size > 0 {
    result.push({
      indices: self.visible(1, self.locate(size).min(frozen)),
      scroll: 0,
      start: 0,
      size,
      frozen: true,
    })
  }
  if size < viewport {
    result.push({
      indices: self.visible(
        self.locate(self.position(frozen + 1) + scroll).max(frozen + 1),
        self.locate(viewport + scroll).min(extent),
      ),
      scroll,
      start: size,
      size: viewport - size,
      frozen: false,
    })
  }
  result
}

///|
fn append_grid_paint(
  primitives : Array[@layout.PositionedPrimitive],
  page : PagePaint,
  clip : @layout.Border,
) -> Unit {
  primitives.push(Clip(clip))
  primitives.append(page.positioned().primitives)
  primitives.push(Restore)
}

///|
fn grid_header(
  page : PagePaint,
  text : String,
  rect : @layout.Border,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  font : String,
) -> Unit raise @failure.Failure {
  page.fills.push({
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height,
    color: "f1f3f5",
  })
  page.strokes.push((rect, "d9dce1", 0.5))
  place_block(
    page,
    probe.text_block(
      text,
      @layout.TextStyle::new(font, 9, "333333"),
      profile,
      (rect.width - 4.5).max(1).min(14400),
      false,
    ),
    rect,
    "center",
    "center",
  )
}

///|
fn grid_intersection(
  rect : @layout.Border,
  clip : @layout.Border,
) -> @layout.Border {
  let x = rect.x.max(clip.x)
  let y = rect.y.max(clip.y)
  {
    x,
    y,
    width: ((rect.x + rect.width).min(clip.x + clip.width) - x).max(0),
    height: ((rect.y + rect.height).min(clip.y + clip.height) - y).max(0),
  }
}

///|
fn Session::paint_grid(
  self : Session,
  index : Int,
  dimensions : Dimensions,
  rows : Array[GridBand],
  columns : Array[GridBand],
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Array[@layout.PositionedPrimitive], Array[Json], Array[Json], Array[Json]) raise @failure.Failure {
  let primitives : Array[@layout.PositionedPrimitive] = []
  let cells : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let count = rows.fold(init=0L, (sum, row) => {
      sum + row.indices.length().to_int64()
    }) *
    columns.fold(init=0L, (sum, column) => {
      sum + column.indices.length().to_int64()
    })
  guard count <= 4096L else {
    @failure.reject("limit-exceeded", "Visible cells exceed 4096 cells")
  }
  let mut units = 0
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
  }
  let conditional = self.conditional_rules(
    self.sheets[index],
    index,
    self.sheets,
    work,
  )
  for row in rows {
    for column in columns {
      let page : PagePaint = {
        width,
        height,
        texts: [],
        fills: [],
        strokes: [],
      }
      let clip : @layout.Border = {
        x: 36 + column.start,
        y: 18 + row.start,
        width: column.size,
        height: row.size,
      }
      for
        item in self.paint_cells(
          index,
          dimensions,
          row.indices,
          column.indices,
          page,
          36 - column.scroll,
          18 - row.scroll,
          probe,
          profile,
          false,
          conditional,
          work,
        ) {
        guard item is Object(fields) &&
          fields["cell"] is { "address": String(address), .. } &&
          fields["display"] is String(display) else {
          abort("Grid cell invariant")
        }
        units += display.length()
        guard units <= 262144 else {
          @failure.reject("limit-exceeded", "Visible text exceeds budget")
        }
        if !seen.contains(address) {
          fields["clip"] = Json(clip)
          cells.push(item)
          seen[address] = true
        }
      }
      append_grid_paint(primitives, page, clip)
    }
  }
  let row_headers : Array[Json] = []
  let column_headers : Array[Json] = []
  for row in rows {
    let page : PagePaint = { width, height, texts: [], fills: [], strokes: [], }
    for index in row.indices {
      let position = dimensions.rows.position(index) + 18 - row.scroll
      let size = dimensions.rows.size(index)
      grid_header(
        page,
        index.to_string(),
        { x: 0, y: position, width: 36, height: size, },
        probe,
        profile,
        self.styles[0].font,
      )
      row_headers.push({ "index": index, "position": position, "size": size })
    }
    append_grid_paint(primitives, page, {
      x: 0,
      y: 18 + row.start,
      width: 36,
      height: row.size,
    })
  }
  for column in columns {
    let page : PagePaint = { width, height, texts: [], fills: [], strokes: [], }
    for index in column.indices {
      let position = dimensions.columns.position(index) + 36 - column.scroll
      let size = dimensions.columns.size(index)
      let address : Address = { row: 1, column: index, }
      let name = address.name()
      grid_header(
        page,
        name[:name.length() - 1].to_owned(),
        { x: position, y: 0, width: size, height: 18, },
        probe,
        profile,
        self.styles[0].font,
      )
      column_headers.push({ "index": index, "position": position, "size": size })
    }
    append_grid_paint(primitives, page, {
      x: 36 + column.start,
      y: 0,
      width: column.size,
      height: 18,
    })
  }
  let corner : PagePaint = { width, height, texts: [], fills: [], strokes: [], }
  grid_header(
    corner,
    "",
    { x: 0, y: 0, width: 36, height: 18, },
    probe,
    profile,
    self.styles[0].font,
  )
  primitives.append(corner.positioned().primitives)
  for column in columns {
    if column.frozen && column.size < width - 36 {
      primitives.push(
        Stroke(
          { x: 36 + column.size, y: 18, width: 0, height: height - 18, },
          "94a3b8",
          1,
        ),
      )
    }
  }
  for row in rows {
    if row.frozen && row.size < height - 18 {
      primitives.push(
        Stroke(
          { x: 36, y: 18 + row.size, width: width - 36, height: 0, },
          "94a3b8",
          1,
        ),
      )
    }
  }
  (primitives, cells, row_headers, column_headers)
}
