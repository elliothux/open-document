///|
pub(all) enum BackgroundFill {
  Solid(String)
  Linear(Array[@layout.GradientStop], Double, Bool)
  Radial(Array[@layout.GradientStop])
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
    Linear(stops, angle, scaled) =>
      {
        "kind": "linear",
        "stops": stops,
        "angle": Json(angle),
        "scaled": Json(scaled),
      }
    Radial(stops) => { "kind": "radial", "stops": stops }
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
    Linear(stops, _, _) | Radial(stops) => stops.map(stop => stop.color)
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
    Radial(stops) => {
      @layout.validate_gradient_stops(stops) catch {
        @failure.Failure(message~, ..) =>
          @failure.reject("invalid-operation", message)
      }
      Radial(
        stops.map(stop => {
          position: (stop.position * 100000).round() / 100000,
          color: stop.color.to_lower(),
          opacity: (stop.opacity * 100000).round() / 100000,
        }),
      )
    }
    Linear(stops, angle, scaled) => {
      @layout.validate_gradient_stops(stops) catch {
        @failure.Failure(message~, ..) =>
          @failure.reject("invalid-operation", message)
      }
      guard !angle.is_nan() && !angle.is_inf() && angle >= 0 && angle <= 360 else {
        @failure.reject(
          "invalid-operation", "Background angle must be 0..360 degrees",
        )
      }
      Linear(
        stops.map(stop => {
          position: (stop.position * 100000).round() / 100000,
          color: stop.color.to_lower(),
          opacity: (stop.opacity * 100000).round() / 100000,
        }),
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
      ["tint", "shade", "lumMod", "lumOff", "alpha", "alphaMod", "alphaOff"].contains(
        node.name,
      ) &&
      node.text.trim().is_empty() &&
      node.attributes.length() == 1 &&
      node.attribute("val") is Some(_) &&
      reference.tree.children.get(node.id).unwrap_or([]).is_empty()
    }) else {
    @failure.reject("unsupported-style", "Unsupported gradient color transform")
  }
}

///|
fn gradient_source(
  fill : Ref,
) -> (Array[(Ref, Double)], Double, Bool, Bool) raise @failure.Failure {
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
    ["lin", "path"].contains(children[1].name) &&
    children.all(n => n.uri == drawing_uri && n.text.trim().is_empty()) else {
    @failure.reject(
      "unsupported-style", "Background requires supported gradient stops",
    )
  }
  let stops = children[0]
  let points = fill.tree.children.get(stops.id).unwrap_or([])
  guard stops.attributes.is_empty() &&
    points.length() >= 2 &&
    points.length() <= 32 &&
    points.all(n => {
      n.uri == drawing_uri &&
      n.name == "gs" &&
      n.text.trim().is_empty() &&
      n.attributes.length() == 1
    }) else {
    @failure.reject(
      "unsupported-style", "Background requires 2..32 ordered gradient stops",
    )
  }
  let positions : Array[(Ref, Double)] = []
  for point in points {
    let position = number(point.attribute("pos").unwrap_or(""), 0, 100000)
    guard position.floor() == position &&
      positions
      .last()
      .map(previous => previous.1 <= position / 100000)
      .unwrap_or(true) else {
      @failure.reject(
        "unsupported-style", "Gradient stop positions must be ordered integer percentages",
      )
    }
    let reference = { tree: fill.tree, node: point, }
    background_color_markup(reference)
    positions.push((reference, position / 100000))
  }
  let line = children[1]
  let radial = line.name == "path"
  if radial {
    guard line.attributes.length() == 1 &&
      line.attribute("path") == Some("circle") else {
      @failure.reject(
        "unsupported-style", "Only circular radial gradients are supported",
      )
    }
    let targets = fill.tree.children.get(line.id).unwrap_or([])
    guard targets.is_empty() ||
      (
        targets is [target] &&
        target.uri == drawing_uri &&
        target.name == "fillToRect" &&
        target.text.trim().is_empty() &&
        target.attributes.length() == 4 &&
        target.attributes.all(a => {
          a.uri.is_empty() &&
          ["l", "t", "r", "b"].contains(a.name) &&
          a.value == "50000"
        }) &&
        fill.tree.children.get(target.id).unwrap_or([]).is_empty()
      ) else {
      @failure.reject(
        "unsupported-style", "Radial gradients require a centered point",
      )
    }
  } else {
    guard fill.tree.children.get(line.id).unwrap_or([]).is_empty() &&
      line.attributes.all(a => {
        a.uri.is_empty() && ["ang", "scaled"].contains(a.name)
      }) &&
      [None, Some("0"), Some("1"), Some("true"), Some("false")].contains(
        line.attribute("scaled"),
      ) else {
      @failure.reject("unsupported-style", "Unsupported gradient angle markup")
    }
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
    positions,
    number(line.attribute("ang").unwrap_or("0"), 0, 21599999) / 60000,
    flag(line, "scaled", default=true),
    radial,
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
    let (points, angle, scaled, radial) = gradient_source(properties)
    let stops : Array[@layout.GradientStop] = points.map(point => {
      let (color, opacity) = color_rgba(theme, point.0, placeholder~)
      { position: point.1, color, opacity, }
    })
    return if radial { Radial(stops) } else { Linear(stops, angle, scaled) }
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
    Radial(stops) =>
      gradient_markup(
        stops, "<a:path path=\"circle\"><a:fillToRect l=\"50000\" t=\"50000\" r=\"50000\" b=\"50000\"/></a:path>",
      )
    Linear(stops, angle, scaled) =>
      gradient_markup(
        stops,
        "<a:lin ang=\"\{(angle*60000).round().to_int()}\" scaled=\"\{if scaled {"1"} else {"0"}}\"/>",
      )
  }
}

///|
fn gradient_markup(
  stops : Array[@layout.GradientStop],
  geometry : String,
) -> String {
  let markup = stops
    .map(stop => {
      let color = if stop.opacity == 1 {
        "<a:srgbClr val=\"\{stop.color}\"/>"
      } else {
        "<a:srgbClr val=\"\{stop.color}\"><a:alpha val=\"\{(stop.opacity*100000).round().to_int()}\"/></a:srgbClr>"
      }
      "<a:gs pos=\"\{(stop.position*100000).round().to_int()}\">\{color}</a:gs>"
    })
    .join("")
  "<a:gradFill xmlns:a=\"\{drawing_uri}\"><a:gsLst>\{markup}</a:gsLst>\{geometry}</a:gradFill>"
}

///|
fn BackgroundFill::paint(
  self : BackgroundFill,
  width : Double,
  height : Double,
  tile_sizes~ : Map[String, (Int, Int)] = Map([]),
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  if self is Radial(stops) {
    return [RadialGradientRectangle({ x: 0, y: 0, width, height, }, stops)]
  }
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
  guard self is Linear(stops, angle, scaled) else {
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
      stops,
    ),
    Restore,
  ]
}
