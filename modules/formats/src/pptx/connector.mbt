///|
pub(all) struct ConnectorEnd {
  x : Double
  y : Double
  target : String
  site : Int
} derive(Eq, ToJson)

///|
pub extend ConnectorEnd with Eq::{equal, not_equal}

///|
pub extend ConnectorEnd with ToJson::{to_json}

///|
fn connector_frame_changed(before : Geometry, after : Geometry) -> Bool {
  member_geometry_changed(before, after) ||
  before.matrix.a != after.matrix.a ||
  before.matrix.b != after.matrix.b ||
  before.matrix.c != after.matrix.c ||
  before.matrix.d != after.matrix.d ||
  before.matrix.e != after.matrix.e ||
  before.matrix.f != after.matrix.f
}

///|
fn Object::connector_properties(self : Object) -> Ref raise @failure.Failure {
  guard self.source.node.name == "cxnSp" && line_shape(self.preset) else {
    @failure.reject(
      "protected-content", "Endpoint editing requires a supported connector",
    )
  }
  self.source
  .child("nvCxnSpPr", uri=presentation_uri)
  .bind(nv => nv.child("cNvCxnSpPr", uri=presentation_uri))
  .unwrap_or_error(
    @failure.Failure(
      code="protected-content",
      part=self.source.tree.part,
      offset=-1,
      message="Missing connector properties",
    ),
  )
}

///|
fn Object::connector_targets(
  self : Object,
) -> Array[String] raise @failure.Failure {
  let properties = self.source
    .child("nvCxnSpPr", uri=presentation_uri)
    .bind(nv => nv.child("cNvCxnSpPr", uri=presentation_uri))
  if properties is None {
    return []
  }
  ["stCxn", "endCxn"].filter_map(name => {
    properties
    .unwrap()
    .child(name)
    .bind(node => node.node.attribute("id"))
    .map(id => self.source.tree.part + "#" + source_identity(id))
  })
}

///|
fn Object::connector_ends(
  self : Object,
) -> (ConnectorEnd, ConnectorEnd) raise @failure.Failure {
  let properties = self.connector_properties()
  for child in properties.tree.children.get(properties.node.id).unwrap_or([]) {
    guard child.uri == drawing_uri &&
      ["stCxn", "endCxn", "cxnSpLocks"].contains(child.name) else {
      @failure.reject(
        "protected-content", "Unknown connector metadata is protected",
      )
    }
  }
  guard self.geometry is Some(g) else {
    @failure.reject("protected-content", "Connector bounds cannot be resolved")
  }
  let points = [g.matrix.point(0, 0), g.matrix.point(g.width, g.height)]
  let ends = ["stCxn", "endCxn"].mapi((index, name) => {
    let connection = properties.child(name)
    let (target, site) = if connection is Some(connection) {
      guard connection.node.attributes.all(a => {
          a.uri.is_empty() && ["id", "idx"].contains(a.name)
        }) &&
        connection.tree.children
        .get(connection.node.id)
        .unwrap_or([])
        .is_empty() &&
        connection.node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Unknown connector endpoint is protected",
        )
      }
      let markup = source_xml(connection)
      guard !markup.contains("<!--") && !markup.contains("<?") else {
        @failure.reject(
          "protected-content", "Retained connector endpoint markup is protected",
        )
      }
      let index = number(connection.node.attribute("idx").unwrap_or(""), 0, 7)
      guard index == index.floor() else {
        @failure.reject(
          "protected-content", "Connection site must be an integer",
        )
      }
      (
        self.source.tree.part +
        "#" +
        source_identity(connection.node.attribute("id").unwrap_or("")),
        index.to_int(),
      )
    } else {
      ("", 0)
    }
    { x: points[index].0, y: points[index].1, target, site, }
  })
  (ends[0], ends[1])
}

///|
fn ConnectorEnd::resolved(
  self : ConnectorEnd,
  objects : Array[Object],
) -> ConnectorEnd raise @failure.Failure {
  guard [self.x, self.y].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) &&
    self.site >= 0 &&
    self.site <= 7 &&
    self.target.length() <= 1024 else {
    @failure.reject("invalid-operation", "Invalid connector endpoint")
  }
  if self.target.is_empty() {
    guard self.site == 0 else {
      @failure.reject("invalid-operation", "Free endpoints require site zero")
    }
    return self
  }
  guard objects.iter().find_first(o => o.id == self.target) is Some(target) else {
    @failure.reject(
      "protected-content", "Connection requires a supported local shape or picture",
    )
  }
  let (x, y) = target.connection_point(self.site)
  { ..self, x, y, }
}

///|
fn Object::connection_site_count(self : Object) -> Int {
  if self.geometry is None ||
    !["rect", "roundRect", "ellipse"].contains(self.preset) ||
    !["sp", "pic"].contains(self.source.node.name) ||
    !self.diagnostic.is_empty() {
    0
  } else if self.preset == "ellipse" {
    8
  } else {
    4
  }
}

///|
fn Object::connection_point(
  self : Object,
  site : Int,
) -> (Double, Double) raise @failure.Failure {
  guard site >= 0 && site < self.connection_site_count() else {
    @failure.reject("protected-content", "Unsupported shape connection site")
  }
  let positions = if self.preset == "ellipse" {
    let diagonal = 0.3535533905932738
    [
      (0.5, 0.0),
      (0.5 - diagonal, 0.5 - diagonal),
      (0.0, 0.5),
      (0.5 - diagonal, 0.5 + diagonal),
      (0.5, 1.0),
      (0.5 + diagonal, 0.5 + diagonal),
      (1.0, 0.5),
      (0.5 + diagonal, 0.5 - diagonal),
    ]
  } else {
    [(0.5, 0.0), (0.0, 0.5), (0.5, 1.0), (1.0, 0.5)]
  }
  let (x, y) = positions[site]
  let g = self.geometry.unwrap()
  let (x, y) = g.matrix.point(x * g.width, y * g.height)
  ((x * 12700).round() / 12700, (y * 12700).round() / 12700)
}

///|
fn connector_geometry(
  start : ConnectorEnd,
  end : ConnectorEnd,
  parent~ : @layout.Matrix = @layout.Matrix::identity(),
) -> Geometry raise @failure.Failure {
  let inverse = parent.inverse()
  let (x1, y1) = inverse.point(start.x, start.y)
  let (x2, y2) = inverse.point(end.x, end.y)
  let x1 = (x1 * 12700).round() / 12700
  let y1 = (y1 * 12700).round() / 12700
  let x2 = (x2 * 12700).round() / 12700
  let y2 = (y2 * 12700).round() / 12700
  let width = (x2 - x1).abs()
  let height = (y2 - y1).abs()
  validate_object_box(x1.min(x2), y1.min(y2), width, height, true)
  geometry_in_parent(
    x1.min(x2),
    y1.min(y2),
    width,
    height,
    0,
    x2 < x1,
    y2 < y1,
    parent,
  )
}

///|
fn connector_problem(object : Object, objects : Array[Object]) -> String {
  try {
    let (start, end) = object.connector_ends()
    for point in [start, end] {
      if !point.target.is_empty() &&
        !point.target.has_prefix(object.source.tree.part + "#") {
        return "Connections must stay in the same source part"
      }
      if !point.target.is_empty() &&
        objects.iter().find_first(o => o.id == point.target).map(o => o.parent) !=
        Some(object.parent) {
        return "Connections must share their coordinate owner"
      }
      ignore(point.resolved(objects))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::connector_query(self : Session, object : Object) -> Json {
  if object.source.node.name != "cxnSp" {
    return Json::null()
  }
  try {
    let (start, end) = object.connector_ends()
    {
      "kind": if object.preset == "bentConnector3" {
        "elbow"
      } else {
        "straight"
      },
      "start": start,
      "end": end,
      "reason": self.object_edit_reason(object, "endpoints"),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "kind": Json::null(),
        "start": Json::null(),
        "end": Json::null(),
        "reason": message,
      }
  }
}
