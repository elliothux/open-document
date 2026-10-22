///|
let math_uri = "http://schemas.openxmlformats.org/officeDocument/2006/math"

///|
fn Session::math_font(self : Session) -> String raise @failure.Failure {
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    let fonts = tree.order.filter(id => {
      tree.nodes[id].uri == math_uri && tree.nodes[id].name == "mathFont"
    })
    guard fonts.length() <= 1 else {
      @failure.reject("unsupported-math", "Repeated mathematical font setting")
    }
    if fonts is [font] {
      guard tree.nodes[font].attribute("val", uri=math_uri) is Some(value) &&
        !value.is_empty() &&
        value.length() <= 255 else {
        @failure.reject("unsupported-math", "Invalid mathematical font setting")
      }
      return value
    }
  }
  "Cambria Math"
}
