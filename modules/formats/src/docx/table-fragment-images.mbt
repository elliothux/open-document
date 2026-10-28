///|
fn WordTree::check_fragment_picture(
  self : WordTree,
  drawing : Int32,
) -> Unit raise @failure.Failure {
  let root = self.nodes[drawing]
  guard root.uri == word_uri &&
    root.name == "drawing" &&
    root.attributes.is_empty() &&
    self.nodes[root.parent].name == "r" else {
    @failure.reject(
      "protected-content", "Rich pictures require ordinary drawings",
    )
  }
  let allowed = [
    "inline", "extent", "effectExtent", "docPr", "cNvGraphicFramePr", "graphicFrameLocks",
    "graphic", "graphicData", "pic", "nvPicPr", "cNvPr", "cNvPicPr", "picLocks",
    "blipFill", "blip", "srcRect", "stretch", "fillRect", "spPr", "xfrm", "off",
    "ext", "prstGeom", "avLst", "anchor", "simplePos", "positionH", "positionV",
    "posOffset", "align", "wrapNone", "wrapTopAndBottom", "wrapSquare",
  ]
  let (_, click) = self.drawing_link_node(drawing)
  for id in self.descendants(drawing) {
    if id == drawing || click == Some(id) {
      continue
    }
    let node = self.nodes[id]
    guard allowed.contains(node.name) &&
      [
        picture_inline_uri, picture_drawing_uri, "http://schemas.openxmlformats.org/drawingml/2006/picture",
      ].contains(node.uri) &&
      (
        node.text.trim().is_empty() ||
        ["posOffset", "align"].contains(node.name)
      ) &&
      node.attributes.all(a => {
        a.uri.is_empty() ||
        (
          node.name == "anchor" &&
          a.uri == drawing_2010_uri &&
          ["anchorId", "editId"].contains(a.name) &&
          a.value.length() == 8 &&
          a.value.iter().all(c => c.is_ascii_hexdigit())
        ) ||
        (
          node.name == "blip" &&
          (
            (
              a.uri ==
              "http://schemas.openxmlformats.org/officeDocument/2006/relationships" &&
              a.name == "embed"
            ) ||
            (a.uri == table_fragment_uri && a.name == "bytes")
          )
        )
      }) &&
      !(node.name.has_suffix("Locks") &&
      ["1", "true"].contains(node.attribute("noCopy").unwrap_or("0"))) else {
      @failure.reject(
        "protected-content", "Rich picture metadata or copying is protected",
      )
    }
  }
  guard self
    .descendants(drawing)
    .filter(id => self.nodes[id].name == "docPr")
    .length() ==
    1 &&
    self
    .descendants(drawing)
    .filter(id => self.nodes[id].name == "cNvPr")
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Rich picture requires unique native identities",
    )
  }
}

///|
fn Session::fragment_picture(
  self : Session,
  tree : WordTree,
  id : Int32,
  limit : Int32,
) -> String raise @failure.Failure {
  tree.check_fragment_picture(id)
  let image = self.editable_picture(tree, id, replace=true).0
  let bytes = self.image_bytes(image.key)
  ignore(@image.type_info(bytes))
  guard bytes.length().to_int64() * 4 / 3 + 1024 <= limit.to_int64() else {
    @failure.reject("limit-exceeded", "Rich picture exceeds clipboard budget")
  }
  let blip = tree
    .descendants(id)
    .iter()
    .find_first(child => tree.nodes[child].name == "blip")
    .unwrap()
  let node = tree.nodes[blip]
  guard node.attribute("bytes", uri=table_fragment_uri) is None else {
    @failure.reject(
      "protected-content", "Source picture contains clipboard metadata",
    )
  }
  let (document, _) = self
    .document()
    .edit_source([
      {
        node: blip,
        offset: node.opening_end - node.start - (if node.empty { 2 } else { 1 }),
        length: 0,
        xml: " xmlns:odClip=\"\{table_fragment_uri}\" odClip:bytes=\"\{@base64.encode(bytes)}\"",
      },
    ])
  let document = self.export_fragment_drawing_link(document, id)
  WordTree::new(document).standalone_markup(document, id)
}

///|
fn Session::import_fragment_drawings(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
  media : Map[String, Bytes],
  created_media : Map[String, Bytes],
) -> (@xml.Document, Map[Int32, Bool]) raise @failure.Failure {
  let tree = WordTree::new(document)
  let drawings = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing"
  })
  guard drawings.length() <= 256 else {
    @failure.reject("limit-exceeded", "Rich drawings exceed 256")
  }
  if drawings.is_empty() {
    return (document, Map([]))
  }
  let identities = self.drawing_identities()
  let changes : Array[@xml.SourceChange] = []
  let resources : Map[String, String] = Map([])
  let mut next = 1
  let mut bytes_count = 0
  for drawing in drawings {
    let chart = tree.drawing_data(drawing).1.attribute("uri") == Some(chart_uri)
    let shape = tree.drawing_data(drawing).1.attribute("uri") ==
      Some(word_shape_uri)
    if chart {
      ignore(tree.check_fragment_chart(drawing, portable=true))
    } else if shape {
      tree.check_fragment_shape(drawing)
    } else {
      tree.check_fragment_picture(drawing)
    }
    let anchor_metadata = tree.drawing_data(drawing).0.attributes.any(a => {
      a.uri == drawing_2010_uri
    })
    while next <= 16384 &&
          (
            identities.contains(next.to_string()) ||
            (
              anchor_metadata &&
              identities.contains("wp14:" + fragment_anchor_identity(next))
            )
          ) {
      next += 1
    }
    guard next <= 16384 else {
      @failure.reject("limit-exceeded", "Picture identities exhausted")
    }
    let id = next.to_string()
    identities[id] = true
    let anchor_identity = fragment_anchor_identity(next)
    if anchor_metadata {
      identities["wp14:" + anchor_identity] = true
    }
    next += 1
    tree.remap_fragment_drawing_identity(drawing, id, anchor_identity, changes)
    if chart {
      let reference = tree.check_fragment_chart(drawing, portable=true)
      let (markup, count) = self.import_fragment_chart(
        tree, drawing, id, parts, edits, created, media, created_media,
      )
      bytes_count += count
      guard bytes_count <= 2097152 else {
        @failure.reject(
          "limit-exceeded", "Rich drawing resources exceed budget",
        )
      }
      let node = tree.nodes[reference]
      changes.push({
        node: node.parent,
        offset: node.start - tree.nodes[node.parent].start,
        length: node.end - node.start,
        xml: markup,
      })
      continue
    }
    if shape {
      continue
    }
    let blips = tree
      .descendants(drawing)
      .filter(id => tree.nodes[id].name == "blip")
    guard blips is [blip] &&
      tree.nodes[blip].attribute("bytes", uri=table_fragment_uri)
      is Some(encoded) &&
      encoded.length() <= 2097152 else {
      @failure.reject(
        "protected-content", "Rich picture requires bounded portable bytes",
      )
    }
    let bytes = @base64.decode(encoded) catch {
      _ => @failure.reject("invalid-image", "Invalid copied image bytes")
    }
    let kind = @image.type_info(bytes)
    bytes_count += bytes.length()
    guard bytes_count <= 2097152 else {
      @failure.reject("limit-exceeded", "Rich image resources exceed budget")
    }
    let link = if resources.get(encoded) is Some(link) {
      link
    } else {
      let view = { ..self, parts, media, }
      let resource = view.prepare_picture_resource(
        next - 1,
        bytes,
        (kind.0, kind.1),
      )
      for (path, value) in resource.parts {
        parts[path] = value
      }
      for (path, value) in resource.edits {
        if created.contains(path) {
          created[path] = parts[path]
        } else {
          edits.get_or_init(path, () => []).append(value)
        }
      }
      for (path, value) in resource.created {
        created[path] = value
      }
      media[resource.path] = bytes
      created_media[resource.path] = bytes
      resources[encoded] = resource.link
      resource.link
    }
    for child in tree.descendants(drawing) {
      let node = tree.nodes[child]
      if node.name == "blip" {
        changes.push({
          node: node.parent,
          offset: node.start - tree.nodes[node.parent].start,
          length: node.end - node.start,
          xml: "<a:blip xmlns:a=\"\{picture_drawing_uri}\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" r:embed=\"\{link}\"/>",
        })
      }
    }
  }
  let document = document.edit_source(changes).0
  let tree = WordTree::new(document)
  let view = { ..self, parts, media, }
  let retained : Map[Int32, Bool] = Map([])
  for
    drawing in tree.order.filter(id => {
      tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing"
    }) {
    if tree.drawing_data(drawing).1.attribute("uri") == Some(chart_uri) {
      ignore(view.editable_chart(tree, drawing, operation=ChartCopy))
    } else {
      view.check_drawing_text(tree, drawing)
    }
    retained[drawing] = true
    for id in tree.descendants(drawing) {
      retained[id] = true
    }
  }
  (document, retained)
}

///|
pub fn Session::table_fragment_images(
  self : Session,
  revision : Int32,
  fragment : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let media = self.media.copy()
  let added : Map[String, Bytes] = Map([])
  ignore(
    self.read_table_fragment(fragment, parts, edits, created, media, added),
  )
  let view = { ..self, parts, media, }
  let images : Array[Json] = []
  for rel in view.relationships() {
    if rel.owner == self.main && added.get(rel.target) is Some(bytes) {
      images.push({ "key": rel.id, "bytes": @base64.encode(bytes) })
    }
  }
  { "revision": revision, "images": images }
}
