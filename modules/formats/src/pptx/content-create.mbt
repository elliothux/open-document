///|
pub(all) struct ContentText {
  text : String
  font : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
}

///|
pub(all) struct ContentPicture {
  bytes : Bytes
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
}

///|
pub(all) struct ContentShape {
  kind : String
  x : Double
  y : Double
  width : Double
  height : Double
  fill : String
  stroke : String
  thickness : Double
}

///|
pub(all) struct ContentTableCell {
  row : Int32
  column : Int32
  rowSpan : Int32
  columnSpan : Int32
  text : String
  font : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
  fill : String
}

///|
pub(all) struct ContentTable {
  x : Double
  y : Double
  widths : Array[Double]
  heights : Array[Double]
  cells : Array[ContentTableCell]
}

///|
pub(all) struct ContentSlide {
  texts : Array[ContentText]
  pictures : Array[ContentPicture]
  shapes : Array[ContentShape]
  tables : Array[ContentTable]
}

///|
fn content_text_body(
  text : String,
  font : String,
  size : Double,
  color : String,
  bold~ : Bool = false,
  italic~ : Bool = false,
) -> String raise @failure.Failure {
  guard size >= 1 &&
    size <= 14400 &&
    color.length() == 6 &&
    color.iter().all(c => "0123456789abcdefABCDEF".contains(c.to_string())) else {
    @failure.reject("invalid-operation", "Invalid imported text style")
  }
  object_text_markup(
    text,
    style="<a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:latin typeface=\"\{xml_attribute(font)}\"/><a:ea typeface=\"\{xml_attribute(font)}\"/>",
    attributes="sz=\"\{(size * 100).round().to_int()}\" b=\"\{if bold { 1 } else { 0 }}\" i=\"\{if italic { 1 } else { 0 }}\"",
  ).replace_all(
    old="<a:bodyPr wrap=\"square\" anchor=\"t\">",
    new="<a:bodyPr wrap=\"none\" anchor=\"t\" lIns=\"0\" rIns=\"0\" tIns=\"0\" bIns=\"0\">",
  )
}

///|
fn content_presentation_table(
  id : String,
  table : ContentTable,
) -> String raise @failure.Failure {
  let rows = table.heights.length()
  let columns = table.widths.length()
  guard rows > 0 && columns > 0 && columns <= 63 && rows * columns <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Imported presentation table exceeds limits",
    )
  }
  let owners = Array::make(rows * columns, -1)
  for index, cell in table.cells {
    guard cell.row >= 0 &&
      cell.column >= 0 &&
      cell.rowSpan > 0 &&
      cell.columnSpan > 0 &&
      cell.row + cell.rowSpan <= rows &&
      cell.column + cell.columnSpan <= columns else {
      @failure.reject(
        "invalid-operation", "Imported table spans exceed their grid",
      )
    }
    for row in cell.row..<(cell.row + cell.rowSpan) {
      for column in cell.column..<(cell.column + cell.columnSpan) {
        let slot = row * columns + column
        guard owners[slot] == -1 else {
          @failure.reject("invalid-operation", "Imported table spans overlap")
        }
        owners[slot] = index
      }
    }
  }
  guard owners.all(owner => owner >= 0) else {
    @failure.reject(
      "invalid-operation", "Imported table cells do not cover the grid",
    )
  }
  let width = table.widths.iter().fold(init=0.0, (a, b) => a + b)
  let height = table.heights.iter().fold(init=0.0, (a, b) => a + b)
  let markup = table_markup(id, rows, columns, table.x, table.y, width, height)
  let tree = Tree::new(
    "content",
    @xml.Document::parse(@utf8.encode(markup), "content", 64, 4194304),
  )
  let source = tree.document.source()
  let tableNode = tree.document
    .nodes()
    .filter(node => node.uri == drawing_uri && node.name == "tbl")[0]
  let output = StringBuilder()
  output.write_string(
    "<a:tbl xmlns:a=\"\{drawing_uri}\"><a:tblPr><a:tableStyleId>ODCONVERT</a:tableStyleId></a:tblPr><a:tblGrid>",
  )
  for width in table.widths {
    guard width > 14.4 else {
      @failure.reject(
        "invalid-transform", "Imported table columns leave no text width",
      )
    }
    output <+ "<a:gridCol w=\"\{(width * 12700).round().to_int64()}\"/>"
  }
  output.write_string("</a:tblGrid>")
  let borders = ["lnL", "lnR", "lnT", "lnB"]
    .map(side => {
      "<a:\{side} w=\"12700\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:\{side}>"
    })
    .join("")
  for row in 0..<rows {
    output <+
      "<a:tr h=\"\{(table.heights[row] * 12700).round().to_int64().max(1L)}\">"
    for column in 0..<columns {
      let cell = table.cells[owners[row * columns + column]]
      let root = cell.row == row && cell.column == column
      let rowSpan = if cell.column == column {
        cell.rowSpan - (row - cell.row)
      } else {
        1
      }
      let columnSpan = if cell.row == row {
        cell.columnSpan - (column - cell.column)
      } else {
        1
      }
      let text = content_text_body(
        if root {
          cell.text
        } else {
          ""
        },
        cell.font,
        cell.size,
        cell.color,
        bold=cell.bold,
        italic=cell.italic,
      ).replace_all(old="p:txBody", new="a:txBody")
      output <+
        "<a:tc rowSpan=\"\{rowSpan}\" gridSpan=\"\{columnSpan}\" hMerge=\"\{if column > cell.column { 1 } else { 0 }}\" vMerge=\"\{if row > cell.row { 1 } else { 0 }}\">\{text}<a:tcPr>\{borders}<a:solidFill><a:srgbClr val=\"\{xml_attribute(cell.fill)}\"/></a:solidFill></a:tcPr></a:tc>"
    }
    output.write_string("</a:tr>")
  }
  output.write_string("</a:tbl>")
  source[:tableNode.start].to_owned() +
  output.to_string() +
  source[tableNode.end:].to_owned()
}

///|
fn content_slide_fragment(
  slide : ContentSlide,
) -> String raise @failure.Failure {
  let count = slide.texts.length() +
    slide.pictures.length() +
    slide.shapes.length() +
    slide.tables.length()
  guard count > 0 && count <= 256 else {
    @failure.reject(
      "limit-exceeded", "Imported slide requires 1 to 256 native objects",
    )
  }
  let source = StringBuilder()
  source <+
    "<p:spTree xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\">"
  let selected : Array[String] = []
  let resources : Array[Json] = []
  if !slide.tables.is_empty() {
    resources.push({
      "id": "ODCONVERT",
      "kind": "tableStyle",
      "value": "<a:tblStyle xmlns:a=\"\{drawing_uri}\" styleId=\"ODCONVERT\" styleName=\"Converted native cells\"/>",
    })
  }
  let mut sequence = 1
  for text in slide.texts {
    let id = sequence.to_string()
    sequence += 1
    selected.push(id)
    let originalBody = object_text_markup(text.text)
    let body = content_text_body(
      text.text,
      text.font,
      text.size,
      text.color,
      bold=text.bold,
      italic=text.italic,
    )
    let markup = object_markup(
      id,
      "text",
      text.x,
      text.y,
      text.width,
      text.height,
      text.text,
    ).replace_all(old=originalBody, new=body)
    source.write_string(
      markup.replace_all(
        old="<a:xfrm>",
        new="<a:xfrm rot=\"\{(text.rotation * 60000).round().to_int64()}\">",
      ),
    )
  }
  for picture in slide.pictures {
    let id = sequence.to_string()
    sequence += 1
    selected.push(id)
    validate_object_box(
      picture.x,
      picture.y,
      picture.width,
      picture.height,
      false,
    )
    ignore(@image.type_info(picture.bytes))
    let link = "image\{id}"
    resources.push({
      "id": link,
      "kind": "image",
      "value": @base64.encode(picture.bytes),
    })
    source <+
      "<p:pic><p:nvPicPr><p:cNvPr id=\"\{id}\" name=\"Picture \{id}\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\{link}\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm rot=\"\{(picture.rotation * 60000).round().to_int64()}\"><a:off x=\"\{(picture.x * 12700).round().to_int64()}\" y=\"\{(picture.y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(picture.width * 12700).round().to_int64()}\" cy=\"\{(picture.height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
  }
  for shape in slide.shapes {
    let id = sequence.to_string()
    sequence += 1
    selected.push(id)
    let original = object_markup(
      id,
      shape.kind,
      shape.x,
      shape.y,
      shape.width,
      shape.height,
      "",
    )
    let fill = if shape.fill.is_empty() {
      "<a:noFill/>"
    } else {
      "<a:solidFill><a:srgbClr val=\"\{xml_attribute(shape.fill)}\"/></a:solidFill>"
    }
    let stroke = if shape.stroke.is_empty() {
      "<a:noFill/>"
    } else {
      "<a:solidFill><a:srgbClr val=\"\{xml_attribute(shape.stroke)}\"/></a:solidFill>"
    }
    let document = @xml.Document::parse(
      @utf8.encode(original),
      "content-shape",
      64,
      4194304,
    )
    let properties = document
      .nodes()
      .filter(node => node.uri == presentation_uri && node.name == "spPr")[0]
    let children = document
      .nodes()
      .filter(node => {
        node.parent == properties.id &&
        node.uri == drawing_uri &&
        (node.name == "solidFill" || node.name == "noFill" || node.name == "ln")
      })
    let changes : Array[@xml.SourceChange] = children
      .iter()
      .map(node => {
        let change : @xml.SourceChange = {
          node: properties.id,
          offset: node.start - properties.start,
          length: node.end - node.start,
          xml: if node.name == "ln" {
            "<a:ln w=\"\{(shape.thickness * 12700).round().to_int64().max(1L)}\">\{stroke}</a:ln>"
          } else {
            fill
          },
        }
        change
      })
      .collect()
    source.write_string(document.edit_source(changes).0.source())
  }
  for table in slide.tables {
    let id = sequence.to_string()
    sequence += 1
    selected.push(id)
    source.write_string(content_presentation_table(id, table))
  }
  source.write_string("</p:spTree>")
  let data : Json = {
    "source": source.to_string(),
    "selection": selected,
    "active": selected[0],
    "resources": resources,
  }
  data.stringify()
}

///|
/// Build each slide as one native-object transaction with existing resource import.
pub fn Session::create_content(
  slides : Array[ContentSlide],
  width : Double,
  height : Double,
  budget : @archive.Budget,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Session raise @failure.Failure {
  guard !slides.is_empty() && slides.length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Imported presentation exceeds slide limits",
    )
  }
  let session = Session::create(budget)
  errdefer session.close()
  ignore(
    session.edit_slides(
      0,
      session.selection.slide,
      Size(width, height),
      probe~,
      profile~,
    ),
  )
  for index, slide in slides {
    if index > 0 {
      ignore(
        session.edit_slides(
          session.revision,
          session.selection.slide,
          AddSlide,
          probe~,
          profile~,
        ),
      )
    }
    if slide.texts.is_empty() &&
      slide.pictures.is_empty() &&
      slide.shapes.is_empty() &&
      slide.tables.is_empty() {
      continue
    }
    ignore(
      session.paste_object_fragment(
        session.revision,
        content_slide_fragment(slide),
        probe,
        profile,
      ),
    )
  }
  session
}
