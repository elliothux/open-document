///|
pub(all) enum BackgroundFill {
  Solid(String)
  Linear(String, String, Double, Bool)
  Picture(String, Array[Double], Double, ImageTile?, Array[Double])
} derive(Eq, Debug)

///|
pub extend BackgroundFill with Eq::{equal, not_equal}

///|
pub extend BackgroundFill with Debug::{to_repr}

///|
pub extend BackgroundFill with ToJson::{to_json}

///|
pub impl ToJson for BackgroundFill with fn to_json(self) {
  match self {
    Picture(key, crop, opacity, tile, insets) =>
      {
        "kind": "image",
        "key": key,
        "crop": Json(crop),
        "insets": Json(insets),
        "opacity": opacity,
        "mode": if tile is Some(_) {
          "tile"
        } else {
          "stretch"
        },
      }
    Solid(color) => { "kind": "solid", "color": Json(color) }
    Linear(start, end, angle, scaled) =>
      {
        "kind": "linear",
        "startColor": Json(start),
        "endColor": Json(end),
        "angle": Json(angle),
        "scaled": Json(scaled),
      }
  }
}

///|
fn BackgroundFill::normalized(
  self : BackgroundFill,
) -> BackgroundFill raise @failure.Failure {
  let colors = match self {
    Picture(_, _, _, _, _) =>
      @failure.reject("invalid-operation", "Use the background image operation")
    Solid(color) => [color]
    Linear(start, end, _, _) => [start, end]
  }
  guard colors.all(c => {
    c.length() == 6 && c.iter().all(c => c.is_ascii_hexdigit())
  }) else {
    @failure.reject(
      "invalid-operation", "Background colors require six hexadecimal digits",
    )
  }
  match self {
    Picture(_, _, _, _, _) => abort("Image background already rejected")
    Solid(color) => Solid(color.to_lower())
    Linear(start, end, angle, scaled) => {
      guard !angle.is_nan() && !angle.is_inf() && angle >= 0 && angle <= 360 else {
        @failure.reject(
          "invalid-operation", "Background angle must be 0..360 degrees",
        )
      }
      Linear(
        start.to_lower(),
        end.to_lower(),
        (angle * 60000).round() % 21600000 / 60000,
        scaled,
      )
    }
  }
}

///|
fn background_color_markup(reference : Ref) -> Unit raise @failure.Failure {
  let children = reference.tree.children.get(reference.node.id).unwrap_or([])
  guard children is [color] &&
    color.uri == drawing_uri &&
    ["srgbClr", "schemeClr", "sysClr"].contains(color.name) &&
    color.text.trim().is_empty() &&
    color.attribute("val") is Some(_) &&
    color.attributes.all(a => {
      a.uri.is_empty() &&
      (a.name == "val" || (color.name == "sysClr" && a.name == "lastClr"))
    }) else {
    @failure.reject("unsupported-style", "Unsupported gradient color")
  }
  guard reference.tree.children
    .get(color.id)
    .unwrap_or([])
    .all(node => {
      node.uri == drawing_uri &&
      ["tint", "shade", "lumMod", "lumOff"].contains(node.name) &&
      node.text.trim().is_empty() &&
      node.attributes.length() == 1 &&
      node.attribute("val") is Some(_) &&
      reference.tree.children.get(node.id).unwrap_or([]).is_empty()
    }) else {
    @failure.reject("unsupported-style", "Unsupported gradient color transform")
  }
}

///|
fn linear_background_source(
  fill : Ref,
) -> (Ref, Ref, Double, Bool) raise @failure.Failure {
  guard fill.node.text.trim().is_empty() &&
    fill.node.attributes.all(a => {
      a.uri.is_empty() &&
      a.name == "rotWithShape" &&
      ["0", "1", "true", "false"].contains(a.value)
    }) &&
    !source_xml(fill).contains("<!--") &&
    !source_xml(fill).contains("<?") else {
    @failure.reject("unsupported-style", "Unsupported linear background markup")
  }
  let children = fill.tree.children.get(fill.node.id).unwrap_or([])
  guard children.length() >= 2 &&
    children.length() <= 3 &&
    children[0].name == "gsLst" &&
    children[1].name == "lin" &&
    children.all(n => n.uri == drawing_uri && n.text.trim().is_empty()) else {
    @failure.reject(
      "unsupported-style", "Background requires linear gradient stops",
    )
  }
  let stops = children[0]
  let points = fill.tree.children.get(stops.id).unwrap_or([])
  guard stops.attributes.is_empty() &&
    points is [start, end] &&
    start.attribute("pos") == Some("0") &&
    end.attribute("pos") == Some("100000") &&
    points.all(n => {
      n.uri == drawing_uri &&
      n.name == "gs" &&
      n.text.trim().is_empty() &&
      n.attributes.length() == 1
    }) else {
    @failure.reject(
      "unsupported-style", "Background requires two endpoint stops",
    )
  }
  let start = { tree: fill.tree, node: start, }
  let end = { tree: fill.tree, node: end, }
  background_color_markup(start)
  background_color_markup(end)
  let line = children[1]
  guard fill.tree.children.get(line.id).unwrap_or([]).is_empty() &&
    line.attributes.all(a => {
      a.uri.is_empty() && ["ang", "scaled"].contains(a.name)
    }) &&
    [None, Some("0"), Some("1"), Some("true"), Some("false")].contains(
      line.attribute("scaled"),
    ) else {
    @failure.reject("unsupported-style", "Unsupported gradient angle markup")
  }
  if children.get(2) is Some(tile) {
    guard tile.name == "tileRect" &&
      fill.tree.children.get(tile.id).unwrap_or([]).is_empty() &&
      tile.attributes.all(a => {
        a.uri.is_empty() &&
        ["l", "t", "r", "b"].contains(a.name) &&
        a.value == "0"
      }) else {
      @failure.reject(
        "unsupported-style", "Unsupported gradient tile rectangle",
      )
    }
  }
  (
    start,
    end,
    number(line.attribute("ang").unwrap_or("0"), 0, 21599999) / 60000,
    flag(line, "scaled", default=true),
  )
}

///|
fn read_background_fill(
  theme : Theme,
  properties : Ref,
  opc~ : @opc.Package,
  parts~ : Map[String, @xml.Document],
  placeholder~ : Ref? = None,
) -> BackgroundFill raise @failure.Failure {
  let image = if properties.node.name == "blipFill" {
    Some(properties)
  } else {
    properties.child("blipFill")
  }
  if image is Some(image) {
    if image.node.id != properties.node.id {
      background_image_properties(properties, image)
    }
    let (key, crop, opacity, tile, insets) = read_shape_image(
      opc,
      image,
      parts,
      background=true,
    )
    return Picture(key, crop, opacity, tile, insets)
  }
  if properties.node.name == "gradFill" {
    let (start, end, angle, scaled) = linear_background_source(properties)
    return Linear(
      color(theme, start, placeholder~),
      color(theme, end, placeholder~),
      angle,
      scaled,
    )
  }
  if properties.child("gradFill") is Some(fill) {
    guard properties.tree.children
      .get(properties.node.id)
      .unwrap_or([])
      .all(node => {
        node.id == fill.node.id ||
        (
          node.uri == drawing_uri &&
          node.name == "effectLst" &&
          node.attributes.is_empty() &&
          node.text.trim().is_empty() &&
          properties.tree.children.get(node.id).unwrap_or([]).is_empty()
        )
      }) else {
      @failure.reject("unsupported-style", "Ambiguous gradient background")
    }
    return read_background_fill(theme, fill, opc~, parts~, placeholder~)
  }
  let value = if properties.node.name == "solidFill" {
    color(theme, properties, placeholder~)
  } else {
    fill(theme, [properties])
  }
  Solid(if value.is_empty() { "ffffff" } else { value })
}

///|
fn BackgroundFill::markup(self : BackgroundFill) -> String {
  match self {
    Picture(_, _, _, _, _) => abort("Image backgrounds require a relationship")
    Solid(color) => paint_markup(Some(color))
    Linear(start, end, angle, scaled) =>
      "<a:gradFill xmlns:a=\"\{drawing_uri}\"><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"\{start}\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"\{end}\"/></a:gs></a:gsLst><a:lin ang=\"\{(angle*60000).round().to_int()}\" scaled=\"\{if scaled {"1"} else {"0"}}\"/></a:gradFill>"
  }
}

///|
fn BackgroundFill::paint(
  self : BackgroundFill,
  width : Double,
  height : Double,
  tile_sizes~ : Map[String, (Int, Int)] = Map([]),
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  if self is Picture(key, crop, opacity, tile, insets) {
    let result : Array[@layout.PositionedPrimitive] = [
      Rectangle({ x: 0, y: 0, width, height, color: "ffffff", }),
      Clip({ x: 0, y: 0, width, height, }),
    ]
    if tile is Some(tile) {
      result.append(tile.paint(key, opacity, width, height, tile_sizes[key]))
    } else {
      result.append(stretched_image(key, width, height, crop, insets, opacity))
    }
    result.push(Restore)
    return result
  }
  guard self is Linear(start, end, angle, scaled) else {
    guard self is Solid(color) else { abort("Invalid background") }
    return [Rectangle({ x: 0, y: 0, width, height, color, })]
  }
  let quadrant = (angle / 90).floor().to_int()
  let delta = angle - quadrant.to_double() * 90
  let half = @math.PI / 2
  let radians = if scaled {
    let bend = if quadrant % 2 == 0 {
      @math.atan2(width, height)
    } else {
      @math.atan2(height, width)
    }
    quadrant.to_double() * half +
    (if delta <= 45 {
      bend * delta / 45
    } else {
      bend + (half - bend) * (delta - 45) / 45
    })
  } else {
    angle * @math.PI / 180
  }
  let x = @math.cos(radians)
  let y = @math.sin(radians)
  let xs = [0.0, width * x, height * y, width * x + height * y]
  let ys = [0.0, -width * y, height * x, -width * y + height * x]
  let left = xs.fold(init=0.0, (a, b) => a.min(b))
  let top = ys.fold(init=0.0, (a, b) => a.min(b))
  [
    Transform({ a: x, b: y, c: -y, d: x, e: 0, f: 0, }),
    GradientRectangle(
      {
        x: left,
        y: top,
        width: xs.fold(init=0.0, (a, b) => a.max(b)) - left,
        height: ys.fold(init=0.0, (a, b) => a.max(b)) - top,
      },
      start,
      end,
    ),
    Restore,
  ]
}
