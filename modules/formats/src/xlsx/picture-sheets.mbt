///|
fn Session::check_sheet_pictures(
  self : Session,
  sheet : Sheet,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  charts~ : Bool = false,
) -> Unit raise @failure.Failure {
  let pictures = self
    .sheet_objects(sheet, self.resolved_dimensions(sheet, probe, profile))
    .filter(object => {
      object.media is Some(_) || (charts && object.chart is Some(_))
    })
  guard self.picture_drawing(sheet) is Some((part, tree)) else { return }
  guard self
    .relationships()
    .all(link => {
      link.owner != part ||
      (
        !link.external &&
        (
          link.kind == relationship_uri + "image" ||
          (charts && link.kind == relationship_uri + "chart")
        )
      )
    }) &&
    tree.document
    .nodes()
    .all(node => {
      node.attributes.all(attribute => {
        attribute.uri !=
        relationship_uri[:relationship_uri.length() - 1].to_owned() ||
        (
          node.uri == picture_drawing_uri &&
          node.name == "blip" &&
          attribute.name == "embed"
        ) ||
        (
          charts &&
          node.uri == chart_uri &&
          node.name == "chart" &&
          attribute.name == "id"
        )
      })
    }) else {
    @failure.reject(
      "protected-content", "Worksheet drawing references require sheet migration support",
    )
  }
  for picture in pictures {
    let (nv_name, props_name, locks_name) = if picture.chart is Some(_) {
      ("nvGraphicFramePr", "cNvGraphicFramePr", "graphicFrameLocks")
    } else {
      ("nvPicPr", "cNvPicPr", "picLocks")
    }
    let nv = tree.picture_node(picture.source.id, nv_name)
    let identity = tree.picture_node(nv.id, "cNvPr")
    let props = tree.picture_node(nv.id, props_name)
    guard tree.children
      .get(nv.id)
      .unwrap_or([])
      .all(node => {
        node.uri == picture_uri && ["cNvPr", props_name].contains(node.name)
      }) &&
      tree.children.get(identity.id).unwrap_or([]).is_empty() &&
      tree.children
      .get(props.id)
      .unwrap_or([])
      .all(node => {
        node.uri == picture_drawing_uri &&
        node.name == locks_name &&
        tree.children.get(node.id).unwrap_or([]).is_empty()
      }) else {
      @failure.reject(
        "protected-content", "Worksheet picture metadata requires sheet migration support",
      )
    }
    if picture.chart is Some(_) {
      guard identity.attributes.all(a => {
        a.uri.is_empty() &&
        ["id", "name", "descr", "title", "hidden"].contains(a.name)
      }) else {
        @failure.reject(
          "protected-content", "Chart identity extensions require copying support",
        )
      }
    }
  }
}

///|
fn Session::copy_sheet_pictures(
  self : Session,
  source : Sheet,
  number : Int,
  created : Map[String, @xml.Document],
  remapped : Map[String, String],
  types : StringBuilder,
) -> Unit raise @failure.Failure {
  guard self.picture_drawing(source) is Some((original_part, tree)) else {
    return
  }
  let directory = self.main
    .split("/")
    .map(segment => segment.to_owned())
    .to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let part = for index in 0..<=self.budget.entries {
    let part = prefix + "drawings/odSheet\{number}-\{index}.xml"
    if !self.opc.names.contains(part.to_lower()) &&
      !self.parts.contains(part) &&
      !created.contains(part) &&
      !self.opc.names.contains(workbook_relations(part).to_lower()) &&
      !self.parts.contains(workbook_relations(part)) {
      break part
    }
  } nobreak {
    @failure.reject(
      "limit-exceeded", "Copied worksheet drawing identities exhausted",
    )
  }
  guard tree.document.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Copied worksheet drawing exceeds history budget",
    )
  }
  created[part] = @xml.Document::parse(
    tree.document.bytes(),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  remapped[original_part] = part
  if self.copy_sheet_relations(original_part, part, remapped) is Some(document) {
    created[workbook_relations(part)] = document
  }
  types.write_string(
    "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>",
  )
}
