///|
fn word_runs(lines : Array[@pdf.PdfReadLine]) -> Array[@docx.ContentRun] {
  let result : Array[@docx.ContentRun] = []
  for index, line in lines {
    for runIndex, run in line.runs {
      result.push({
        text: (if index > 0 && runIndex == 0 { "\n" } else { "" }) + run.text,
        font: run.font,
        size: run.size,
        color: run.color,
        bold: run.bold,
        italic: run.italic,
      })
    }
  }
  result
}

///|
fn write_docx(
  pages : Array[Page],
  budget : @archive.Budget,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  warnings : Array[String],
) -> (Bytes, Array[PageMap]) raise @failure.Failure {
  let blocks : Array[@docx.ContentBlock] = []
  for pageIndex, page in pages {
    let ordered : Array[(Double, Int32, Int32)] = []
    for index, line in page.lines {
      ordered.push((line.y, 0, index))
    }
    for index, table in page.tables {
      ordered.push((table.ys[0], 1, index))
    }
    for index, image in page.images {
      ordered.push((@pdf.read_bounds(image.quad).1, 2, index))
    }
    ordered.sort_by((a, b) => a.0.compare(b.0))
    let mut first = pageIndex > 0
    for (_, kind, index) in ordered {
      if kind == 0 {
        let line = page.lines[index]
        if line.rotation.abs() > 0.01 {
          @pdf.read_warning(
            warnings,
            "Page \{pageIndex+1}: rotated text was reflowed as ordinary paragraphs",
          )
        }
        blocks.push(@docx.ParagraphBlock(word_runs([line]), first))
      } else if kind == 1 {
        let table = page.tables[index]
        let widths = Array::makei(table.xs.length() - 1, column => {
          table.xs[column + 1] - table.xs[column]
        })
        let cells = table.cells.map(cell => {
          (
            {
              row: cell.row,
              column: cell.column,
              rowSpan: cell.rowSpan,
              columnSpan: cell.columnSpan,
              runs: word_runs(cell.lines),
              fill: cell.fill,
            } : @docx.ContentCell)
        })
        blocks.push(
          @docx.TableBlock(widths, table.ys.length() - 1, cells, first),
        )
      } else {
        let image = page.images[index]
        let (_, _, width, height, rotation) = image_box(image)
        guard image.rgba.length() > 0 else {
          @failure.reject(
            "conversion-unavailable", "DOCX image conversion requires decoded source pixels",
          )
        }
        if rotation.abs() > 0.01 {
          @pdf.read_warning(
            warnings,
            "Page \{pageIndex+1}: rotated pictures were placed as unrotated inline images",
          )
        }
        let fit = (pages[0].width / width).min(1)
        blocks.push(
          @docx.PictureBlock(
            image_bytes(image),
            image.pixelWidth,
            image.pixelHeight,
            image.rgba,
            width * fit,
            height * fit,
            first,
          ),
        )
      }
      first = false
    }
    if ordered.is_empty() {
      blocks.push(@docx.ParagraphBlock([], first))
    }
  }
  let (target, mapping) = @docx.Session::create_content(
    blocks,
    {
      width: (pages[0].width * 20).round() / 20,
      height: (pages[0].height * 20).round() / 20,
      top: 0,
      right: 0,
      bottom: 0,
      left: 0,
    },
    budget,
    probe,
    profile,
  )
  defer target.close()
  guard mapping.length() == pages.length() else {
    @failure.reject(
      "conversion-unavailable", "Native Word page mapping could not be established",
    )
  }
  (
    target.save(),
    Array::makei(pages.length(), index => {
      source: pages[index].source,
      target: mapping[index],
    }),
  )
}
