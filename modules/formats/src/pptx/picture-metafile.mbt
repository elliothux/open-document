///|
fn picture_duotone(
  theme : Theme,
  blip : Ref,
) -> Array[Array[Double]] raise @failure.Failure {
  let nodes = blip.tree.children
    .get(blip.node.id)
    .unwrap_or([])
    .filter(n => n.uri == drawing_uri && n.name == "duotone")
  guard nodes.length() <= 1 else {
    @failure.reject("unsupported-style", "Duplicate picture duotone")
  }
  guard nodes is [node] else { return [] }
  let colors = blip.tree.children.get(node.id).unwrap_or([])
  guard node.attributes.is_empty() &&
    node.text.trim().is_empty() &&
    colors.length() == 2 else {
    @failure.reject("unsupported-style", "Picture duotone requires two colors")
  }
  colors.map(color => {
    guard color.uri == drawing_uri &&
      ["srgbClr", "schemeClr", "prstClr", "sysClr"].contains(color.name) &&
      color.text.trim().is_empty() &&
      color.attributes.all(a => {
        a.uri.is_empty() &&
        (a.name == "val" || (color.name == "sysClr" && a.name == "lastClr"))
      }) else {
      @failure.reject("unsupported-style", "Unsupported picture duotone color")
    }
    let (value, alpha) = color_value_rgba(theme, {
      tree: blip.tree,
      node: color,
    })
    guard alpha == 1 else {
      @failure.reject(
        "unsupported-style", "Picture duotone requires opaque colors",
      )
    }
    hex_color(value).map(v => (v * 255).round())
  })
}

///|
fn duotone_paint(
  color : String,
  colors : Array[Array[Double]],
) -> String raise @failure.Failure {
  if color.is_empty() || colors.is_empty() {
    return color
  }
  let rgb = hex_color(color).map(v => (v * 255).round())
  // LibreOffice BitmapDuoToneFilter uses integer luminance and two truncated components.
  let luminance = ((rgb[0] * 76 + rgb[1] * 151 + rgb[2] * 29) / 256).floor()
  rgb_hex(
    Array::makei(3, i => {
      (
        (colors[0][i] * (255 - luminance) / 255).floor() +
        (colors[1][i] * luminance / 255).floor()
      ) /
      255
    }),
  )
}

///|
fn read_picture_metafile(
  opc : @opc.Package,
  frame : Object,
  theme : Theme,
  parts : Map[String, @xml.Document],
) -> Object raise @failure.Failure {
  guard frame.kind == "image" &&
    frame.source.node.name == "pic" &&
    frame.source.child("blipFill", uri=presentation_uri) is Some(fill) &&
    fill.child("blip") is Some(blip) &&
    blip.node.attribute("embed", uri=relationship_uri) is Some(embed) &&
    relationship_target(
      opc,
      frame.source.tree.part,
      embed,
      relationship_uri + "/image",
      parts,
    )
    is Some(target) &&
    image_content_type(opc, target, parts) == Some("image/x-wmf") else {
    return frame
  }
  guard ["", "Unsupported or external image", "Unsupported picture effect"].contains(
      frame.diagnostic,
    ) &&
    frame.preset == "rect" &&
    frame.geometry is Some(geometry) &&
    frame.shadow.map(s => s.alpha == 0).unwrap_or(true) else {
    @failure.reject(
      "unsupported-style", "Unsupported WMF picture geometry or effects",
    )
  }
  let (_, crop, opacity, tile, insets) = shape_image_source(fill, duotone=true)
  guard insets.all(v => v == 0) && tile is None else {
    @failure.reject(
      "unsupported-style", "WMF picture tile or insets require support",
    )
  }
  check_image_crop_bounds(geometry.width, geometry.height, crop)
  let colors = picture_duotone(theme, blip)
  let file = @image.read_wmf(opc.read(target))
  let commands = file.commands.map(command => {
    match command {
      @layout.Vector(path, fill, stroke, width, pen, clip) =>
        @layout.Vector(
          path,
          duotone_paint(fill, colors),
          duotone_paint(stroke, colors),
          width,
          {
            ..pen,
            fillAlpha: pen.fillAlpha * opacity,
            strokeAlpha: pen.strokeAlpha * opacity,
          },
          clip,
        )
      _ =>
        @failure.reject(
          "unsupported-image", "WMF picture requires vector content",
        )
    }
  })
  {
    ..frame,
    image: None,
    crop,
    metafile: Some(@layout.Metafile::new(file.bounds, commands)),
    opacity,
    diagnostic: "",
    read_only: if frame.read_only == frame.diagnostic {
      if frame.parent.is_empty() {
        ""
      } else {
        "Group members are read-only"
      }
    } else {
      frame.read_only
    },
    text_reason: "",
  }
}

///|
fn positioned_picture_metafile(
  file : @layout.Metafile,
  geometry : Geometry,
  crop : Array[Double],
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  let width = geometry.width
  let height = geometry.height
  let paint = file.positioned(width, height, probe, profile)
  if crop.all(value => value == 0) {
    return paint
  }
  let sx = 1.0 / (1 - crop[0] - crop[2])
  let sy = 1.0 / (1 - crop[1] - crop[3])
  [
    Clip({ x: 0, y: 0, width, height, }),
    Transform({
      a: sx,
      b: 0,
      c: 0,
      d: sy,
      e: -crop[0] * width * sx,
      f: -crop[1] * height * sy,
    }),
    ..paint,
    Restore,
    Restore,
  ]
}
