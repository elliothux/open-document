///|
priv struct GridBand {
  indices : Array[Int32]
  scroll : Double
  start : Double
  size : Double
  frozen : Bool
}

///|
fn grid_rect(
  rect : @layout.Border,
  width : Double,
  rtl : Bool,
) -> @layout.Border {
  if rtl {
    { ..rect, x: width - rect.x - rect.width, }
  } else {
    rect
  }
}

///|
#derive(ToJson)
pub struct SelectionGeometry {
  x : Double
  y : Double
  width : Double
  height : Double
  rects : Array[@layout.Border]
}

///|
pub extend SelectionGeometry with ToJson::{to_json}

///|
fn Grid::range_geometry(
  self : Grid,
  range : Range,
  frozen : Frozen,
) -> SelectionGeometry {
  let header_width = self.header_width
  let header_height = self.header_height
  let rects : Array[@layout.Border] = []
  for row in self.rows {
    for column in self.columns {
      let top = range.top.max(if row.frozen { 1 } else { frozen.rows + 1 })
      let bottom = range.bottom.min(
        if row.frozen {
          frozen.rows
        } else {
          WorksheetRows
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
          WorksheetColumns
        },
      )
      if top > bottom || left > right {
        continue
      }
      let rect : @layout.Border = {
        x: self.dimensions.columns.position(left) + header_width - column.scroll,
        y: self.dimensions.rows.position(top) + header_height - row.scroll,
        width: self.dimensions.columns.position(right + 1) -
        self.dimensions.columns.position(left),
        height: self.dimensions.rows.position(bottom + 1) -
        self.dimensions.rows.position(top),
      }
      let clipped = grid_rect(
        grid_intersection(rect, {
          x: header_width + column.start,
          y: header_height + row.start,
          width: column.size,
          height: row.size,
        }),
        self.width,
        self.rtl,
      )
      if clipped.width > 0 && clipped.height > 0 {
        rects.push(clipped)
      }
    }
  }
  let rect = self.range_rect(range, frozen)
  { x: rect.x, y: rect.y, width: rect.width, height: rect.height, rects, }
}

///|
fn Grid::range_rect(
  self : Grid,
  range : Range,
  frozen : Frozen,
) -> @layout.Border {
  grid_rect(
    {
      x: self.dimensions.columns.position(range.left) +
      self.header_width -
      (if range.left <= frozen.columns && self.columns.any(band => band.frozen) {
        0
      } else {
        self.scroll_x
      }),
      y: self.dimensions.rows.position(range.top) +
      self.header_height -
      (if range.top <= frozen.rows && self.rows.any(band => band.frozen) {
        0
      } else {
        self.scroll_y
      }),
      width: self.dimensions.columns.position(range.right + 1) -
      self.dimensions.columns.position(range.left),
      height: self.dimensions.rows.position(range.bottom + 1) -
      self.dimensions.rows.position(range.top),
    },
    self.width,
    self.rtl,
  )
}

///|
fn Axis::bands(
  self : Axis,
  frozen : Int32,
  scroll : Double,
  viewport : Double,
  extent : Int32,
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
pub struct ViewportChartTile {
  index : Int32
  key : String
  body : Json
}

///|
fn grid_commands_json(
  commands : Array[@layout.DrawCommand],
  chart_tiles? : Array[ViewportChartTile],
) -> Json {
  let output : Array[Json] = []
  let mut index = 0
  while index < commands.length() {
    let command = commands[index]
    index += 1
    if command is StrokeRect(rect, color, width, screen_fractional=false) &&
      commands.get(index)
      is Some(StrokeRect(_, next_color, next_width, screen_fractional=false)) &&
      color == next_color &&
      width == next_width {
      let bands = [(rect.y, rect.height, [(rect.x, rect.width)])]
      while commands.get(index)
            is Some(
              StrokeRect(next, next_color, next_width, screen_fractional=false),
            ) &&
            color == next_color &&
            width == next_width {
        let (y, height, spans) = bands[bands.length() - 1]
        if y == next.y && height == next.height {
          spans.push((next.x, next.width))
        } else {
          bands.push((next.y, next.height, [(next.x, next.width)]))
        }
        index += 1
      }
      output.push({
        "op": "strokeBands",
        "color": color,
        "lineWidth": width,
        "bands": bands,
      })
    } else {
      if chart_tiles is Some(tiles) && command is CachedDrawing(key, body) {
        tiles.push({ index: output.length(), key, body, })
      }
      output.push(Json(command))
    }
  }
  Json::array(output)
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
  page.bars.push(Stroke(rect, "d9dce1", 0.5))
  ignore(
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
      0,
    ),
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
  index : Int32,
  dimensions : Dimensions,
  rows : Array[GridBand],
  columns : Array[GridBand],
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  notes : Map[String, CellNote],
  objects : Array[SheetObject],
  slicer_hover : (String, Int32)?,
  screen_scale : Double?,
  chart_wire : Bool,
  compact_cells : Bool,
) -> (
  Array[@layout.PositionedPrimitive],
  Array[(PaintedCell, Int32)],
  Array[@layout.Border],
  Array[Json],
  Array[Json],
  Array[Json],
  ConditionalRules,
) raise @failure.Failure {
  let (header_width, header_height) = self.sheets[index].view.header_size()
  let rtl = self.sheets[index].view.rtl
  let primitives : Array[@layout.PositionedPrimitive] = []
  let cells : Array[(PaintedCell, Int32)] = []
  let clips : Array[@layout.Border] = []
  let visible_notes : Array[Json] = []
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
    random: None,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let conditional = self.read_conditional_rules(index, work)
  let chart_tiles = if objects.any(object => object.chart is Some(_)) {
    Some(
      self.chart_tiles(
        self.sheets[index].id,
        probe,
        profile,
        screen_scale,
        objects,
        chart_wire,
      ),
    )
  } else {
    None
  }
  for row in rows {
    for column in columns {
      let page : PagePaint = {
        width,
        height,
        texts: [],
        cells: [],
        anchors: [],
        fills: [],
        bars: [],
        strokes: [],
      }
      let markers : Array[@layout.PositionedPrimitive] = []
      let clip = grid_rect(
        {
          x: header_width + column.start,
          y: header_height + row.start,
          width: column.size,
          height: row.size,
        },
        width,
        rtl,
      )
      let clip_index = clips.length()
      clips.push(clip)
      for
        item in (if self.sheets[index].is_chart() {
          []
        } else {
          self.paint_cells(
            index,
            dimensions,
            row.indices,
            column.indices,
            page,
            header_width - column.scroll,
            header_height - row.scroll,
            probe,
            profile,
            false,
            width,
            conditional,
            work,
            compact=compact_cells,
          )
        }) {
        let address = item.address
        units += item.text.length()
        guard units <= 262144 else {
          @failure.reject("limit-exceeded", "Visible text exceeds budget")
        }
        if !seen.contains(address) {
          cells.push((item, clip_index))
          seen[address] = true
        }
        if notes.get(address) is Some(note) {
          let rect = item.rect
          let visible = grid_intersection(rect, clip)
          if visible.width > 0 && visible.height > 0 {
            visible_notes.push({
              "address": address,
              "author": note.author,
              "text": note.text,
              "rect": visible,
            })
            markers.push(note_marker(rect, rtl))
          }
        }
      }
      append_grid_paint(primitives, page, clip)
      if !markers.is_empty() {
        primitives.push(Clip(clip))
        primitives.append(markers)
        primitives.push(Restore)
      }
      for picture in objects {
        let rect = grid_rect(
          {
            ..picture.rect,
            x: picture.rect.x + header_width - column.scroll,
            y: picture.rect.y + header_height - row.scroll,
          },
          width,
          rtl,
        )
        let visible = grid_intersection(picture.paint_bounds(rect), clip)
        if visible.width > 0 && visible.height > 0 {
          primitives.push(Clip(clip))
          picture.paint(
            primitives,
            rect,
            probe,
            profile,
            view=true,
            screen_scale~,
            chart_tiles~,
            slicer_hover=slicer_hover
              .filter(item => item.0 == picture.id)
              .map(item => item.1),
          )
          primitives.push(Restore)
        }
      }
    }
  }
  let row_headers : Array[Json] = []
  let column_headers : Array[Json] = []
  if self.sheets[index].view.headings {
    for row in rows {
      let band = grid_rect(
        {
          x: 0,
          y: header_height + row.start,
          width: header_width,
          height: row.size,
        },
        width,
        rtl,
      )
      let page : PagePaint = {
        width,
        height,
        texts: [],
        cells: [],
        anchors: [],
        fills: [],
        bars: [],
        strokes: [],
      }
      for index in row.indices {
        let position = dimensions.rows.position(index) +
          header_height -
          row.scroll
        let size = dimensions.rows.size(index)
        let label = index.to_string()
        let rect = grid_rect(
          { x: 0, y: position, width: header_width, height: size, },
          width,
          rtl,
        )
        grid_header(page, label, rect, probe, profile, self.styles[0].font)
        row_headers.push({
          "index": index,
          "position": position,
          "size": size,
          "label": label,
          "clip": Json(grid_intersection(rect, band)),
        })
      }
      append_grid_paint(primitives, page, band)
    }
    for column in columns {
      let band = grid_rect(
        {
          x: header_width + column.start,
          y: 0,
          width: column.size,
          height: header_height,
        },
        width,
        rtl,
      )
      let page : PagePaint = {
        width,
        height,
        texts: [],
        cells: [],
        anchors: [],
        fills: [],
        bars: [],
        strokes: [],
      }
      for index in column.indices {
        let position = dimensions.columns.position(index) +
          header_width -
          column.scroll
        let size = dimensions.columns.size(index)
        let position = if rtl { width - position - size } else { position }
        let address : Address = { row: 1, column: index, }
        let name = address.name()
        let label = name[:name.length() - 1].to_owned()
        let rect : @layout.Border = {
          x: position,
          y: 0,
          width: size,
          height: header_height,
        }
        grid_header(page, label, rect, probe, profile, self.styles[0].font)
        column_headers.push({
          "index": index,
          "position": position,
          "size": size,
          "label": label,
          "clip": Json(grid_intersection(rect, band)),
        })
      }
      append_grid_paint(primitives, page, band)
    }
    let corner : PagePaint = {
      width,
      height,
      texts: [],
      cells: [],
      anchors: [],
      fills: [],
      bars: [],
      strokes: [],
    }
    grid_header(
      corner,
      "",
      grid_rect(
        { x: 0, y: 0, width: header_width, height: header_height, },
        width,
        rtl,
      ),
      probe,
      profile,
      self.styles[0].font,
    )
    primitives.append(corner.positioned().primitives)
  }
  for column in columns {
    if column.frozen && column.size < width - header_width {
      primitives.push(
        Stroke(
          grid_rect(
            {
              x: header_width + column.size,
              y: header_height,
              width: 0,
              height: height - header_height,
            },
            width,
            rtl,
          ),
          "94a3b8",
          1,
        ),
      )
    }
  }
  for row in rows {
    if row.frozen && row.size < height - header_height {
      primitives.push(
        Stroke(
          grid_rect(
            {
              x: header_width,
              y: header_height + row.size,
              width: width - header_width,
              height: 0,
            },
            width,
            rtl,
          ),
          "94a3b8",
          1,
        ),
      )
    }
  }
  (
    primitives, cells, clips, row_headers, column_headers, visible_notes, conditional,
  )
}
