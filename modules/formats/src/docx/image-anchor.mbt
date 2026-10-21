///|
fn anchor_flag(
  node : @xml.Node,
  name : String,
  fallback : Bool,
) -> Bool raise @failure.Failure {
  match node.attribute(name) {
    None => fallback
    Some("1" | "true") => true
    Some("0" | "false") => false
    _ => @failure.reject("unsupported-layout", "Invalid floating image " + name)
  }
}

///|
fn WordTree::anchor_children(
  self : WordTree,
  id : Int,
  names : Array[String],
) -> Unit raise @failure.Failure {
  let seen : Map[String, Unit] = Map([])
  for child in self.children[id] {
    let node = self.nodes[child]
    guard (
        (node.uri == picture_inline_uri && names.contains(node.name)) ||
        (
          node.uri == picture_drawing_uri &&
          node.name == "graphic" &&
          names.contains("graphic")
        )
      ) &&
      !seen.contains(node.name) else {
      @failure.reject(
        "unsupported-layout", "Unknown or duplicate floating image content",
      )
    }
    seen[node.name] = ()
  }
}

///|
fn WordTree::anchor_child(
  self : WordTree,
  id : Int,
  name : String,
) -> Int raise @failure.Failure {
  let nodes = self.children[id].filter(child => {
    self.nodes[child].uri == picture_inline_uri &&
    self.nodes[child].name == name
  })
  guard nodes is [node] else {
    @failure.reject(
      "unsupported-layout",
      "Missing or duplicate floating image " + name,
    )
  }
  node
}

///|
fn WordTree::image_axis(
  self : WordTree,
  id : Int,
) -> @layout.ImageAxis raise @failure.Failure {
  let node = self.nodes[id]
  guard node.attributes.all(a => a.uri.is_empty() && a.name == "relativeFrom") else {
    @failure.reject("unsupported-layout", "Unknown floating image position")
  }
  self.anchor_children(id, ["posOffset", "align"])
  guard self.children[id] is [value] &&
    self.children[value].is_empty() &&
    self.nodes[value].attributes.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Unsupported floating image position value",
    )
  }
  let reference = node.attribute("relativeFrom").unwrap_or("")
  if self.nodes[value].name == "align" {
    @layout.Aligned(reference, self.nodes[value].text.trim().to_owned())
  } else {
    let offset = @string.parse_int64(self.nodes[value].text.trim()) catch {
      _ => @failure.reject("invalid-image", "Invalid floating image offset")
    }
    @layout.Offset(reference, offset.to_double() / 12700)
  }
}

///|
fn WordTree::image_anchor(
  self : WordTree,
  drawing : Int,
  id : Int,
) -> @layout.ImageAnchor raise @failure.Failure {
  let node = self.nodes[id]
  guard self.children[drawing] is [child] &&
    child == id &&
    node.attributes.all(a => {
      (
        a.uri.is_empty() &&
        [
          "distT", "distB", "distL", "distR", "simplePos", "relativeHeight", "behindDoc",
          "locked", "layoutInCell", "allowOverlap",
        ].contains(a.name)
      ) ||
      (
        a.uri ==
        "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" &&
        ["anchorId", "editId"].contains(a.name)
      )
    }) else {
    @failure.reject(
      "unsupported-layout", "Unknown floating image frame attributes",
    )
  }
  guard !anchor_flag(node, "simplePos", false) &&
    anchor_flag(node, "allowOverlap", true) else {
    @failure.reject(
      "unsupported-layout", "Simple or nonoverlapping floating image positioning requires support",
    )
  }
  ignore(anchor_flag(node, "layoutInCell", true))
  ignore(anchor_flag(node, "locked", false))
  for key in ["distT", "distB", "distL", "distR"] {
    let distance = @string.parse_int64(node.attribute(key).unwrap_or("0")[:]) catch {
      _ =>
        @failure.reject("invalid-image", "Invalid floating image text distance")
    }
    guard distance >= 0 && distance <= 182880000L else {
      @failure.reject(
        "limit-exceeded", "Floating image text distance exceeds budget",
      )
    }
  }
  self.anchor_children(id, [
    "simplePos", "positionH", "positionV", "extent", "effectExtent", "docPr", "cNvGraphicFramePr",
    "wrapNone", "graphic",
  ])
  let graphics = self.children[id].filter(child => {
    self.nodes[child].uri == picture_drawing_uri &&
    self.nodes[child].name == "graphic"
  })
  guard graphics is [graphic] &&
    self.children[graphic] is [data] &&
    self.nodes[data].uri == picture_drawing_uri &&
    self.nodes[data].name == "graphicData" &&
    self.nodes[data].attribute("uri") ==
    Some("http://schemas.openxmlformats.org/drawingml/2006/picture") &&
    self.children[data] is [picture] &&
    self.nodes[picture].uri ==
    "http://schemas.openxmlformats.org/drawingml/2006/picture" &&
    self.nodes[picture].name == "pic" else {
    @failure.reject(
      "unsupported-layout", "Floating drawing requires ordinary picture data",
    )
  }
  let wrap = self.anchor_child(id, "wrapNone")
  guard self.children[wrap].is_empty() && self.nodes[wrap].attributes.is_empty() else {
    @failure.reject("unsupported-layout", "Unknown floating image wrapping")
  }
  let simple = self.anchor_child(id, "simplePos")
  guard self.children[simple].is_empty() &&
    self.nodes[simple].attributes.all(a => {
      a.uri.is_empty() && ["x", "y"].contains(a.name) && a.value == "0"
    }) else {
    @failure.reject(
      "unsupported-layout", "Unsupported floating image simple position",
    )
  }
  for child in self.children[id] {
    if self.nodes[child].name == "effectExtent" {
      guard self.children[child].is_empty() &&
        self.nodes[child].attributes.all(a => {
          a.uri.is_empty() &&
          ["l", "t", "r", "b"].contains(a.name) &&
          a.value == "0"
        }) else {
        @failure.reject(
          "unsupported-layout", "Floating image effects require layout support",
        )
      }
    }
  }
  for parent = node.parent; parent >= 0; parent = self.nodes[parent].parent {
    guard !["tc", "hdr", "ftr"].contains(self.nodes[parent].name) else {
      @failure.reject(
        "unsupported-layout", "Floating images require a body paragraph",
      )
    }
  }
  let order = @string.parse_int64(
    node.attribute("relativeHeight").unwrap_or("0")[:],
  ) catch {
    _ => @failure.reject("invalid-image", "Invalid floating image order")
  }
  let result : @layout.ImageAnchor = {
    horizontal: self.image_axis(self.anchor_child(id, "positionH")),
    vertical: self.image_axis(self.anchor_child(id, "positionV")),
    behind: anchor_flag(node, "behindDoc", false),
    order,
  }
  result.validate()
  result
}
