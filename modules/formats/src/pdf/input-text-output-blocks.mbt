///|
priv struct PdfOutputBlock {
  x : Double
  y : Double
  html : String
  markdown : String
}

///|
fn output_table(
  table : PdfReadTable,
  links : Array[PdfOutputLink],
  used : Map[Int32, Bool],
) -> String raise @failure.Failure {
  let out = StringBuilder()
  out.write_string("<table><tbody>")
  for row in 0..<(table.ys.length() - 1) {
    out.write_string("<tr>")
    for cell in table.cells {
      if cell.row != row {
        continue
      }
      out <+ "<td rowspan=\"\{cell.rowSpan}\" colspan=\"\{cell.columnSpan}\">"
      for index, line in cell.lines {
        if index > 0 {
          out.write_string("<br>")
        }
        out.write_string(
          output_line(line, read_line_text(line), links, used, false),
        )
      }
      out.write_string("</td>")
    }
    out.write_string("</tr>")
  }
  out.write_string("</tbody></table>")
  out.to_string()
}

///|
fn output_image(
  image : PdfExtractedImage,
  remaining : Int32,
) -> String raise @failure.Failure {
  guard !image.rgba.is_empty() &&
    image.pixelWidth > 0 &&
    image.pixelHeight > 0 &&
    image.pixelWidth.to_int64() * image.pixelHeight.to_int64() * 4 ==
    image.rgba.length().to_int64() else {
    @failure.reject(
      "protected-content", "PDF output image requires verified decoded pixels",
    )
  }
  let matrix = image.transform
  let width = (matrix.a * matrix.a + matrix.b * matrix.b).sqrt()
  let height = (matrix.c * matrix.c + matrix.d * matrix.d).sqrt()
  guard !image.clipped &&
    width > 0 &&
    height > 0 &&
    matrix.a * matrix.d - matrix.b * matrix.c > 0 &&
    (matrix.a * matrix.c + matrix.b * matrix.d).abs() <= width * height * 0.001 else {
    @failure.reject(
      "protected-content", "Clipped, skewed or mirrored PDF output image cannot be reconstructed",
    )
  }
  let pixels = if image.opacity == 1 {
    image.rgba
  } else {
    Bytes::makei(image.rgba.length(), index => {
      if index % 4 == 3 {
        (image.rgba[index].to_int().to_double() * image.opacity)
        .round()
        .to_int()
        .to_byte()
      } else {
        image.rgba[index]
      }
    })
  }
  let png = @image.encode_png(image.pixelWidth, image.pixelHeight, pixels)
  guard png.length().to_int64() * 4 / 3 + 1024 <= remaining.to_int64() else {
    @failure.reject(
      "limit-exceeded", "PDF embedded output image exceeds budget",
    )
  }
  let angle = @math.atan2(matrix.b, matrix.a) * 180 / 3.141592653589793
  "<img alt=\"PDF image\" width=\"\{image.pixelWidth}\" height=\"\{image.pixelHeight}\" style=\"width:\{width}px;height:\{height}px;transform:rotate(\{angle}deg)\" src=\"data:image/png;base64,\{@base64.encode(png)}\">"
}

///|
fn output_blocks(
  extraction : PdfExtraction,
  lines : Array[PdfReadLine],
  tables : Array[PdfReadTable],
  links : Array[PdfOutputLink],
  warnings : Array[String],
  page : Int32,
  budget : Int32,
) -> Array[PdfOutputBlock] raise @failure.Failure {
  let blocks : Array[PdfOutputBlock] = []
  let used : Map[Int32, Bool] = Map([])
  for table in tables {
    let html = output_table(table, links, used)
    blocks.push({ x: table.xs[0], y: table.ys[0], html, markdown: html, })
    read_warning(
      warnings,
      "Page \{page}: Markdown tables use HTML to preserve cell spans without guessing headers",
    )
  }
  let outside = lines.filter(line => {
    !tables.any(table => read_line_in_table(line, table))
  })
  let mut i = 0
  while i < outside.length() {
    let line = outside[i]
    let text = read_line_text(line)
    let (kind, _, start) = output_list_marker(text)
    let mut end = i + 1
    if !kind.is_empty() && line.rotation.abs() < 0.01 {
      while end < outside.length() {
        let next = outside[end]
        let (nextKind, _, number) = output_list_marker(read_line_text(next))
        let prior = outside[end - 1]
        if nextKind != kind ||
          next.rotation.abs() >= 0.01 ||
          (next.x - line.x).abs() > 3 ||
          next.y - prior.y > prior.height * 2.5 ||
          (kind == "ol" && number != start + end - i) {
          break
        }
        end += 1
      }
    }
    if end > i + 1 {
      let html = StringBuilder()
      let md = StringBuilder()
      html <+ "<\{kind}"
      if kind == "ol" {
        html <+ " start=\"\{start}\""
      }
      html.write_string(">")
      for n in i..<end {
        let (_, body, number) = output_list_marker(read_line_text(outside[n]))
        html <+ "<li>\{output_line(outside[n], body, links, used, false)}</li>"
        let marker = if kind == "ol" { "\{number}. " } else { "- " }
        md <+ "\{marker}\{output_line(outside[n], body, links, used, true)}\n"
      }
      html <+ "</\{kind}>"
      blocks.push({
        x: line.x,
        y: line.y,
        html: html.to_string(),
        markdown: md.to_string(),
      })
      i = end
    } else {
      blocks.push({
        x: line.x,
        y: line.y,
        html: "<p>\{output_line(line, text, links, used, false)}</p>",
        markdown: output_line(line, text, links, used, true),
      })
      i += 1
    }
  }
  let mut remaining = budget
  for image in extraction.images {
    let html = output_image(image, remaining) catch {
      error => {
        if error is @failure.Failure(code~, ..) && code == "limit-exceeded" {
          raise error
        }
        read_warning(
          warnings,
          "Page \{page}: an image could not be safely reconstructed and was omitted",
        )
        continue
      }
    }
    remaining -= html.length()
    let (x, y, _, _) = read_bounds(image.quad)
    blocks.push({ x, y, html, markdown: html, })
  }
  for index, link in links {
    if !used.contains(index) {
      let html = "<p><a href=\"\{output_attribute(link.href)}\">\{@xml.escape_text(link.label)}</a></p>"
      blocks.push({ x: link.x, y: link.y, html, markdown: html, })
      read_warning(
        warnings,
        "Page \{page}: a link without a confidently associated complete text line is listed separately",
      )
    }
  }
  blocks.sort_by((a, b) => {
    if (a.y - b.y).abs() < 1 {
      a.x.compare(b.x)
    } else {
      a.y.compare(b.y)
    }
  })
  blocks
}
