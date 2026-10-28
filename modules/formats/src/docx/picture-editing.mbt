///|
let picture_drawing_uri = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
let picture_inline_uri = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"

///|
fn Session::editable_picture(
  self : Session,
  tree : WordTree,
  id : Int32,
  remove~ : Bool = false,
  replace~ : Bool = false,
  position~ : Bool = false,
) -> (PictureFrame, Int32, Int32, Int32?) raise @failure.Failure {
  let paragraph = self.drawing_paragraph(tree, id)
  let image = self.image_frame(tree, id) catch {
    @failure.Failure(code="unsupported-layout", message~, ..) =>
      @failure.reject("protected-content", message)
    error => raise error
  }
  let (fill, crop) = tree.picture_content(id, remove~, replace~, position~)
  (image, paragraph, fill, crop)
}

///|
fn Session::drawing_paragraph(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> Int32 raise @failure.Failure {
  self.check_picture_context(tree)
  guard tree.nodes.get(id) is Some(node) &&
    node.uri == word_uri &&
    node.name == "drawing" else {
    @failure.reject("invalid-operation", "Unknown drawing")
  }
  let run = tree.nodes
    .get(node.parent)
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part=self.main,
        offset=id,
        message="Missing picture run",
      ),
    )
  guard run.uri == word_uri &&
    run.name == "r" &&
    tree.nodes.get(run.parent) is Some(paragraph) &&
    paragraph.uri == word_uri &&
    paragraph.name == "p" else {
    @failure.reject("protected-content", "Picture requires a paragraph run")
  }
  for parent = paragraph.parent; parent >= 0; parent = tree.nodes[parent].parent {
    guard tree.nodes[parent].uri == word_uri &&
      ["tc", "tr", "tbl", "body", "document"].contains(tree.nodes[parent].name) else {
      @failure.reject(
        "protected-content", "Picture is inside a protected container",
      )
    }
  }
  for child in tree.descendants(paragraph.id) {
    guard !["pPrChange", "rPrChange"].contains(tree.nodes[child].name) else {
      @failure.reject(
        "protected-content", "Tracked picture paragraph properties are protected",
      )
    }
  }
  paragraph.id
}

///|
fn WordTree::picture_content(
  tree : WordTree,
  id : Int32,
  remove~ : Bool,
  replace~ : Bool,
  position~ : Bool,
) -> (Int32, Int32?) raise @failure.Failure {
  let extents : Array[Int32] = []
  let fills : Array[Int32] = []
  let crops : Array[Int32] = []
  for child in tree.descendants(id) {
    let node = tree.nodes[child]
    guard [
        word_uri, picture_drawing_uri, picture_inline_uri, "http://schemas.openxmlformats.org/drawingml/2006/picture",
      ].contains(node.uri) &&
      !["extLst", "effectLst", "effectDag", "tile"].contains(node.name) else {
      @failure.reject(
        "protected-content", "Picture effects extensions or locks require editing support",
      )
    }
    if node.name.has_suffix("Locks") &&
      node.attributes.any(attr => {
        (if remove {
          ["noDelete"]
        } else if position {
          ["noMove", "noChangeWrap"]
        } else if replace {
          []
        } else {
          ["noCrop", "noResize"]
        }).contains(attr.name) &&
        ["1", "true"].contains(attr.value)
      }) {
      @failure.reject("protected-content", "Picture operation is locked")
    }
    if node.uri == picture_drawing_uri &&
      node.name == "blip" &&
      !tree.children[child].is_empty() {
      @failure.reject(
        "protected-content", "Picture color effects require editing support",
      )
    }
    if (node.uri == picture_inline_uri && node.name == "extent") ||
      (node.uri == picture_drawing_uri && node.name == "ext") {
      extents.push(child)
    }
    if node.uri == picture_drawing_uri && node.name == "blipFill" {
      fills.push(child)
    }
    if node.name == "blipFill" &&
      node.uri == "http://schemas.openxmlformats.org/drawingml/2006/picture" {
      fills.push(child)
    }
    if node.uri == picture_drawing_uri && node.name == "srcRect" {
      guard tree.children[child].is_empty() &&
        node.text.trim().is_empty() &&
        !tree.source[node.start:node.end].contains("<!--") &&
        !tree.source[node.start:node.end].contains("<?") &&
        node.attributes.all(attr => {
          attr.uri.is_empty() && ["l", "t", "r", "b"].contains(attr.name)
        }) else {
        @failure.reject("protected-content", "Unknown picture crop markup")
      }
      crops.push(child)
    }
  }
  guard extents.length() == 2 &&
    fills.length() == 1 &&
    crops.length() <= 1 &&
    crops.all(crop => tree.nodes[crop].parent == fills[0]) &&
    tree.children[fills[0]]
    .filter(child => {
      tree.nodes[child].uri == picture_drawing_uri &&
      tree.nodes[child].name == "stretch"
    })
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "Picture requires one frame and stretch fill",
    )
  }
  for extent in extents {
    guard tree.nodes[extent].attribute("cx") is Some(_) &&
      tree.nodes[extent].attribute("cy") is Some(_) else {
      @failure.reject("protected-content", "Incomplete picture extent")
    }
  }
  let blips = tree
    .descendants(id)
    .filter(child => {
      tree.nodes[child].uri == picture_drawing_uri &&
      tree.nodes[child].name == "blip"
    })
  guard blips.length() == 1 &&
    tree.nodes[blips[0]].parent == fills[0] &&
    tree.nodes[blips[0]].attribute(
      "link",
      uri="http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    )
    is None else {
    @failure.reject("protected-content", "Picture requires one embedded source")
  }
  if remove {
    tree.check_picture_references(id)
  }
  (fills[0], crops.get(0))
}

///|
pub fn Session::pictures(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let images : Array[Json] = []
  let selected = self.selected_drawing(tree)
  let links = self.hyperlink_relationships()
  let bookmarks = tree.bookmark_targets()
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri || node.name != "drawing" {
      continue
    }
    if [Some(word_shape_uri), Some(chart_uri)].contains(
        tree.drawing_data(id).1.attribute("uri"),
      ) {
      continue
    }
    guard images.length() < 256 else {
      @failure.reject("limit-exceeded", "Picture list exceeds 256 entries")
    }
    let name = tree
      .descendants(id)
      .iter()
      .find_first(child => {
        tree.nodes[child].uri == picture_inline_uri &&
        tree.nodes[child].name == "docPr"
      })
      .map(child => tree.nodes[child].attribute("name").unwrap_or("Picture"))
      .unwrap_or("Picture")
    let (image, reason) = (Some(self.editable_picture(tree, id).0), "") catch {
      @failure.Failure(message~, ..) => (None, message)
    }
    let delete_reason = try {
      ignore(self.editable_picture(tree, id, remove=true))
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    let replace_reason = try {
      ignore(self.editable_picture(tree, id, replace=true))
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    let (position_image, position_reason) = (
      Some(self.editable_picture(tree, id, position=true).0),
      "",
    ) catch {
      @failure.Failure(message~, ..) => (None, message)
    }
    images.push({
      "id": id,
      "selected": selected == Some(id),
      "name": name,
      "width": image.map(image => image.width).unwrap_or(0),
      "height": image.map(image => image.height).unwrap_or(0),
      "crop": image.map(image => image.crop).unwrap_or([0, 0, 0, 0]),
      "reason": reason,
      "deleteReason": delete_reason,
      "replaceReason": replace_reason,
      "anchor": position_image
      .bind(image => image.anchor)
      .map(anchor => anchor.to_json())
      .unwrap_or(Json::null()),
      "positionReason": position_reason,
      "hyperlink": self.drawing_link_summary(tree, id, links~, bookmarks~),
    })
  }
  { "revision": revision, "images": images }
}

///|
pub fn Session::edit_picture(
  self : Session,
  revision : Int32,
  id : Int32,
  width : Double,
  height : Double,
  crop : Array[Double],
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let prepared = self.prepare_picture_resize(id, width, height, crop)
  if prepared is Some(prepared) {
    self.check_picture_layout(prepared.document, probe, profile, images)
    self.commit_edit(prepared.edit, prepared.document)
  }
  self.edit_result(prepared.map(p => p.edit.paragraphs).unwrap_or([]))
}

///|
fn Session::prepare_picture_resize(
  self : Session,
  id : Int32,
  width : Double,
  height : Double,
  crop : Array[Double],
) -> PreparedEdit? raise @failure.Failure {
  guard [width, height].all(v => {
      !v.is_nan() && !v.is_inf() && v >= 0.1 && v <= 14400
    }) &&
    crop.length() == 4 &&
    crop.all(v => !v.is_nan() && !v.is_inf() && v >= 0 && v < 1) else {
    @failure.reject("invalid-operation", "Invalid picture size or crop")
  }
  let width = (width * 12700).round() / 12700
  let height = (height * 12700).round() / 12700
  let crop = crop.map(v => (v * 100000).round() / 100000)
  guard crop[0] + crop[2] < 1 && crop[1] + crop[3] < 1 else {
    @failure.reject(
      "invalid-operation", "Picture crop removes its entire source",
    )
  }
  guard width / (1 - crop[0] - crop[2]) <= 1000000000 &&
    height / (1 - crop[1] - crop[3]) <= 1000000000 else {
    @failure.reject(
      "limit-exceeded", "Expanded picture exceeds drawing coordinate budget",
    )
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let (image, paragraph, fill, existing) = self.editable_picture(tree, id)
  for child in tree.descendants(id) {
    let node = tree.nodes[child]
    if node.name.has_suffix("Locks") &&
      ["1", "true"].contains(node.attribute("noChangeAspect").unwrap_or("0")) {
      guard (width * image.height - height * image.width).abs() <=
        (image.width + image.height) / 12700 else {
        @failure.reject("protected-content", "Picture aspect ratio is locked")
      }
    }
  }
  if image.width == width && image.height == height && image.crop == crop {
    return None
  }
  let changes : Array[@xml.SourceChange] = []
  for child in tree.descendants(id) {
    let node = tree.nodes[child]
    if (node.uri == picture_inline_uri && node.name == "extent") ||
      (node.uri == picture_drawing_uri && node.name == "ext") {
      for attr in node.attributes {
        let value = if attr.name == "cx" {
          Some(width)
        } else if attr.name == "cy" {
          Some(height)
        } else {
          None
        }
        if value is Some(value) && attr.uri.is_empty() {
          let xml = (value * 12700).round().to_int64().to_string()
          if attr.value != xml {
            changes.push({
              node: child,
              offset: attr.start - node.start,
              length: attr.end - attr.start,
              xml,
            })
          }
        }
      }
    }
  }
  if image.crop != crop {
    let markup = StringBuilder()
    markup.write_string("<a:srcRect xmlns:a=\"\{picture_drawing_uri}\"")
    for index, key in ["l", "t", "r", "b"] {
      markup.write_string(
        " \{key}=\"\{(crop[index] * 100000).round().to_int()}\"",
      )
    }
    markup.write_string("/>")
    let node = tree.nodes[fill]
    let before = existing.map(id => tree.nodes[id])
    let offset = before
      .map(item => item.start)
      .unwrap_or_else(() => {
        tree.children[fill]
        .iter()
        .find_first(child => tree.nodes[child].name == "stretch")
        .map(child => tree.nodes[child].start)
        .unwrap_or(node.closing_start)
      })
    changes.push({
      node: fill,
      offset: offset - node.start,
      length: before.map(item => item.end - item.start).unwrap_or(0),
      xml: markup.to_string(),
    })
  }
  let (candidate, xml) = document.edit_source(changes)
  Some({
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
    document: candidate,
    typing_text: None,
    join_group: false,
  })
}

///|
fn Session::check_picture_context(
  self : Session,
  tree : WordTree,
) -> Unit raise @failure.Failure {
  ignore(self.editable_page_section(tree))
  if self.settings_part() is Some(part) {
    let settings = WordTree::new(self.part_xml(part))
    for setting in settings.children[0] {
      let node = settings.nodes[setting]
      if node.uri == word_uri &&
        node.name == "trackRevisions" &&
        !["0", "false", "off"].contains(
          node.attribute("val", uri=word_uri).unwrap_or("1"),
        ) {
        @failure.reject(
          "protected-content", "Tracked picture edits require revision support",
        )
      }
    }
  }
}
