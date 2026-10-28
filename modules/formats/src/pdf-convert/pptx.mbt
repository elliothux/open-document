///|
fn presentation_shapes(
  page : Page,
  scale : Double,
  dx : Double,
  dy : Double,
  warnings : Array[String],
  number : Int32,
) -> Array[@pptx.ContentShape] {
  let result : Array[@pptx.ContentShape] = []
  let used : Array[Int32] = []
  for table in page.tables {
    used.append(table.paths)
  }
  for index, path in page.paths {
    if used.contains(index) {
      continue
    }
    let mut current = (0.0, 0.0)
    let mut first = current
    let points : Array[Double] = []
    let mut closed = false
    let mut supported = true
    for segment in path.path {
      match segment {
        Move(x, y) => {
          current = (x, y)
          first = current
          points.append([x, y])
        }
        Line(x, y) => {
          current = (x, y)
          points.append([x, y])
        }
        Close => closed = true
        _ => supported = false
      }
    }
    if path.clipped ||
      !supported ||
      path.style.fillAlpha != 1 ||
      path.style.strokeAlpha != 1 ||
      path.style.multiply ||
      !path.style.dash.is_empty() {
      @pdf.read_warning(
        warnings,
        "Page \{number}: a complex or clipped path was omitted",
      )
      continue
    }
    if points.length() == 4 && !closed && path.fill.is_empty() {
      let x = points[0]
      let y = points[1]
      let r = points[2]
      let b = points[3]
      if (x - r).abs() <= 0.1 || (y - b).abs() <= 0.1 {
        result.push({
          kind: "line",
          x: dx + x.min(r) * scale,
          y: dy + y.min(b) * scale,
          width: (x - r).abs() * scale,
          height: (y - b).abs() * scale,
          fill: "",
          stroke: path.stroke,
          thickness: path.width * scale,
        })
      } else {
        @pdf.read_warning(
          warnings,
          "Page \{number}: a diagonal path was omitted",
        )
      }
    } else if closed && points.length() == 8 {
      let (x, y, r, b) = @pdf.read_bounds(points)
      let corners = Array::makei(4, i => {
        (points[i * 2] - x).abs() < 0.1 || (points[i * 2] - r).abs() < 0.1
      })
      if corners.all(value => value) {
        result.push({
          kind: "rect",
          x: dx + x * scale,
          y: dy + y * scale,
          width: (r - x) * scale,
          height: (b - y) * scale,
          fill: path.fill,
          stroke: path.stroke,
          thickness: path.width * scale,
        })
      } else {
        @pdf.read_warning(
          warnings,
          "Page \{number}: a nonrectangular shape was omitted",
        )
      }
    } else if !points.is_empty() {
      @pdf.read_warning(warnings, "Page \{number}: a complex path was omitted")
    }
    ignore(first)
    ignore(current)
  }
  result
}

///|
fn write_pptx(
  pages : Array[Page],
  budget : @archive.Budget,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  warnings : Array[String],
) -> (Bytes, Array[PageMap]) raise @failure.Failure {
  let slides : Array[@pptx.ContentSlide] = []
  let width = pages[0].width
  let height = pages[0].height
  for pageIndex, page in pages {
    let scale = (width / page.width).min(height / page.height)
    let dx = (width - page.width * scale) / 2
    let dy = (height - page.height * scale) / 2
    let texts : Array[@pptx.ContentText] = []
    for line in page.lines {
      let style = line.runs[0]
      if line.runs.length() > 1 {
        @pdf.read_warning(
          warnings,
          "Page \{pageIndex+1}: styling within a line was normalized to its first run",
        )
      }
      let angle = line.rotation * 3.141592653589793 / 180
      let centerX = line.x +
        @math.cos(angle) * line.width / 2 -
        @math.sin(angle) * line.height / 2
      let centerY = line.y +
        @math.sin(angle) * line.width / 2 +
        @math.cos(angle) * line.height / 2
      texts.push({
        text: @pdf.read_line_text(line),
        font: style.font,
        size: style.size * scale,
        color: style.color,
        bold: style.bold,
        italic: style.italic,
        x: dx + (centerX - line.width / 2) * scale,
        y: dy + (centerY - line.height / 2) * scale,
        width: line.width * scale + 0.5,
        height: line.height * scale + 0.5,
        rotation: line.rotation,
      })
    }
    let pictures = page.images.map(image => {
      let (x, y, w, h, rotation) = image_box(image)
      let picture : @pptx.ContentPicture = {
        bytes: image_bytes(image),
        x: dx + x * scale,
        y: dy + y * scale,
        width: w * scale,
        height: h * scale,
        rotation,
      }
      picture
    })
    let tables = page.tables.map(table => {
      let cells = table.cells.map(cell => {
        let style = cell.lines
          .iter()
          .filter_map(line => line.runs.get(0))
          .next()
          .unwrap_or({
            text: "",
            font: "Arial",
            identity: "",
            size: 11,
            color: "000000",
            bold: false,
            italic: false,
          })
        let value : @pptx.ContentTableCell = {
          row: cell.row,
          column: cell.column,
          rowSpan: cell.rowSpan,
          columnSpan: cell.columnSpan,
          text: cell.lines.map(@pdf.read_line_text).join("\n"),
          font: style.font,
          size: style.size * scale,
          color: style.color,
          bold: style.bold,
          italic: style.italic,
          fill: cell.fill,
        }
        value
      })
      let value : @pptx.ContentTable = {
        x: dx + table.xs[0] * scale,
        y: dy + table.ys[0] * scale,
        widths: Array::makei(table.xs.length() - 1, index => {
          (table.xs[index + 1] - table.xs[index]) * scale
        }),
        heights: Array::makei(table.ys.length() - 1, index => {
          (table.ys[index + 1] - table.ys[index]) * scale
        }),
        cells,
      }
      value
    })
    slides.push({
      texts,
      pictures,
      shapes: presentation_shapes(page, scale, dx, dy, warnings, pageIndex + 1),
      tables,
    })
  }
  let target = @pptx.Session::create_content(
    slides, width, height, budget, probe, profile,
  )
  defer target.close()
  guard target.query() is { "revision": Number(revision, ..), .. } else {
    abort("Expected native presentation revision")
  }
  (
    target.save(revision.to_int()),
    Array::makei(pages.length(), index => {
      source: pages[index].source,
      target: index + 1,
    }),
  )
}
