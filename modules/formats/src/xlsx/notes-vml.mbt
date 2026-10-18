///|
let note_vml_uri = "urn:schemas-microsoft-com:vml"

///|
let note_office_uri = "urn:schemas-microsoft-com:office:office"

///|
let note_excel_uri = "urn:schemas-microsoft-com:office:excel"

///|
fn vml_child(
  tree : Tree,
  parent : Int,
  uri : String,
  name : String,
) -> @xml.Node? raise @failure.Failure {
  let nodes = tree.children
    .get(parent)
    .unwrap_or([])
    .filter(n => n.uri == uri && n.name == name)
  guard nodes.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate VML note element")
  }
  nodes.get(0)
}

///|
fn vml_note_shapes(
  tree : Tree,
) -> Map[String, @xml.Node] raise @failure.Failure {
  let root = tree.document.nodes()[0]
  guard root.uri.is_empty() &&
    root.name == "xml" &&
    root.attributes.is_empty() &&
    root.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown VML root is protected")
  }
  let shapes : Map[String, @xml.Node] = Map([])
  let ids : Map[String, Bool] = Map([])
  let types : Map[String, Bool] = Map([])
  for node in tree.document.nodes() {
    if node.uri == note_vml_uri &&
      node.name == "shapetype" &&
      node.attribute("spt", uri=note_office_uri) == Some("202") {
      types[node.attribute("id").unwrap_or("")] = true
    }
  }
  guard !types.is_empty() else {
    @failure.reject(
      "protected-content", "VML notes require a known note shape type",
    )
  }
  for node in tree.document.nodes() {
    if node.parent < 0 {
      continue
    }
    let parent = tree.nodes[node.parent]
    let (plain, office, vml, children) : (
      Array[String],
      Array[String],
      Array[String],
      Array[(String, String)],
    ) = match (node.uri, node.name) {
      (uri, "shapelayout") if uri == note_office_uri =>
        ([], [], ["ext"], [(note_office_uri, "idmap")])
      (uri, "idmap") if uri == note_office_uri => (["data"], [], ["ext"], [])
      (uri, "shapetype") if uri == note_vml_uri =>
        (
          ["id", "coordsize", "path"],
          ["spt"],
          [],
          [(note_vml_uri, "stroke"), (note_vml_uri, "path")],
        )
      (uri, "shape") if uri == note_vml_uri =>
        (
          ["id", "type", "style", "fillcolor", "strokecolor", "strokeweight"],
          ["insetmode"],
          [],
          [
            (note_vml_uri, "fill"),
            (note_vml_uri, "shadow"),
            (note_vml_uri, "path"),
            (note_vml_uri, "textbox"),
            (note_excel_uri, "ClientData"),
          ],
        )
      (uri, "stroke") if uri == note_vml_uri => (["joinstyle"], [], [], [])
      (uri, "path") if uri == note_vml_uri =>
        (
          ["gradientshapeok", "shadowok", "strokeok", "fillok"],
          ["connecttype", "extrusionok"],
          [],
          [],
        )
      (uri, "fill") if uri == note_vml_uri =>
        (["color2", "color", "type"], [], [], [])
      (uri, "shadow") if uri == note_vml_uri =>
        (["on", "color", "obscured"], [], [], [])
      (uri, "textbox") if uri == note_vml_uri =>
        (["style", "inset"], [], [], [("", "div")])
      ("", "div") => (["style"], [], [], [])
      (uri, "ClientData") if uri == note_excel_uri =>
        (
          ["ObjectType"],
          [],
          [],
          [
            "MoveWithCells", "SizeWithCells", "Anchor", "AutoFill", "Row", "Column",
            "Visible",
          ].map(name => (note_excel_uri, name)),
        )
      (uri, name) if uri == note_excel_uri &&
        [
          "MoveWithCells", "SizeWithCells", "Anchor", "AutoFill", "Row", "Column",
          "Visible",
        ].contains(name) => ([], [], [], [])
      _ =>
        @failure.reject(
          "protected-content", "VML controls and unknown note shapes are protected",
        )
    }
    guard node.attributes.all(a => {
        (a.uri.is_empty() && plain.contains(a.name)) ||
        (a.uri == note_office_uri && office.contains(a.name)) ||
        (a.uri == note_vml_uri && vml.contains(a.name))
      }) &&
      tree.children
      .get(node.id)
      .unwrap_or([])
      .all(n => children.contains((n.uri, n.name))) &&
      (node.uri == note_excel_uri || node.text.trim().is_empty()) else {
      @failure.reject(
        "protected-content", "Unknown VML note source is protected",
      )
    }
    if parent.id == root.id {
      guard (node.uri == note_office_uri && node.name == "shapelayout") ||
        (node.uri == note_vml_uri && ["shapetype", "shape"].contains(node.name)) else {
        @failure.reject("protected-content", "Unknown VML root child")
      }
    }
    if node.uri == note_vml_uri && ["shape", "shapetype"].contains(node.name) {
      let id = node.attribute("id").unwrap_or("").trim().to_owned()
      guard !id.is_empty() && id.length() <= 255 && !ids.contains(id) else {
        @failure.reject("protected-content", "Invalid VML shape identity")
      }
      ids[id] = true
    }
    if node.uri != note_vml_uri || node.name != "shape" {
      continue
    }
    let data = vml_child(tree, node.id, note_excel_uri, "ClientData").unwrap_or_else(() => {
        @failure.reject("protected-content", "VML shape is not a cell note")
      },
    )
    guard data.attribute("ObjectType") == Some("Note") else {
      @failure.reject(
        "protected-content", "VML controls require editing support",
      )
    }
    let row = vml_child(tree, data.id, note_excel_uri, "Row").unwrap_or_else(() => {
      @failure.reject("protected-content", "VML note row is missing")
    })
    let column = vml_child(tree, data.id, note_excel_uri, "Column").unwrap_or_else(() => {
        @failure.reject("protected-content", "VML note column is missing")
      },
    )
    let address : Address = {
      row: natural(row.text.trim().to_owned(), 1048575) + 1,
      column: natural(column.text.trim().to_owned(), 16383) + 1,
    }
    guard !shapes.contains(address.name()) && shapes.length() < 4096 else {
      @failure.reject(
        "protected-content", "Duplicate or excessive VML cell note anchors",
      )
    }
    if vml_child(tree, data.id, note_excel_uri, "Anchor") is Some(anchor) {
      let values = anchor.text.split(",").to_array()
      guard values.length() == 8 else {
        @failure.reject("protected-content", "Invalid VML note anchor")
      }
      for index, value in values {
        ignore(
          natural(
            value.trim().to_owned(),
            [16383, 1023, 1048575, 255, 16383, 1023, 1048575, 255][index],
          ),
        )
      }
    }
    let kind = node.attribute("type").unwrap_or("")
    guard kind.has_prefix("#") && types.contains(kind[1:].to_owned()) else {
      @failure.reject("protected-content", "Unknown VML note shape type")
    }
    shapes[address.name()] = node
  }
  shapes
}

///|
fn Session::read_note_vml(
  self : Session,
  sheet : Sheet,
) -> (String, Tree, Map[String, @xml.Node])? raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let legacy = tree.one(tree.root("worksheet").id, "legacyDrawing")
  let links = self.relationships()
  let owned = links.filter(l => {
    l.owner == sheet.id && l.kind == relationship_uri + "vmlDrawing"
  })
  guard owned.length() <= 1 && (legacy is Some(_)) == !owned.is_empty() else {
    @failure.reject("protected-content", "Ambiguous VML note ownership")
  }
  guard legacy is Some(legacy) && owned.get(0) is Some(link) else {
    return None
  }
  guard legacy.attributes.length() == 1 &&
    legacy.attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    ) ==
    Some(link.id) &&
    legacy.text.trim().is_empty() &&
    tree.children.get(legacy.id).unwrap_or([]).is_empty() &&
    !link.external &&
    links.filter(l => !l.external && l.target == link.target).length() == 1 &&
    !links.any(l => l.owner == link.target) else {
    @failure.reject(
      "protected-content", "Shared external or resource-owning VML is protected",
    )
  }
  let source = Tree::new(self.part_xml(link.target))
  Some((link.target, source, vml_note_shapes(source)))
}

///|
fn note_vml_shape(
  address : Address,
  id : Int,
  shape_type~ : String = "_x0000_t202",
) -> String raise @failure.Failure {
  let column = (address.column - 1).min(16381)
  let row = (address.row - 1).min(1048572)
  "<v:shape xmlns:v=\"\{note_vml_uri}\" xmlns:o=\"\{note_office_uri}\" xmlns:x=\"\{note_excel_uri}\" id=\"_x0000_s\{id}\" type=\"#\{escaped_attribute(shape_type)}\" style=\"position:absolute;width:108pt;height:60pt;visibility:hidden\" fillcolor=\"#ffffe1\" o:insetmode=\"auto\"><v:fill color2=\"#ffffe1\"/><v:shadow on=\"t\" color=\"black\" obscured=\"t\"/><v:path o:connecttype=\"none\"/><v:textbox style=\"mso-direction-alt:auto\"><div style=\"text-align:left\"/></v:textbox><x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>\{column}, 15, \{row}, 2, \{column+2}, 15, \{row+3}, 2</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>\{address.row-1}</x:Row><x:Column>\{address.column-1}</x:Column></x:ClientData></v:shape>"
}

///|
fn note_vml_document(
  addresses : Array[Address],
) -> String raise @failure.Failure {
  let fragments : Array[String] = []
  for index, address in addresses {
    fragments.push(note_vml_shape(address, index + 1025))
  }
  let shapes = fragments.join("")
  "<xml xmlns:v=\"\{note_vml_uri}\" xmlns:o=\"\{note_office_uri}\" xmlns:x=\"\{note_excel_uri}\"><o:shapelayout v:ext=\"edit\"><o:idmap v:ext=\"edit\" data=\"1\"/></o:shapelayout><v:shapetype id=\"_x0000_t202\" coordsize=\"21600,21600\" o:spt=\"202\" path=\"m,l,21600r21600,l21600,xe\"><v:stroke joinstyle=\"miter\"/><v:path gradientshapeok=\"t\" o:connecttype=\"rect\"/></v:shapetype>\{shapes}</xml>"
}

///|
fn moved_note_shape(
  source : SheetNotes,
  note : CellNote,
  address : Address,
  target : Tree,
  ids : Map[String, Bool],
  types : Map[String, String],
) -> (String, Int) raise @failure.Failure {
  let id = for i in 1025..<=21504 {
    if !ids.contains("_x0000_s\{i}") {
      break i
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Moved VML note identities exhausted")
  }
  ids["_x0000_s\{id}"] = true
  guard source.vml is Some((_, tree, shapes)) else {
    let kind = target.document
      .nodes()
      .iter()
      .find_first(node => {
        node.uri == note_vml_uri &&
        node.name == "shapetype" &&
        node.attribute("spt", uri=note_office_uri) == Some("202")
      })
      .unwrap()
      .attribute("id")
      .unwrap()
    return (note_vml_shape(address, id, shape_type=kind), id)
  }
  let shape = shapes[note.address.name()]
  let kind = shape.attribute("type").unwrap()[1:].to_owned()
  let type_xml = StringBuilder()
  let mapped = types
    .get(kind)
    .unwrap_or_else(() => {
      let mapped = for i in 1..<=16384 {
        let value = "odNoteType\{i}"
        if !ids.contains(value) {
          break value
        }
      } nobreak {
        @failure.reject("limit-exceeded", "Moved VML note types exhausted")
      }
      ids[mapped] = true
      types[kind] = mapped
      let node = tree.document
        .nodes()
        .iter()
        .find_first(node => {
          node.uri == note_vml_uri &&
          node.name == "shapetype" &&
          node.attribute("id") == Some(kind)
        })
        .unwrap()
      type_xml.write_string(
        style_markup(
          tree,
          node,
          changes=metadata_changes(node, [("id", mapped)]),
        ),
      )
      mapped
    })
  let changes = metadata_changes(shape, [
    ("id", "_x0000_s\{id}"),
    ("type", "#" + mapped),
  ])
  let data = vml_child(tree, shape.id, note_excel_uri, "ClientData").unwrap()
  for
    (name, value) in [("Row", address.row - 1), ("Column", address.column - 1)] {
    let node = vml_child(tree, data.id, note_excel_uri, name).unwrap()
    changes.append(
      axis_text_change(tree, node, value.to_string()).map(change => {
        ..change,
        node: shape.id,
        offset: node.start - shape.start + change.offset,
      }),
    )
  }
  (type_xml.to_string() + style_markup(tree, shape, changes~), id)
}
