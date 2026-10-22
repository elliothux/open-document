///|
fn WordTree::check_fragment_shape(
  self : WordTree,
  drawing : Int,
) -> Unit raise @failure.Failure {
  let root = self.nodes[drawing]
  guard root.uri == word_uri &&
    root.name == "drawing" &&
    root.attributes.is_empty() &&
    self.nodes[root.parent].name == "r" else {
    @failure.reject(
      "protected-content", "Rich shapes require ordinary drawings",
    )
  }
  let (frame, data) = self.drawing_data(drawing)
  guard data.attribute("uri") == Some(word_shape_uri) else {
    @failure.reject(
      "protected-content", "Rich shapes require a WordprocessingShape",
    )
  }
  ignore(self.read_basic_shape(drawing, data.id)) catch {
    @failure.Failure(code="unsupported-layout", message~, ..) =>
      @failure.reject("protected-content", message)
    error => raise error
  }
  let text_nodes : Map[Int, Bool] = Map([])
  for
    content in self
    .descendants(drawing)
    .filter(id => {
      self.nodes[id].uri == word_uri && self.nodes[id].name == "txbxContent"
    }) {
    let nodes = self.descendants(content).filter(id => id != content)
    check_fragment_content(self, nodes, Map([]))
    for id in nodes {
      self.check_text_box_clipboard_metadata(id)
      text_nodes[id] = true
    }
  }
  for id in self.descendants(drawing) {
    if text_nodes.contains(id) {
      continue
    }
    let node = self.nodes[id]
    let attributes = match node.name {
      "drawing"
      | "graphic"
      | "wsp"
      | "spPr"
      | "solidFill"
      | "noFill"
      | "avLst"
      | "cNvGraphicFramePr"
      | "noAutofit"
      | "spAutoFit" => []
      "txbx" => ["id"]
      "txbxContent" => []
      "inline" => ["distT", "distB", "distL", "distR"]
      "anchor" =>
        [
          "distT", "distB", "distL", "distR", "simplePos", "relativeHeight", "behindDoc",
          "locked", "layoutInCell", "allowOverlap",
        ]
      "simplePos" => ["x", "y"]
      "positionH" | "positionV" => ["relativeFrom"]
      "posOffset" | "align" | "wrapNone" => []
      "wrapTopAndBottom" => ["distT", "distB"]
      "wrapSquare" => ["distT", "distB", "distL", "distR", "wrapText"]
      "extent" | "ext" => ["cx", "cy"]
      "effectExtent" => ["l", "t", "r", "b"]
      "docPr" | "cNvPr" => ["id", "name", "descr", "title", "hidden"]
      "graphicData" => ["uri"]
      "cNvSpPr" => ["txBox"]
      "spLocks" | "graphicFrameLocks" =>
        [
          "noGrp", "noSelect", "noRot", "noChangeAspect", "noMove", "noResize", "noEditPoints",
          "noAdjustHandles", "noChangeArrowheads", "noChangeShapeType", "noTextEdit",
          "noDelete", "noChangeWrap", "noDrilldown", "noCopy",
        ]
      "bodyPr" =>
        [
          "rot", "lIns", "rIns", "tIns", "bIns", "anchor", "wrap", "horzOverflow",
          "vertOverflow", "spcCol", "vert", "numCol", "anchorCtr", "rtlCol", "upright",
          "fromWordArt", "forceAA", "spcFirstLastPara",
        ]
      "xfrm" => ["rot", "flipH", "flipV"]
      "off" => ["x", "y"]
      "prstGeom" | "prstTxWarp" => ["prst"]
      "srgbClr" | "prstDash" => ["val"]
      "ln" => ["w"]
      "normAutofit" => ["fontScale", "lnSpcReduction"]
      _ => @failure.reject("protected-content", "Unknown rich shape content")
    }
    guard [word_uri, word_shape_uri, picture_inline_uri, picture_drawing_uri].contains(
        node.uri,
      ) &&
      node.attributes.all(a => {
        (a.uri.is_empty() && attributes.contains(a.name)) ||
        (
          node.id == frame.id &&
          frame.name == "anchor" &&
          a.uri == drawing_2010_uri &&
          ["anchorId", "editId"].contains(a.name) &&
          a.value.length() == 8 &&
          a.value.iter().all(c => c.is_ascii_hexdigit())
        )
      }) &&
      (node.name != "bodyPr" || node.attribute("rot").unwrap_or("0") == "0") else {
      @failure.reject(
        "protected-content", "Shape clipboard metadata requires support",
      )
    }
    if ["docPr", "cNvPr"].contains(node.name) ||
      (node.name == "txbx" && node.attribute("id") is Some(_)) {
      let identity = @string.parse_int64(node.attribute("id").unwrap_or("")[:]) catch {
        _ =>
          @failure.reject("protected-content", "Invalid copied shape identity")
      }
      guard identity >= 0 && identity <= 4294967295L else {
        @failure.reject(
          "protected-content", "Copied shape identity exceeds native range",
        )
      }
    }
  }
  guard !self.shape_locked(drawing, "noCopy") else {
    @failure.reject("protected-content", "Shape copying is locked")
  }
}

///|
fn Session::fragment_drawing(
  self : Session,
  tree : WordTree,
  id : Int,
  limit : Int,
) -> String raise @failure.Failure {
  if tree.drawing_data(id).1.attribute("uri") == Some(chart_uri) {
    return self.fragment_chart(tree, id, limit)
  }
  if tree.drawing_data(id).1.attribute("uri") != Some(word_shape_uri) {
    return self.fragment_picture(tree, id, limit)
  }
  let (_, frame, _) = self.editable_shape(tree, id)
  guard tree.nodes[id].end - tree.nodes[id].start <= limit else {
    @failure.reject("limit-exceeded", "Rich shape exceeds clipboard budget")
  }
  let document = if frame.content is @layout.TextBox(_, text) {
    let content = tree
      .descendants(id)
      .iter()
      .find_first(child => {
        tree.nodes[child].uri == word_uri &&
        tree.nodes[child].name == "txbxContent"
      })
      .unwrap()
    let styles = self.styles([])
    let links = self.hyperlink_relationships()
    let bookmarks = tree.bookmark_targets()
    let output = StringBuilder()
    let mut units = 0
    for paragraph in text.paragraphs() {
      for child in tree.descendants(paragraph.id) {
        tree.check_text_box_clipboard_metadata(child)
      }
      let markup = fragment_paragraph(
        tree,
        paragraph,
        styles,
        self.document(),
        limit - units,
        links,
        bookmarks,
        Map([]),
        Map([]),
        Map([]),
      )
      let markup = markup.replace(
        old="<od:p>",
        new="<od:p xmlns:od=\"\{word_uri}\">",
      )
      guard markup.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich text box exceeds clipboard budget",
        )
      }
      units += markup.length()
      output.write_string(markup)
    }
    let node = tree.nodes[content]
    self
    .document()
    .edit_source([
      {
        node: content,
        offset: node.opening_end - node.start,
        length: node.closing_start - node.opening_end,
        xml: output.to_string(),
      },
    ]).0
  } else {
    self.document()
  }
  let tree = WordTree::new(document)
  tree.check_fragment_shape(id)
  let markup = tree.standalone_markup(document, id)
  guard markup.length() <= limit else {
    @failure.reject(
      "limit-exceeded", "Rich shape namespaces exceed clipboard budget",
    )
  }
  markup
}

///|
fn WordTree::check_text_box_clipboard_metadata(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  guard (match node.name {
    "t" =>
      node.attributes.all(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" &&
        a.name == "space" &&
        ["preserve", "default"].contains(a.value)
      })
    "tab" | "cr" => node.attributes.is_empty()
    "br" =>
      node.attributes.all(a => {
        a.uri == word_uri && a.name == "type" && a.value == "textWrapping"
      })
    _ => true
  }) else {
    @failure.reject(
      "protected-content", "Text box clipboard contains unknown text metadata",
    )
  }
}

///|
fn WordTree::remap_fragment_drawing_identity(
  self : WordTree,
  drawing : Int,
  identity : String,
  anchor_identity : String,
  changes : Array[@xml.SourceChange],
) -> Unit raise @failure.Failure {
  for id in self.descendants(drawing) {
    let node = self.nodes[id]
    if node.uri == picture_inline_uri && node.name == "anchor" {
      for attr in node.attributes {
        if attr.uri == drawing_2010_uri &&
          ["anchorId", "editId"].contains(attr.name) {
          changes.push({
            node: id,
            offset: attr.start - node.start,
            length: attr.end - attr.start,
            xml: anchor_identity,
          })
        }
      }
    }
    if ["docPr", "cNvPr"].contains(node.name) ||
      (
        node.uri == word_shape_uri &&
        node.name == "txbx" &&
        node.attribute("id") is Some(_)
      ) {
      guard node.attribute("id") is Some(_) else {
        @failure.reject("protected-content", "Missing copied drawing identity")
      }
      for attr in node.attributes {
        if attr.name == "id" && attr.uri.is_empty() {
          changes.push({
            node: id,
            offset: attr.start - node.start,
            length: attr.end - attr.start,
            xml: identity,
          })
        }
      }
    }
  }
}

///|
fn fragment_anchor_identity(identity : Int) -> String {
  let hex = identity.to_string(radix=16).to_upper()
  "0".repeat(8 - hex.length()) + hex
}

///|
fn WordTree::check_drawing_budget(
  self : WordTree,
) -> Unit raise @failure.Failure {
  guard self.order.filter(id => self.math_root(id)).length() <= 256 else {
    @failure.reject("limit-exceeded", "Document fractions exceed 256")
  }
  guard self.order
    .filter(id => {
      self.nodes[id].uri == word_uri && self.nodes[id].name == "drawing"
    })
    .length() <=
    256 else {
    @failure.reject("limit-exceeded", "Document drawings exceed 256")
  }
}
