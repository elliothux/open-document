///|
let picture_uri = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"

///|
let picture_drawing_uri = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
priv struct SheetObject {
  id : String
  name : String
  description : String
  part : String
  media : String?
  shape : SheetShape?
  chart : (String, @chart.WorksheetChart)?
  tree : Tree
  frame : @xml.Node
  source : @xml.Node
  rect : @layout.Border
  anchor : String
  crop : Array[Double]
  printable : Bool
  visible : Bool
}

///|
fn Tree::picture_child(
  self : Tree,
  parent : Int,
  name : String,
  uri~ : String = picture_uri,
) -> @xml.Node? raise @failure.Failure {
  let children = self.children
    .get(parent)
    .unwrap_or([])
    .filter(node => node.uri == uri && node.name == name)
  guard children.length() <= 1 else {
    @failure.reject("unsupported-drawing", "Duplicate picture " + name)
  }
  children.get(0)
}

///|
fn Tree::picture_node(
  self : Tree,
  parent : Int,
  name : String,
  uri~ : String = picture_uri,
) -> @xml.Node raise @failure.Failure {
  self
  .picture_child(parent, name, uri~)
  .unwrap_or_else(() => {
    @failure.reject("unsupported-drawing", "Missing picture " + name)
  })
}

///|
fn picture_integer(
  value : String,
  maximum~ : Double = 1000000000000,
) -> Double raise @failure.Failure {
  let result = number(value)
  guard result >= 0 && result <= maximum && result == result.floor() else {
    @failure.reject("unsupported-drawing", "Invalid picture anchor integer")
  }
  result
}

///|
fn Tree::picture_mark(
  self : Tree,
  parent : Int,
  name : String,
  dimensions : Dimensions,
) -> (Double, Double) raise @failure.Failure {
  let mark = self.picture_node(parent, name)
  fn read(name : String, max : Double) -> Double raise @failure.Failure {
    let node = self.picture_node(mark.id, name)
    guard node.attributes.is_empty() &&
      self.children.get(node.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-drawing", "Unknown picture anchor coordinate",
      )
    }
    picture_integer(node.text, maximum=max)
  }
  let col = read("col", 16383).to_int() + 1
  let row = read("row", 1048575).to_int() + 1
  let x = read("colOff", 1000000000000) / 12700
  let y = read("rowOff", 1000000000000) / 12700
  guard mark.attributes.is_empty() &&
    self.children
    .get(mark.id)
    .unwrap_or([])
    .all(node => {
      node.uri == picture_uri &&
      ["col", "colOff", "row", "rowOff"].contains(node.name)
    }) else {
    @failure.reject("unsupported-drawing", "Unknown picture anchor marker")
  }
  (dimensions.columns.position(col) + x, dimensions.rows.position(row) + y)
}

///|
fn Session::picture_drawing(
  self : Session,
  sheet : Sheet,
) -> (String, Tree)? raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  guard tree.one(tree.root("worksheet").id, "drawing") is Some(node) else {
    return None
  }
  let id = node
    .attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    )
    .unwrap_or("")
  let rels = self
    .relationships()
    .filter(rel => rel.owner == sheet.id && rel.id == id)
  guard rels is [rel] &&
    !rel.external &&
    rel.kind == relationship_uri + "drawing" else {
    @failure.reject(
      "unsupported-drawing", "Invalid worksheet drawing relationship",
    )
  }
  guard self
    .relationships()
    .filter(link => {
      !link.external &&
      link.kind == relationship_uri + "drawing" &&
      link.target == rel.target
    })
    .length() ==
    1 else {
    @failure.reject(
      "unsupported-drawing", "Shared worksheet drawing parts require independent ownership",
    )
  }
  Some((rel.target, Tree::new(self.part_xml(rel.target))))
}

///|
fn Session::picture_bytes(
  self : Session,
  path : String,
) -> Bytes raise @failure.Failure {
  self.media.get(path).unwrap_or_else(() => self.opc.read(path))
}

///|
fn Session::sheet_objects(
  self : Session,
  sheet : Sheet,
  dimensions : Dimensions,
) -> Array[SheetObject] raise @failure.Failure {
  guard self.picture_drawing(sheet) is Some((part, tree)) else { return [] }
  let root = tree.document.nodes()[0]
  guard root.uri == picture_uri &&
    root.name == "wsDr" &&
    root.attributes.is_empty() else {
    @failure.reject("unsupported-drawing", "Expected a worksheet drawing")
  }
  let anchors = tree.children.get(root.id).unwrap_or([])
  guard anchors.length() <= 256 else {
    @failure.reject("limit-exceeded", "Worksheet pictures exceed256 entries")
  }
  let relationships = self.relationships()
  let ids : Map[String, Unit] = Map([])
  let result : Array[SheetObject] = []
  let mut source_bytes = 0
  for frame in anchors {
    guard frame.uri == picture_uri &&
      ["absoluteAnchor", "oneCellAnchor", "twoCellAnchor"].contains(frame.name) &&
      frame.attributes.all(a => {
        a.uri.is_empty() && a.name == "editAs" && frame.name == "twoCellAnchor"
      }) else {
      @failure.reject("unsupported-drawing", "Unknown worksheet drawing anchor")
    }
    let coordinates = if frame.name == "absoluteAnchor" {
      ["pos", "ext"]
    } else if frame.name == "oneCellAnchor" {
      ["from", "ext"]
    } else {
      ["from", "to"]
    }
    guard tree.children
      .get(frame.id)
      .unwrap_or([])
      .all(node => {
        node.uri == picture_uri &&
        (coordinates + ["pic", "sp", "graphicFrame", "clientData"]).contains(
          node.name,
        )
      }) else {
      @failure.reject(
        "unsupported-drawing", "Only ordinary worksheet pictures are supported",
      )
    }
    if tree.picture_child(frame.id, "graphicFrame") is Some(source) {
      guard tree.picture_child(frame.id, "pic") is None &&
        tree.picture_child(frame.id, "sp") is None else {
        @failure.reject(
          "unsupported-drawing", "Drawing anchor has multiple objects",
        )
      }
      let object = self.read_sheet_chart(
        sheet, part, tree, frame, source, dimensions,
      )
      guard !ids.contains(object.id) else {
        @failure.reject("unsupported-drawing", "Duplicate drawing identity")
      }
      ids[object.id] = ()
      result.push(object)
      continue
    }
    if tree.picture_child(frame.id, "sp") is Some(source) {
      guard tree.picture_child(frame.id, "pic") is None else {
        @failure.reject(
          "unsupported-drawing", "Drawing anchor has multiple objects",
        )
      }
      let shape = self.read_sheet_shape(part, tree, frame, source, dimensions)
      guard !ids.contains(shape.id) else {
        @failure.reject("unsupported-drawing", "Duplicate drawing identity")
      }
      ids[shape.id] = ()
      result.push(shape)
      continue
    }
    let source = tree.picture_node(frame.id, "pic")
    guard tree.children
      .get(source.id)
      .unwrap_or([])
      .all(node => {
        node.uri == picture_uri &&
        ["nvPicPr", "blipFill", "spPr"].contains(node.name)
      }) else {
      @failure.reject("unsupported-drawing", "Unknown picture content")
    }
    let client = tree.picture_child(frame.id, "clientData")
    if client is Some(node) {
      guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
        node.attributes.all(a => {
          a.uri.is_empty() &&
          ["fPrintsWithSheet", "fLocksWithSheet"].contains(a.name) &&
          ["0", "1", "true", "false"].contains(a.value)
        }) else {
        @failure.reject(
          "unsupported-drawing", "Unknown worksheet picture client data",
        )
      }
    }
    let nv = tree.picture_node(source.id, "nvPicPr")
    let identity = tree.picture_node(nv.id, "cNvPr")
    let id = identity.attribute("id").unwrap_or("")
    guard natural(id, 2147483647) > 0 && !ids.contains(id) else {
      @failure.reject(
        "unsupported-drawing", "Invalid or duplicate picture identity",
      )
    }
    ids[id] = ()
    let fill = tree.picture_node(source.id, "blipFill")
    guard tree.children
      .get(fill.id)
      .unwrap_or([])
      .all(node => {
        node.uri == picture_drawing_uri &&
        ["blip", "srcRect", "stretch"].contains(node.name)
      }) else {
      @failure.reject("unsupported-drawing", "Unknown worksheet image fill")
    }
    let blip = tree.picture_node(fill.id, "blip", uri=picture_drawing_uri)
    let embed = blip
      .attribute(
        "embed",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      .unwrap_or("")
    guard blip.attributes.all(a => {
        a.uri == relationship_uri[:relationship_uri.length() - 1].to_owned() &&
        a.name == "embed"
      }) &&
      tree.children.get(blip.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-drawing", "Linked or transformed image resources are protected",
      )
    }
    let links = relationships.filter(rel => rel.owner == part && rel.id == embed)
    guard links is [link] &&
      !link.external &&
      link.kind == relationship_uri + "image" else {
      @failure.reject(
        "unsupported-drawing", "Picture requires an internal image relationship",
      )
    }
    let bytes = self.picture_bytes(link.target)
    source_bytes += bytes.length()
    guard source_bytes <= 16777216 else {
      @failure.reject("limit-exceeded", "Worksheet image sources exceed16MiB")
    }
    ignore(@image.type_info(bytes))
    let props = tree.picture_node(source.id, "spPr")
    let transform = tree.picture_child(
      props.id,
      "xfrm",
      uri=picture_drawing_uri,
    )
    guard transform.map(node => node.attributes.is_empty()).unwrap_or(true) &&
      tree.children
      .get(props.id)
      .unwrap_or([])
      .all(node => {
        node.uri == picture_drawing_uri &&
        ["xfrm", "prstGeom"].contains(node.name)
      }) else {
      @failure.reject(
        "unsupported-drawing", "Rotated or styled worksheet pictures require drawing support",
      )
    }
    if transform is Some(node) {
      guard tree.children
        .get(node.id)
        .unwrap_or([])
        .all(child => {
          child.uri == picture_drawing_uri &&
          ["off", "ext"].contains(child.name)
        }) else {
        @failure.reject(
          "unsupported-drawing", "Unknown worksheet picture transform",
        )
      }
    }
    if tree.picture_child(props.id, "prstGeom", uri=picture_drawing_uri)
      is Some(shape) {
      guard shape.attribute("prst") == Some("rect") else {
        @failure.reject(
          "unsupported-drawing", "Only rectangular pictures are supported",
        )
      }
    }
    guard tree.picture_child(fill.id, "tile", uri=picture_drawing_uri) is None &&
      tree.picture_child(fill.id, "stretch", uri=picture_drawing_uri) is Some(_) else {
      @failure.reject(
        "unsupported-drawing", "Tiled pictures require drawing support",
      )
    }
    let stretch = tree.picture_node(fill.id, "stretch", uri=picture_drawing_uri)
    let fill_rect = tree.picture_node(
      stretch.id,
      "fillRect",
      uri=picture_drawing_uri,
    )
    guard fill_rect.attributes.is_empty() &&
      tree.children.get(fill_rect.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-drawing", "Picture fill insets require drawing support",
      )
    }
    let crop = if tree.picture_child(
        fill.id,
        "srcRect",
        uri=picture_drawing_uri,
      )
      is Some(node) {
      ["l", "t", "r", "b"].map(name => {
        number(node.attribute(name).unwrap_or("0")) / 100000
      })
    } else {
      [0.0, 0.0, 0.0, 0.0]
    }
    guard crop.all(v => v >= 0 && v < 1) &&
      crop[0] + crop[2] < 1 &&
      crop[1] + crop[3] < 1 else {
      @failure.reject("unsupported-drawing", "Invalid worksheet image crop")
    }
    let (anchor, rect) = tree.drawing_rect(frame, dimensions)
    guard rect.width / (1 - crop[0] - crop[2]) <= 1000000000 &&
      rect.height / (1 - crop[1] - crop[3]) <= 1000000000 else {
      @failure.reject(
        "limit-exceeded", "Expanded worksheet picture exceeds drawing bounds",
      )
    }
    result.push({
      id,
      name: identity.attribute("name").unwrap_or("Picture"),
      description: identity.attribute("descr").unwrap_or(""),
      part,
      media: Some(link.target),
      shape: None,
      chart: None,
      tree,
      source,
      frame,
      anchor,
      rect,
      crop,
      printable: client
      .map(node => flag(node, "fPrintsWithSheet", fallback=true))
      .unwrap_or(true),
      visible: !flag(identity, "hidden"),
    })
  }
  result
}

///|
fn Session::sheet_pictures(
  self : Session,
  sheet : Sheet,
  dimensions : Dimensions,
) -> Array[SheetObject] raise @failure.Failure {
  self
  .sheet_objects(sheet, dimensions)
  .filter(object => object.media is Some(_))
}
