///|
fn Session::markup_text_box(
  self : Session,
  tree : WordTree,
  styles : Styles,
  id : Int,
  frame : @layout.DrawingFrame,
  shape : @layout.BasicShape,
  text : @layout.DrawingTextBox,
  label : String,
  link : String?,
  output : MarkupOutput,
) -> String raise @failure.Failure {
  let nodes : Map[Int, Bool] = Map([])
  for paragraph in text.paragraphs() {
    for child in tree.descendants(paragraph.id) {
      tree.check_text_box_clipboard_metadata(child)
      nodes[child] = true
    }
  }
  tree.check_shape_metadata(id, nodes)
  let settings = text.properties()
  let area = frame.text_box_rect(shape, text)
  let inner = {
    ..output,
    builder: StringBuilder(),
    units: 0,
    limit: output.limit - output.units,
    markdown: false,
    text_box: true,
    wrap: settings.wrap,
    drawing_link: link,
  }
  self.markup_paragraphs(tree, styles, text.paragraphs(), inner, html=true)
  let svg = shape_markup_svg(frame, shape, label, decoration=true)
  let background = if link is Some(attributes) {
    "<a" +
    attributes +
    " aria-label=\"" +
    property_attribute(label) +
    "\" style=\"position:absolute;inset:0\">" +
    svg +
    "</a>"
  } else {
    svg
  }
  let top = if settings.anchor == "t" { "0" } else { "auto" }
  let bottom = if settings.anchor == "b" { "0" } else { "auto" }
  "<span role=\"group\" aria-label=\"" +
  property_attribute(label) +
  "\" style=\"display:inline-block;position:relative;vertical-align:middle;width:\{frame.width}pt;height:\{frame.height}pt\">" +
  background +
  "<span style=\"position:absolute;display:flex;flex-direction:column;left:\{area.x}pt;top:\{area.y}pt;width:\{area.width}pt;height:\{area.height}pt;overflow:" +
  (if settings.clip { "hidden" } else { "visible" }) +
  ";" +
  (if link is Some(_) { "pointer-events:none;" } else { "" }) +
  "\"><span style=\"display:block;flex-shrink:0;width:100%;margin-top:\{top};margin-bottom:\{bottom}\">" +
  inner.builder.to_string() +
  "</span></span></span>"
}
