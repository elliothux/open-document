///|
fn shape_image_source(
  fill : Ref,
  background~ : Bool = false,
) -> (String, Array[Double], Double, ImageTile?) raise @failure.Failure {
  try {
    guard fill.node.attributes.all(a => {
        a.uri.is_empty() &&
        (
          a.name == "dpi" ||
          (
            a.name == "rotWithShape" &&
            (if background {
              ["0", "1", "false", "true"]
            } else {
              ["1", "true"]
            }).contains(a.value)
          )
        )
      }) &&
      !source_xml(fill).contains("<!--") &&
      !source_xml(fill).contains("<?") else {
      @failure.reject(
        "unsupported-style", "Unsupported shape image fill metadata",
      )
    }
    if fill.node.attribute("dpi") is Some(dpi) {
      ignore(number(dpi, 0, 4294967295))
    }
    let entries = fill.tree.children.get(fill.node.id).unwrap_or([])
    let names = entries.map(n => n.name)
    guard (
        names == ["blip", "stretch"] ||
        names == ["blip", "srcRect", "stretch"] ||
        names == ["blip", "tile"] ||
        names == ["blip", "srcRect", "tile"]
      ) &&
      entries.all(n => n.uri == drawing_uri && n.text.trim().is_empty()) &&
      fill.node.text.trim().is_empty() else {
      @failure.reject(
        "unsupported-style", "Shape image fills require an embedded image and known mode",
      )
    }
    let blip = fill.child("blip").unwrap()
    guard blip.node.attributes.all(a => {
        (a.uri == relationship_uri && a.name == "embed") ||
        (
          a.uri.is_empty() &&
          a.name == "cstate" &&
          ["none", "email", "screen", "print", "hqprint"].contains(a.value)
        )
      }) &&
      blip.node.attribute("embed", uri=relationship_uri) is Some(embed) &&
      !embed.is_empty() else {
      @failure.reject(
        "unsupported-style", "External or unknown image fill references are protected",
      )
    }
    let tile = fill.child("tile").map(read_image_tile)
    if fill.child("stretch") is Some(stretch) {
      let rectangles = stretch.tree.children.get(stretch.node.id).unwrap_or([])
      guard stretch.node.attributes.is_empty() &&
        rectangles.length() <= 1 &&
        rectangles.all(n => {
          n.uri == drawing_uri &&
          n.name == "fillRect" &&
          n.text.trim().is_empty() &&
          n.attributes.all(a => {
            a.uri.is_empty() &&
            ["l", "t", "r", "b"].contains(a.name) &&
            a.value == "0"
          }) &&
          stretch.tree.children.get(n.id).unwrap_or([]).is_empty()
        }) else {
        @failure.reject(
          "unsupported-style", "Inset image fill destinations are protected",
        )
      }
    }
    let crop = if fill.child("srcRect") is Some(rect) {
      guard rect.node.attributes.all(a => {
          a.uri.is_empty() && ["l", "t", "r", "b"].contains(a.name)
        }) &&
        rect.tree.children.get(rect.node.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "unsupported-style", "Unknown image fill crop is protected",
        )
      }
      ["l", "t", "r", "b"].map(key => {
        number(rect.node.attribute(key).unwrap_or("0"), 0, 99999) / 100000
      })
    } else {
      [0.0, 0.0, 0.0, 0.0]
    }
    guard crop[0] + crop[2] < 1 && crop[1] + crop[3] < 1 else {
      @failure.reject(
        "unsupported-style", "Image fill crop must retain positive area",
      )
    }
    guard tile is None || crop.all(v => v == 0) else {
      @failure.reject("unsupported-style", "Cropped tile sources are protected")
    }
    (embed, crop, image_opacity(blip), tile)
  } catch {
    @failure.Failure(code="malformed-pptx", message~, ..) =>
      @failure.reject("unsupported-style", message)
    error => raise error
  }
}

///|
fn read_shape_image(
  opc : @opc.Package,
  fill : Ref,
  parts : Map[String, @xml.Document],
  background~ : Bool = false,
) -> (String, Array[Double], Double, ImageTile?) raise @failure.Failure {
  let (embed, crop, opacity, tile) = shape_image_source(fill, background~)
  let target = image_target(opc, fill.tree.part, embed, parts)
  guard target is Some(key) &&
    [Some("image/png"), Some("image/jpeg")].contains(
      image_content_type(opc, key, parts),
    ) else {
    @failure.reject(
      "unsupported-style", "Unsupported or external shape image fill",
    )
  }
  (key, crop, opacity, tile)
}

///|
fn Session::image_fill_reason(self : Session, object : Object) -> String {
  let reason = self.paint_reason(object)
  if !reason.is_empty() {
    return reason
  }
  if object.preset == "line" ||
    object.geometry.map(g => g.width <= 0 || g.height <= 0).unwrap_or(true) {
    return "Image fills require a closed shape with positive bounds"
  }
  ""
}

///|
fn Session::image_fill_targets(
  self : Session,
) -> Array[Object] raise @failure.Failure {
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Select shapes before setting an image fill",
    )
  }
  self.selection.objects.map(id => {
    let object = self.current().object(id)
    let reason = self.image_fill_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    object
  })
}

///|
fn image_fill_markup(
  link : String,
  opacity : Double,
  crop : Array[Double],
  tile : ImageTile?,
) -> String raise @failure.Failure {
  let alpha = if opacity == 1 {
    ""
  } else {
    "<a:alphaModFix amt=\"\{(opacity * 100000).round().to_int()}\"/>"
  }
  let rect = if crop.all(v => v == 0) {
    ""
  } else {
    "<a:srcRect l=\"\{(crop[0] * 100000).round().to_int()}\" t=\"\{(crop[1] * 100000).round().to_int()}\" r=\"\{(crop[2] * 100000).round().to_int()}\" b=\"\{(crop[3] * 100000).round().to_int()}\"/>"
  }
  let mode = tile
    .map(t => t.markup())
    .unwrap_or("<a:stretch><a:fillRect/></a:stretch>")
  "<a:blipFill xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><a:blip r:embed=\"\{xml_attribute(link)}\">\{alpha}</a:blip>\{rect}\{mode}</a:blipFill>"
}

///|
fn image_fill_opacity_markup(
  fill : Ref,
  amount : Int,
) -> String raise @failure.Failure {
  let blip = fill.child("blip").unwrap()
  let markup = if amount == 100000 {
    ""
  } else {
    "<a:alphaModFix xmlns:a=\"\{drawing_uri}\" amt=\"\{amount}\"/>"
  }
  let (document, _) = fill.tree.document.edit_source([
    paint_child_change(
      blip,
      blip.child("alphaModFix").map(v => v.node),
      markup,
      [],
    ),
  ])
  fill.tree.standalone_markup(document, fill.node.id)
}

///|
fn Object::has_fill(self : Object) -> Bool {
  !self.fill.is_empty() || self.gradient is Some(_) || self.image is Some(_)
}

///|
fn Object::image_primitive(
  self : Object,
  geometry : Geometry,
) -> @layout.PositionedPrimitive {
  let width = geometry.width / (1 - self.crop[0] - self.crop[2])
  let height = geometry.height / (1 - self.crop[1] - self.crop[3])
  Image(
    {
      key: self.image.unwrap(),
      x: -self.crop[0] * width,
      y: -self.crop[1] * height,
      width,
      height,
    },
    self.opacity,
  )
}
