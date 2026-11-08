///|
fn read_theme(
  opc : @opc.Package,
  main : String,
  relationship : String,
) -> Array[String] raise @failure.Failure {
  let colors = [
    "ffffff", "000000", "eeece1", "1f497d", "4f81bd", "c0504d", "9bbb59", "8064a2",
    "4bacc6", "f79646", "0000ff", "800080",
  ]
  let relation = opc
    .relationships()
    .iter()
    .find_first(rel => rel.owner == main && rel.kind == relationship + "theme")
  if relation is Some(rel) {
    guard !rel.external else {
      @failure.reject("malformed-xlsx", "External theme relationship")
    }
    let document = opc.xml(rel.target)
    let nodes = document.nodes()
    let drawing = if relationship == strict_relationship_uri {
      "http://purl.oclc.org/ooxml/drawingml/main"
    } else {
      picture_drawing_uri
    }
    if nodes
      .iter()
      .find_first(node => node.name == "clrScheme" && node.uri == drawing)
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

///|
fn Session::chart_theme_line_width(
  self : Session,
) -> Double raise @failure.Failure {
  let relation = self
    .relationships()
    .iter()
    .find_first(rel => {
      rel.owner == self.main && rel.kind == relationship_uri + "theme"
    })
  guard relation is Some(relation) else { return 0.75 }
  let tree = Tree::new(self.part_xml(relation.target))
  let root = tree.nodes[0]
  guard root.uri == picture_drawing_uri && root.name == "theme" else {
    @failure.reject("unsupported-chart", "Invalid native chart theme")
  }
  let elements = tree.picture_node(
    root.id,
    "themeElements",
    uri=picture_drawing_uri,
  )
  let format = tree.picture_node(
    elements.id,
    "fmtScheme",
    uri=picture_drawing_uri,
  )
  let styles = tree.picture_node(
    format.id,
    "lnStyleLst",
    uri=picture_drawing_uri,
  )
  let lines = tree.children.get(styles.id).unwrap_or([])
  guard lines.get(0) is Some(line) &&
    line.uri == picture_drawing_uri &&
    line.name == "ln" else {
    @failure.reject("unsupported-chart", "Missing native chart theme line")
  }
  guard line.attributes.all(a => {
      a.uri.is_empty() && ["w", "cap", "cmpd", "algn"].contains(a.name)
    }) &&
    line.attribute("cap").unwrap_or("flat") == "flat" &&
    line.attribute("cmpd").unwrap_or("sng") == "sng" &&
    line.attribute("algn").unwrap_or("ctr") == "ctr" else {
    @failure.reject(
      "unsupported-chart", "Native chart theme line requires support",
    )
  }
  ignore(tree.shape_children(line, ["solidFill", "prstDash", "miter"]))
  if tree.picture_child(line.id, "prstDash", uri=picture_drawing_uri)
    is Some(dash) {
    ignore(tree.shape_children(dash, []))
    guard dash.attributes.all(a => a.uri.is_empty() && a.name == "val") &&
      dash.attribute("val") == Some("solid") else {
      @failure.reject(
        "unsupported-chart", "Dashed native chart theme frame requires support",
      )
    }
  }
  if tree.picture_child(line.id, "miter", uri=picture_drawing_uri)
    is Some(miter) {
    ignore(tree.shape_children(miter, []))
    guard miter.attributes.all(a => a.uri.is_empty() && a.name == "lim") &&
      miter.attribute("lim").unwrap_or("800000") == "800000" else {
      @failure.reject(
        "unsupported-chart", "Native chart theme join requires support",
      )
    }
  }
  let width = picture_integer(
      line.attribute("w").unwrap_or(""),
      maximum=12700000,
    ) /
    12700
  guard width > 0 else {
    @failure.reject(
      "unsupported-chart", "Invalid native chart theme line width",
    )
  }
  width
}
