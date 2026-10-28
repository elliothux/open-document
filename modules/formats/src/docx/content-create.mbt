///|
pub(all) struct ContentRun {
  text : String
  font : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
}

///|
pub(all) struct ContentCell {
  row : Int32
  column : Int32
  rowSpan : Int32
  columnSpan : Int32
  runs : Array[ContentRun]
  fill : String
}

///|
pub(all) enum ContentBlock {
  ParagraphBlock(Array[ContentRun], Bool)
  TableBlock(Array[Double], Int32, Array[ContentCell], Bool)
  PictureBlock(Bytes, Int32, Int32, Bytes, Double, Double, Bool)
}

///|
fn content_runs(runs : Array[ContentRun]) -> String raise @failure.Failure {
  let output = StringBuilder()
  for run in runs {
    guard run.size >= 1 &&
      run.size <= 14400 &&
      run.text.length() <= 32767 &&
      run.color.length() == 6 &&
      run.color
      .iter()
      .all(c => "0123456789abcdefABCDEF".contains(c.to_string())) else {
      @failure.reject(
        "invalid-operation", "Native document run exceeds style or text limits",
      )
    }
    let family = property_attribute(run.font)
    output <+
      "<w:r><w:rPr><w:rFonts w:ascii=\"\{family}\" w:hAnsi=\"\{family}\" w:eastAsia=\"\{family}\" w:cs=\"\{family}\"/><w:sz w:val=\"\{(run.size * 2).round().to_int()}\"/><w:color w:val=\"\{run.color}\"/>\{if run.bold { "<w:b/>" } else { "" }}\{if run.italic { "<w:i/>" } else { "" }}</w:rPr>"
    for index, line in run.text.split("\n").to_array() {
      if index > 0 {
        output.write_string("<w:br/>")
      }
      output <+
        "<w:t xml:space=\"preserve\">\{@xml.escape_text(line.to_owned())}</w:t>"
    }
    output.write_string("</w:r>")
  }
  output.to_string()
}

///|
fn content_table(
  widths : Array[Double],
  rows : Int32,
  cells : Array[ContentCell],
) -> String raise @failure.Failure {
  guard !widths.is_empty() &&
    widths.length() <= 63 &&
    rows > 0 &&
    rows * widths.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Native document table exceeds limits")
  }
  let owners = Array::make(rows * widths.length(), -1)
  for index, cell in cells {
    guard cell.row >= 0 &&
      cell.column >= 0 &&
      cell.rowSpan > 0 &&
      cell.columnSpan > 0 &&
      cell.row + cell.rowSpan <= rows &&
      cell.column + cell.columnSpan <= widths.length() else {
      @failure.reject("invalid-operation", "Native table spans exceed the grid")
    }
    for row in cell.row..<(cell.row + cell.rowSpan) {
      for column in cell.column..<(cell.column + cell.columnSpan) {
        let slot = row * widths.length() + column
        guard owners[slot] == -1 else {
          @failure.reject("invalid-operation", "Native table spans overlap")
        }
        owners[slot] = index
      }
    }
  }
  guard owners.all(owner => owner >= 0) else {
    @failure.reject(
      "invalid-operation", "Native table cells do not cover their grid",
    )
  }
  let output = StringBuilder()
  output.write_string(
    "<w:tbl><w:tblPr><w:tblLayout w:type=\"fixed\"/><w:tblBorders>",
  )
  for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
    output <+ "<w:\{side} w:val=\"single\" w:sz=\"8\" w:color=\"000000\"/>"
  }
  output.write_string("</w:tblBorders></w:tblPr><w:tblGrid>")
  for width in widths {
    guard width > 0 && width <= 14400 else {
      @failure.reject("invalid-operation", "Invalid native table width")
    }
    output <+ "<w:gridCol w:w=\"\{(width * 20).round().to_int()}\"/>"
  }
  output.write_string("</w:tblGrid>")
  for row in 0..<rows {
    output.write_string("<w:tr>")
    for column = 0; column < widths.length(); {
      let cell = cells[owners[row * widths.length() + column]]
      guard cell.column == column else {
        @failure.reject("invalid-operation", "Invalid native table ownership")
      }
      let width = widths[column:column + cell.columnSpan]
        .iter()
        .fold(init=0.0, (a, b) => a + b)
      output <+
        "<w:tc><w:tcPr><w:tcW w:w=\"\{(width * 20).round().to_int()}\" w:type=\"dxa\"/>"
      if cell.columnSpan > 1 {
        output <+ "<w:gridSpan w:val=\"\{cell.columnSpan}\"/>"
      }
      if cell.rowSpan > 1 {
        output.write_string(
          if row == cell.row {
            "<w:vMerge w:val=\"restart\"/>"
          } else {
            "<w:vMerge/>"
          },
        )
      }
      if !cell.fill.is_empty() {
        output <+ "<w:shd w:fill=\"\{property_attribute(cell.fill)}\"/>"
      }
      output <+
        "</w:tcPr><w:p>\{if row == cell.row { content_runs(cell.runs) } else { "" }}</w:p></w:tc>"
      continue column + cell.columnSpan
    }
    output.write_string("</w:tr>")
  }
  output.write_string("</w:tbl>")
  output.to_string()
}

///|
/// Construct native paragraphs, tables and pictures with the existing fragment transaction.
pub fn Session::create_content(
  blocks : Array[ContentBlock],
  page : @layout.PageSetup,
  budget : @archive.Budget,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Session, Array[Int32]) raise @failure.Failure {
  guard !blocks.is_empty() && blocks.length() <= 1024 else {
    @failure.reject(
      "limit-exceeded", "Native document content exceeds block limits",
    )
  }
  let session = Session::create(budget)
  errdefer session.close()
  ignore(session.set_page_setup(0, 0, page))
  let output = StringBuilder()
  let pixels : Map[String, (Int32, Int32, Bytes)] = Map([])
  output <+ "<w:body xmlns:w=\"\{word_uri}\">"
  for index, block in blocks {
    match block {
      ParagraphBlock(runs, pageBreak) =>
        output <+
          "<w:p>\{if pageBreak { "<w:pPr><w:pageBreakBefore/></w:pPr>" } else { "" }}\{content_runs(runs)}</w:p>"
      TableBlock(widths, rows, cells, pageBreak) => {
        if pageBreak {
          output.write_string("<w:p><w:pPr><w:pageBreakBefore/></w:pPr></w:p>")
        }
        output.write_string(content_table(widths, rows, cells))
      }
      PictureBlock(
        bytes,
        pixelWidth,
        pixelHeight,
        rgba,
        width,
        height,
        pageBreak
      ) => {
        ignore(@image.type_info(bytes))
        let encoded = @base64.encode(bytes)
        pixels[encoded] = (pixelWidth, pixelHeight, rgba)
        let drawing = picture_markup(
          index + 1,
          "image\{index}",
          width,
          height,
          bytes=Some(encoded),
        )
        output <+
          "<w:p>\{if pageBreak { "<w:pPr><w:pageBreakBefore/></w:pPr>" } else { "" }}<w:r>\{drawing}</w:r></w:p>"
      }
    }
  }
  output.write_string("</w:body>")
  let paragraph = session.flow().paragraphs[0].id
  let position : Position = {
    paragraph,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
  let fragment = output.to_string()
  let images = @layout.Images::new()
  defer images.clear()
  guard session.body_fragment_images(1, fragment)
    is { "images": Array(assets), .. } else {
    abort("Expected native fragment image list")
  }
  for asset in assets {
    guard asset is { "key": String(key), "bytes": String(encoded), .. } &&
      pixels.get(encoded) is Some((width, height, rgba)) else {
      @failure.reject(
        "missing-image", "Imported document image has no decoded pixels",
      )
    }
    images.add(key, width, height, rgba)
  }
  ignore(
    session.paste_body_fragment(
      1,
      { anchor: position, focus: position, },
      fragment,
      probe,
      profile,
      images=Some(images),
    ),
  )
  let flow = session.flow()
  let layout = @layout.paginate(probe, flow, profile, images)
  let pages = [1]
  for paragraph in flow.paragraphs {
    if paragraph.pageBreakBefore {
      pages.push(layout.caret(paragraph.id, 0, "after").page + 1)
    }
  }
  (session, pages)
}
