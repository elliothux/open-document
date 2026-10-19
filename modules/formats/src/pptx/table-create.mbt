///|
fn table_markup(
  id : String,
  rows : Int,
  columns : Int,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> String raise @failure.Failure {
  let w = (width * 12700).round().to_int64()
  let h = (height * 12700).round().to_int64()
  let output = StringBuilder()
  output.write_string(
    "<p:graphicFrame xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvGraphicFramePr><p:cNvPr id=\"\{id}\" name=\"Table \{id}\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{w}\" cy=\"\{h}\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr/><a:tblGrid>",
  )
  for column in 0..<columns {
    // Partition integer EMUs so the grid exactly fills its frame.
    let cell_width = w * (column + 1).to_int64() / columns.to_int64() -
      w * column.to_int64() / columns.to_int64()
    guard cell_width > 182880 else {
      @failure.reject("invalid-transform", "Table columns leave no text width")
    }
    output.write_string("<a:gridCol w=\"\{cell_width}\"/>")
  }
  output.write_string("</a:tblGrid>")
  let text = object_text_markup("")
    .replace(old="<p:txBody>", new="<a:txBody>")
    .replace(old="</p:txBody>", new="</a:txBody>")
  let borders = ["lnL", "lnR", "lnT", "lnB"]
    .map(side => {
      "<a:\{side} w=\"12700\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill></a:\{side}>"
    })
    .join("")
  let cell = "<a:tc>\{text}<a:tcPr>\{borders}<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill></a:tcPr></a:tc>"
  for row in 0..<rows {
    let row_height = (h * (row + 1).to_int64() / rows.to_int64() -
    h * row.to_int64() / rows.to_int64()).max(1L)
    output.write_string(
      "<a:tr h=\"\{row_height}\">\{cell.repeat(columns)}</a:tr>",
    )
  }
  output.write_string("</a:tbl></a:graphicData></a:graphic></p:graphicFrame>")
  output.to_string()
}

///|
fn Session::insert_table(
  self : Session,
  rows : Int,
  columns : Int,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard rows >= 1 &&
    rows <= 1000 &&
    columns >= 1 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid table dimensions")
  }
  validate_object_box(x, y, width, height, false)
  let original = self.current()
  let id = self.next_object_identity()
  let identity = original.tree.part + "#" + id
  let markup = table_markup(id, rows, columns, x, y, width, height)
  let (candidate, edit) = self.prepare_table(
    original,
    [object_insertion(original.tree, markup)],
    identity,
    probe,
    profile,
  )
  self.commit(
    candidate,
    edit,
    {
      ..self.selection,
      object: identity,
      objects: [identity],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    probe~,
    profile~,
  )
  self.object_sequence = number(id, 1, 4294967295).to_int64() + 1
  self.query()
}
