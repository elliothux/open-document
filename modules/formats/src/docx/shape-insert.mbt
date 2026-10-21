///|
/// Inserts an inline shape; supplying text creates a native editable text box.
pub fn Session::insert_shape(
  self : Session,
  revision : Int,
  preset : String,
  width : Double,
  height : Double,
  fill : String,
  stroke : String,
  line_width : Double,
  text? : String,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let (width, height, line_width) = check_shape_properties(
    preset, width, height, fill, stroke, line_width,
  )
  let content = match text {
    Some(text) => {
      guard preset != "line" else {
        @failure.reject("invalid-operation", "Line shapes cannot contain text")
      }
      text_box_markup(
        text,
        self.opc.budget.entry_bytes.min(history_byte_limit / 2),
      )
    }
    None => ""
  }
  let identity = self.next_drawing_identity()
  let cx = (width * 12700).round().to_int64()
  let cy = (height * 12700).round().to_int64()
  let paint = shape_fill_markup(fill.to_upper())
  let line = shape_fill_markup(stroke.to_upper())
  let weight = (line_width * 12700).round().to_int64()
  let name = if text is Some(_) { "Text box" } else { "Shape" }
  let nonvisual = if text is Some(_) {
    "<wps:cNvSpPr txBox=\"1\"/>"
  } else {
    "<wps:cNvSpPr/>"
  }
  let body = if text is Some(_) {
    "<wps:bodyPr><a:noAutofit/></wps:bodyPr>"
  } else {
    "<wps:bodyPr/>"
  }
  let markup = "<od:drawing xmlns:od=\"\{word_uri}\" xmlns:wp=\"\{picture_inline_uri}\" xmlns:a=\"\{picture_drawing_uri}\" xmlns:wps=\"\{word_shape_uri}\"><wp:inline><wp:extent cx=\"\{cx}\" cy=\"\{cy}\"/><wp:docPr id=\"\{identity}\" name=\"\{name} \{identity}\"/><a:graphic><a:graphicData uri=\"\{word_shape_uri}\"><wps:wsp>\{nonvisual}<wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\{cx}\" cy=\"\{cy}\"/></a:xfrm><a:prstGeom prst=\"\{preset}\"><a:avLst/></a:prstGeom>\{paint}<a:ln w=\"\{weight}\">\{line}</a:ln></wps:spPr>\{content}\{body}</wps:wsp></a:graphicData></a:graphic></wp:inline></od:drawing>"
  let prepared = self.prepare_drawing_insertion(markup)
  let prepared = if text is Some(value) {
    let tree = WordTree::new(prepared.document)
    let drawing = tree.order
      .iter()
      .find_first(id => {
        tree.nodes[id].uri == word_uri &&
        tree.nodes[id].name == "drawing" &&
        tree.nodes[tree.anchor_child(tree.drawing_data(id).0.id, "docPr")].attribute(
          "id",
        ) ==
        Some(identity.to_string())
      })
      .unwrap()
    ignore(self.drawing_frame(tree, drawing))
    let data = tree.drawing_data(drawing).1
    let shape = tree.children[data.id][0]
    let box = tree.drawing_child(shape, "txbx", uri=word_shape_uri).unwrap()
    let content = tree.drawing_child(box, "txbxContent", uri=word_uri).unwrap()
    let paragraphs = tree.children[content]
    let focus : Position = {
      paragraph: paragraphs.last().unwrap(),
      offset: value.split("\n").last().unwrap().length(),
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    }
    {
      ..prepared,
      edit: {
        ..prepared.edit,
        after: Some({ anchor: focus, focus, }),
        paragraphs: prepared.edit.paragraphs + paragraphs,
      },
    }
  } else {
    prepared
  }
  self.check_picture_layout(prepared.document, probe, profile, images)
  self.commit_edit(prepared.edit, prepared.document)
  self.edit_result(prepared.edit.paragraphs)
}

///|
fn text_box_markup(text : String, limit : Int) -> String raise @failure.Failure {
  guard text.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Text box initial text exceeds budget")
  }
  guard valid_inline_input(text) && !has_region_break(text) else {
    @failure.reject("invalid-operation", "Invalid text box initial text")
  }
  let parts : Array[StringView] = text.split("\n").collect()
  guard parts.length() <= 256 && parts.all(part => part.length() <= 4096) else {
    @failure.reject("limit-exceeded", "Text box initial text exceeds budget")
  }
  let output = StringBuilder()
  output.write_string("<wps:txbx><od:txbxContent>")
  let mut units = "<wps:txbx><od:txbxContent></od:txbxContent></wps:txbx>".length()
  for part in parts {
    let markup = "<od:p><od:r>" +
      inline_markup(part.to_owned(), limit) +
      "</od:r></od:p>"
    guard markup.length() <= limit - units else {
      @failure.reject("limit-exceeded", "Text box source exceeds budget")
    }
    output.write_string(markup)
    units += markup.length()
  }
  output.write_string("</od:txbxContent></wps:txbx>")
  output.to_string()
}
