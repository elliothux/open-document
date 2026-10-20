///|
pub(all) struct SnapSettings {
  grid : Bool
  objects : Bool
  spacing : Double
} derive(Eq)

///|
pub extend SnapSettings with Eq::{equal, not_equal}

///|
fn read_snapping(tree : Tree?) -> SnapSettings raise @failure.Failure {
  guard tree is Some(tree) else {
    return { grid: false, objects: true, spacing: 360000.0 / 12700, }
  }
  let owner = guide_owner(tree)
  let node = tree.one(
    tree.root("viewPr").id,
    "gridSpacing",
    uri=presentation_uri,
  )
  let mut spacing = node
    .map(node => number(node.attribute("cx").unwrap_or("360000"), 1, 2147483647))
    .unwrap_or(360000)
  // ONLYOFFICE normalizes oversized imported grid units before using the stride.
  while spacing > 1828800 {
    spacing /= 1000
  }
  {
    grid: owner.map(node => flag(node, "snapToGrid")).unwrap_or(false),
    objects: owner
    .map(node => flag(node, "snapToObjects", default=true))
    .unwrap_or(true),
    spacing: spacing.round() / 12700,
  }
}

///|
fn Session::snapping_query(self : Session) -> Json {
  try {
    let value = read_snapping(self.guide_properties())
    {
      "grid": value.grid,
      "objects": value.objects,
      "spacing": value.spacing,
      "reason": self.slide_visibility_reason(),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "grid": false,
        "objects": false,
        "spacing": 360000.0 / 12700,
        "reason": message,
      }
  }
}

///|
fn grid_spacing_markup(spacing : Double) -> String {
  let units = (spacing * 12700).round().to_int64().to_string()
  "<od:gridSpacing xmlns:od=\"\{presentation_uri}\" cx=\"\{units}\" cy=\"\{units}\"/>"
}

///|
fn grid_spacing_changes(
  tree : Tree,
  spacing : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let root = tree.root("viewPr")
  if tree.one(root.id, "gridSpacing", uri=presentation_uri) is Some(node) {
    let units = (spacing * 12700).round().to_int64().to_string()
    return [
      attribute_change({ tree, node, }, "cx", units),
      attribute_change({ tree, node, }, "cy", units),
    ]
  }
  let markup = grid_spacing_markup(spacing)
  let next = tree.one(root.id, "extLst", uri=presentation_uri)
  [
    if next is Some(next) {
      {
        node: root.id,
        offset: next.start - root.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(root, markup)
    },
  ]
}

///|
fn Session::set_snapping(
  self : Session,
  value : SnapSettings,
) -> Json raise @failure.Failure {
  guard !value.spacing.is_nan() &&
    !value.spacing.is_inf() &&
    value.spacing >= 1.0 / 12700 &&
    value.spacing <= 144 else {
    @failure.reject(
      "invalid-operation", "Grid spacing must be between one EMU and 144 points",
    )
  }
  let value = { ..value, spacing: (value.spacing * 12700).round() / 12700, }
  let tree = self.guide_properties()
  let previous = read_snapping(tree)
  if value == previous {
    return self.query()
  }
  let attributes = "showGuides=\"0\" snapToGrid=\"\{if value.grid { "1" } else { "0" }}\" snapToObjects=\"\{if value.objects { "1" } else { "0" }}\""
  let body = slide_view_markup(false, []).replace(
    old="showGuides=\"0\"",
    new=attributes,
  )
  let changes : Array[@xml.SourceChange] = []
  if tree is Some(tree) {
    if guide_owner(tree) is Some(owner) {
      for
        (name, before, after) in [
          ("snapToGrid", previous.grid, value.grid),
          ("snapToObjects", previous.objects, value.objects),
        ] {
        if before != after {
          changes.push(
            attribute_change(
              { tree, node: owner, },
              name,
              if after {
                "1"
              } else {
                "0"
              },
            ),
          )
        }
      }
    } else {
      changes.push(insert_slide_view(tree, body))
    }
  }
  self.commit_view_properties(
    tree,
    changes,
    body,
    spacing=if value.spacing == previous.spacing {
      None
    } else {
      Some(value.spacing)
    },
  )
}

///|
fn nearest_grid_point(
  value : Double,
  size : Double,
  spacing : Double,
) -> Double {
  let stride = (spacing * 12700).round()
  let origin = grid_origin(size, stride)
  let delta = (value * 12700 + 0.5).trunc() - origin
  let distance = (delta.abs() / stride + 0.5).floor() * stride
  (origin + (if delta < 0 { -distance } else { distance })) / 12700
}

///|
fn grid_origin(size : Double, stride : Double) -> Double {
  let center = (size * 12700 / 2 + 0.5).trunc()
  center - ((center / stride).trunc() + 1) * stride
}

///|
fn Session::grid_geometry(
  self : Session,
  scale : Double?,
) -> Json raise @failure.Failure {
  guard scale is Some(scale) else { return Json::null() }
  guard !scale.is_nan() && !scale.is_inf() && scale >= 0.1 && scale <= 16 else {
    @failure.reject("invalid-operation", "Invalid grid display scale")
  }
  let settings = read_snapping(self.guide_properties())
  let pixels = (units : Double) => (units / 12700 * scale + 0.5).floor()
  let mut inside = (settings.spacing * 12700).round()
  let minimum = pixels(100000).max(1)
  while pixels(inside) < minimum {
    inside *= 2
  }
  let mut line = inside
  while pixels(line) < pixels(720000).max(1) {
    line += inside
  }
  // Keep even a large page with a one-EMU source stride within the overlay budget.
  while (self.width * 12700 / inside + 2).ceil() *
        (self.height * 12700 / line + 2).ceil() +
        (if line == inside {
          0
        } else {
          (self.width * 12700 / line + 2).ceil() *
          (self.height * 12700 / inside + 2).ceil()
        }) >
        16384 {
    inside *= 2
    line = inside
    while pixels(line) < pixels(720000).max(1) {
      line += inside
    }
  }
  let points : Array[Json] = []
  let steps = if line == inside {
    [(inside, line)]
  } else {
    [(inside, line), (line, inside)]
  }
  for (sx, sy) in steps {
    for y = grid_origin(self.height, sy); y <= self.height * 12700; y = y + sy {
      if y < 0 {
        continue
      }
      for x = grid_origin(self.width, sx); x <= self.width * 12700; x = x + sx {
        if x >= 0 {
          points.push({ "x": x / 12700, "y": y / 12700 })
        }
      }
    }
  }
  { "points": points, "cross": pixels(inside) >= 17 }
}
