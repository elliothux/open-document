///|
fn analysis_reference(
  document : @xml.Document,
  uri : String,
  container : String,
  child : String,
  id : String,
  payload_uri~ : String = slicer_uri,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(document)
  let root = document.nodes()[0]
  let list = tree.one(root.id, "extLst")
  let extension = list.bind(list => {
    tree
    .all(list.id, "ext")
    .iter()
    .find_first(node => {
      node
      .attribute("uri")
      .map(value => value.to_upper() == uri)
      .unwrap_or(false)
    })
  })
  let entry = "<odS:\{child} xmlns:odS=\"\{payload_uri}\" xmlns:r=\"\{relationship_uri[:relationship_uri.length()-1]}\" r:id=\"\{escaped_attribute(id)}\"/>"
  if extension is Some(ext) {
    let parent = if payload_uri == timeline_uri {
      tree.timeline_node(ext.id, container)
    } else {
      tree.slicer_node(ext.id, container)
    }
    guard tree.children
      .get(parent.id)
      .unwrap_or([])
      .filter(node => node.uri == payload_uri && node.name == child)
      .length() <
      64 else {
      @failure.reject("limit-exceeded", "Slicer references exceed budget")
    }
    return document.edit_source([insertion(parent, entry)])
  }
  let markup = "<odX:ext xmlns:odX=\"\{spreadsheet_uri}\" uri=\"\{uri}\"><odS:\{container} xmlns:odS=\"\{payload_uri}\">\{entry}</odS:\{container}></odX:ext>"
  match list {
    Some(list) => document.edit_source([insertion(list, markup)])
    None =>
      document.edit_source([
        insertion(
          root,
          "<odX:extLst xmlns:odX=\"\{spreadsheet_uri}\">\{markup}</odX:extLst>",
        ),
      ])
  }
}

///|
fn Session::slicer_creation_identity(
  self : Session,
  name : String,
) -> String raise @failure.Failure {
  let result : Map[String, Bool] = Map([])
  let uids : Map[String, Bool] = Map([])
  for sheet in self.sheets {
    for
      path in self.slicer_parts(
        sheet.id,
        sheet.document,
        slicer_list_extension,
        "slicerList",
        "slicer",
        "slicer",
      ) {
      let tree = Tree::new(self.part_xml(path))
      for node in tree.slicer_children(tree.document.nodes()[0].id, "slicer") {
        let name = slicer_text(node, "name")
        guard !result.contains(name) && result.length() < 16384 else {
          @failure.reject(
            "protected-content", "Slicer names are duplicated or exceed budget",
          )
        }
        result[name] = true
        if node.attribute(
            "uid",
            uri="http://schemas.microsoft.com/office/spreadsheetml/2016/revision10",
          )
          is Some(uid) {
          guard !uids.contains(uid.to_upper()) else {
            @failure.reject("protected-content", "Duplicate slicer view UID")
          }
          uids[uid.to_upper()] = true
        }
      }
    }
  }
  guard !result.contains(name) else {
    @failure.reject("invalid-name", "Slicer name is already used")
  }
  slicer_creation_uid(uids, result.length(), "00000001")
}

///|
fn slicer_creation_uid(
  uids : Map[String, Bool],
  count : Int,
  kind : String,
) -> String raise @failure.Failure {
  if uids.is_empty() {
    return ""
  }
  guard uids.length() == count else {
    @failure.reject(
      "protected-content", "Mixed slicer UID profile requires support",
    )
  }
  let value = for index in 1..<=16384 {
    let hex = index.to_string(radix=16).to_upper()
    let value = "{" +
      kind +
      "-0000-4000-8000-" +
      "000000000000"[:12 - hex.length()].to_owned() +
      hex +
      "}"
    if !uids.contains(value) {
      break value
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Slicer UIDs exhausted")
  }
  " xmlns:xr10=\"http://schemas.microsoft.com/office/spreadsheetml/2016/revision10\" xr10:uid=\"\{value}\""
}

///|
fn Session::slicer_sheet_id(
  self : Session,
  sheet : String,
) -> String raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  let node = tree
    .all(tree.one(tree.root("workbook").id, "sheets").unwrap().id, "sheet")
    .iter()
    .find_first(node => {
      let id = node
        .attribute(
          "id",
          uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
        )
        .unwrap_or("")
      self
      .relationships()
      .any(link => {
        link.owner == self.main &&
        link.id == id &&
        !link.external &&
        link.target == sheet
      })
    })
    .unwrap_or_else(() => {
      @failure.reject(
        "protected-content", "Slicer worksheet identity is unavailable",
      )
    })
  node.attribute("sheetId").unwrap()
}

///|
fn slicer_graphic_source(
  id : String,
  name : String,
  caption : String,
  rect : @layout.Border,
) -> String raise @failure.Failure {
  let identity = escaped_attribute(name)
  let name = escaped_attribute(encoded_text(name))
  let caption = @xml.escape_text(caption)
  let graphic = "<odXdr:graphicFrame><odXdr:nvGraphicFramePr><odXdr:cNvPr id=\"\{id}\" name=\"\{identity}\"/><odXdr:cNvGraphicFramePr/></odXdr:nvGraphicFramePr>\{chart_transform(rect)}<odA:graphic><odA:graphicData uri=\"\{slicer_drawing_uri}\"><odS:slicer xmlns:odS=\"\{slicer_drawing_uri}\" name=\"\{name}\"/></odA:graphicData></odA:graphic></odXdr:graphicFrame>"
  let fallback = "<odXdr:sp><odXdr:nvSpPr><odXdr:cNvPr id=\"0\" name=\"\"/><odXdr:cNvSpPr/></odXdr:nvSpPr><odXdr:spPr>\{picture_transform(rect)}<odA:prstGeom prst=\"rect\"><odA:avLst/></odA:prstGeom></odXdr:spPr><odXdr:txBody><odA:bodyPr/><odA:lstStyle/><odA:p><odA:r><odA:t>\{caption}: This slicer requires Office 2010 or later.</odA:t></odA:r></odA:p></odXdr:txBody></odXdr:sp>"
  "<mc:AlternateContent xmlns:mc=\"\{drawing_compatibility_uri}\" xmlns:odA=\"\{picture_drawing_uri}\"><mc:Choice xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\" Requires=\"a14\">\{graphic}</mc:Choice><mc:Fallback>\{fallback}</mc:Fallback></mc:AlternateContent>"
}
