///|
priv struct PictureFrame {
  key : String
  width : Double
  height : Double
  crop : Array[Double]
  anchor : @layout.DrawingAnchor?
}

///|
fn Session::image_frame(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> PictureFrame raise @failure.Failure {
  let (_, data) = tree.drawing_data(id)
  guard data.uri == picture_drawing_uri &&
    data.attribute("uri") ==
    Some("http://schemas.openxmlformats.org/drawingml/2006/picture") else {
    @failure.reject("protected-content", "Drawing is not an ordinary picture")
  }
  let (width, height, anchor) = tree.drawing_geometry(id)
  let drawing = "http://schemas.openxmlformats.org/drawingml/2006/main"
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let mut target = None
  let mut seen_blip = false
  let crop : Array[Double] = [0, 0, 0, 0]
  let mut seen_crop = false
  for item in tree.descendants(id) {
    let node = tree.nodes[item]
    if node.start < tree.nodes[id].start || node.end > tree.nodes[id].end {
      continue
    }
    if node.uri == drawing &&
      ["effectLst", "effectDag"].contains(node.name) &&
      !tree.children[item].is_empty() {
      @failure.reject(
        "unsupported-layout", "Picture paint effects require support",
      )
    }
    if node.uri == drawing && node.name == "blip" {
      guard !seen_blip else {
        @failure.reject(
          "unsupported-layout", "Multiple picture image sources require support",
        )
      }
      seen_blip = true
      target = node.attribute("embed", uri=rel_uri)
    }
    if node.uri == drawing && node.name == "srcRect" {
      guard !seen_crop &&
        node.attributes.all(attr => {
          attr.uri.is_empty() && ["l", "t", "r", "b"].contains(attr.name)
        }) else {
        @failure.reject(
          "unsupported-layout", "Unknown or duplicate inline image crop",
        )
      }
      seen_crop = true
      for index, key in ["l", "t", "r", "b"] {
        let value = @string.parse_int(node.attribute(key).unwrap_or("0")[:]) catch {
          _ => @failure.reject("invalid-image", "Invalid inline image crop")
        }
        // shortcut: Source outsets need matching inline layout before accepting negative crop.
        guard value >= 0 && value < 100000 else {
          @failure.reject(
            "unsupported-layout", "Inline crop requires positive source insets",
          )
        }
        crop[index] = value.to_double() / 100000
      }
    }
    if node.uri == drawing &&
      node.name == "xfrm" &&
      (
        node.attribute("rot").unwrap_or("0") != "0" ||
        node.attribute("flipH") is Some("1" | "true") ||
        node.attribute("flipV") is Some("1" | "true")
      ) {
      @failure.reject(
        "unsupported-layout", "Rotated or flipped images are unsupported",
      )
    }
  }
  guard target is Some(target) &&
    width > 0 &&
    height > 0 &&
    width <= 14400 &&
    height <= 14400 &&
    crop[0] + crop[2] < 1 &&
    crop[1] + crop[3] < 1 else {
    @failure.reject("invalid-image", "Incomplete or invalid inline image")
  }
  let rel = self.image_reference(tree.part, target)
  guard width / (1 - crop[0] - crop[2]) <= 1000000000 &&
    height / (1 - crop[1] - crop[3]) <= 1000000000 else {
    @failure.reject(
      "limit-exceeded", "Expanded picture exceeds drawing coordinate budget",
    )
  }
  guard !rel.external else {
    @failure.reject(
      "missing-image", "External images require supplied resources",
    )
  }
  {
    key: if tree.part == self.main {
      target
    } else {
      self.image_resource_key(rel.target)
    },
    width,
    height,
    crop,
    anchor,
  }
}

///|
fn Session::image_reference(
  self : Session,
  owner : String,
  id : String,
) -> @opc.Relationship raise @failure.Failure {
  ignore(self.document())
  self
  .relationships()
  .iter()
  .find_first(rel => {
    rel.owner == owner && rel.id == id && rel.kind == running_rel_uri + "/image"
  })
  .unwrap_or_error(
    @failure.Failure(
      code="missing-image",
      message="Unresolved image relationship: " + id,
      part=owner,
      offset=-1,
    ),
  )
}

///|
fn Session::image_resource_key(
  self : Session,
  target : String,
) -> String raise @failure.Failure {
  let key = "watermark:" + target
  guard !self
    .relationships()
    .any(rel => {
      rel.owner == self.main &&
      rel.id == key &&
      rel.kind == running_rel_uri + "/image" &&
      rel.target != target
    }) else {
    @failure.reject(
      "protected-content", "Stored image identity conflicts with a document relationship",
    )
  }
  key
}

///|
fn Session::image_relationship(
  self : Session,
  key : String,
) -> @opc.Relationship raise @failure.Failure {
  ignore(self.document())
  for rel in self.relationships() {
    if rel.owner == self.main &&
      rel.id == key &&
      rel.kind == running_rel_uri + "/image" {
      return rel
    }
  }
  for rel in self.relationships() {
    if key == "watermark:" + rel.target &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" {
      return rel
    }
  }
  @failure.reject("missing-image", "Unresolved image relationship: " + key)
}

///|
pub fn Session::image_bytes(
  self : Session,
  key : String,
) -> Bytes raise @failure.Failure {
  if key.has_prefix("emf:") &&
    !self.relationships().any(rel => rel.owner == self.main && rel.id == key) {
    return self.ole_preview_image(key)
  }
  let rel = self.image_relationship(key)
  guard !rel.external else {
    @failure.reject(
      "missing-image", "External image bytes must be supplied explicitly",
    )
  }
  self.media.get(rel.target).unwrap_or_else(() => self.opc.read(rel.target))
}

///|
/// Register a supported raster for layout, or leave the source for host decoding.
pub fn Session::prepare_image(
  self : Session,
  key : String,
  images : @layout.Images,
) -> Bool raise @failure.Failure {
  let source = self.image_bytes(key) catch { _ => return false }
  guard @image.decode_plain_raster(source, exif_orientation=true)
    is Some((width, height, rgba)) else {
    return false
  }
  images.add(key, width, height, rgba)
  true
}
