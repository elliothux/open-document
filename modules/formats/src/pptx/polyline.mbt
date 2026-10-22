///|
fn read_polyline(
  source : Ref,
) -> Array[(Double, Double)] raise @failure.Failure {
  let tree = source.tree
  let pending = [source.node]
  while pending.pop() is Some(node) {
    pending.append(tree.children.get(node.id).unwrap_or([]))
    let keys = match node.name {
      "custGeom"
      | "avLst"
      | "gdLst"
      | "ahLst"
      | "cxnLst"
      | "pathLst"
      | "moveTo"
      | "lnTo" => []
      "rect" => ["l", "t", "r", "b"]
      "path" => ["w", "h", "fill", "stroke", "extrusionOk"]
      "pt" => ["x", "y"]
      _ =>
        @failure.reject(
          "unsupported-geometry", "Unsupported custom path command",
        )
    }
    guard node.uri == drawing_uri &&
      node.text.trim().is_empty() &&
      node.attributes.all(attr => {
        attr.uri.is_empty() && keys.contains(attr.name)
      }) else {
      @failure.reject(
        "unsupported-geometry", "Unsupported custom path metadata",
      )
    }
  }
  for name in ["avLst", "gdLst", "ahLst", "cxnLst"] {
    if source.child(name) is Some(list) {
      guard tree.children.get(list.node.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "unsupported-geometry", "Custom path guides are not supported",
        )
      }
    }
  }
  if source.child("rect") is Some(rect) {
    guard tree.children.get(rect.node.id).unwrap_or([]).is_empty() &&
      ["l", "t", "r", "b"].all(key => rect.node.attribute(key) == Some(key)) else {
      @failure.reject(
        "unsupported-geometry", "Unsupported custom text rectangle",
      )
    }
  }
  let lists = tree.children.get(source.node.id).unwrap_or([])
  guard lists.all(node => {
      ["avLst", "gdLst", "ahLst", "cxnLst", "rect", "pathLst"].contains(
        node.name,
      )
    }) &&
    source.child("pathLst") is Some(list) &&
    tree.children.get(list.node.id).unwrap_or([]) is [node] &&
    node.name == "path" else {
    @failure.reject("unsupported-geometry", "A polyline requires one path")
  }
  guard node.attribute("fill") == Some("none") &&
    flag(node, "stroke", default=true) &&
    !flag(node, "extrusionOk") else {
    @failure.reject(
      "unsupported-geometry", "Only open stroked custom paths are supported",
    )
  }
  let width = number(node.attribute("w").unwrap_or(""), 1, 182880000)
  let height = number(node.attribute("h").unwrap_or(""), 1, 182880000)
  let commands = tree.children.get(node.id).unwrap_or([])
  guard commands.length() >= 2 && commands.length() <= 4097 else {
    @failure.reject(
      "limit-exceeded", "Polyline point count is outside its budget",
    )
  }
  commands.mapi((index, command) => {
    guard command.name == (if index == 0 { "moveTo" } else { "lnTo" }) &&
      tree.children.get(command.id).unwrap_or([]) is [point] &&
      point.name == "pt" &&
      tree.children.get(point.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "unsupported-geometry", "Unsupported polyline command structure",
      )
    }
    (
      number(point.attribute("x").unwrap_or(""), 0, width) / width,
      number(point.attribute("y").unwrap_or(""), 0, height) / height,
    )
  })
}

///|
fn Object::polyline_hit(
  self : Object,
  geometry : Geometry,
  x : Double,
  y : Double,
  margin : Double,
) -> Bool {
  if self.stroke.is_empty() {
    return false
  }
  for index in 1..<self.polyline.length() {
    let (ax, ay) = self.polyline[index - 1]
    let (bx, by) = self.polyline[index]
    let ax = ax * geometry.width
    let ay = ay * geometry.height
    let dx = bx * geometry.width - ax
    let dy = by * geometry.height - ay
    let square = dx * dx + dy * dy
    let t = (if square > 0 {
        ((x - ax) * dx + (y - ay) * dy) / square
      } else {
        0.0
      })
      .max(0)
      .min(1)
    let gx = x - ax - t * dx
    let gy = y - ay - t * dy
    if gx * gx + gy * gy <= margin * margin {
      return true
    }
  }
  false
}
