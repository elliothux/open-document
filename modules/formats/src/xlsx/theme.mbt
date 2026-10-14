///|
fn read_theme(
  opc : @opc.Package,
  main : String,
) -> Array[String] raise @failure.Failure {
  let colors = [
    "ffffff", "000000", "eeece1", "1f497d", "4f81bd", "c0504d", "9bbb59", "8064a2",
    "4bacc6", "f79646", "0000ff", "800080",
  ]
  let relation = opc
    .relationships()
    .iter()
    .find_first(rel => {
      rel.owner == main && rel.kind == relationship_uri + "theme"
    })
  if relation is Some(rel) {
    guard !rel.external else {
      @failure.reject("malformed-xlsx", "External theme relationship")
    }
    let document = opc.xml(rel.target)
    let nodes = document.nodes()
    if nodes
      .iter()
      .find_first(node => {
        node.name == "clrScheme" &&
        node.uri == "http://schemas.openxmlformats.org/drawingml/2006/main"
      })
      is Some(scheme) {
      for
        index, name in [
          "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4",
          "accent5", "accent6", "hlink", "folHlink",
        ] {
        if nodes
          .iter()
          .find_first(node => node.parent == scheme.id && node.name == name)
          is Some(container) &&
          nodes.iter().find_first(node => node.parent == container.id)
          is Some(color) {
          if color.name == "srgbClr" {
            colors[index] = color_hex(color.attribute("val").unwrap_or(""))
          } else if color.name == "sysClr" {
            colors[index] = color_hex(color.attribute("lastClr").unwrap_or(""))
          } else {
            @failure.reject("unsupported-xlsx", "Unsupported theme color")
          }
        }
      }
    }
  }
  colors
}
