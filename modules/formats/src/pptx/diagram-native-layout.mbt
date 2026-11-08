///|
priv struct DiagramNode {
  source : Ref
  key : String
  kind : String
  children : Array[DiagramNode]
}

///|
fn diagram_active(source : Ref) -> Array[Ref] raise @failure.Failure {
  let output : Array[Ref] = []
  for node in source.tree.children.get(source.node.id).unwrap_or([]) {
    if node.uri != diagram_uri {
      continue
    }
    let child : Ref = { tree: source.tree, node, }
    if node.name != "choose" {
      output.push(child)
      continue
    }
    let mut selected : Ref? = None
    for branch in source.tree.children.get(node.id).unwrap_or([]) {
      guard branch.uri == diagram_uri && ["if", "else"].contains(branch.name) else {
        @failure.reject(
          "unsupported-style", "Unsupported SmartArt layout choice",
        )
      }
      if branch.name == "else" {
        selected = Some({ tree: source.tree, node: branch, })
        break
      }
      guard branch.attribute("func") == Some("var") &&
        branch.attribute("op") == Some("equ") &&
        [Some("dir"), Some("hierBranch")].contains(branch.attribute("arg")) else {
        @failure.reject(
          "unsupported-style", "SmartArt layout choice requires another algorithm",
        )
      }
      let value = if branch.attribute("arg") == Some("dir") {
        "norm"
      } else {
        "init"
      }
      if branch.attribute("val") == Some(value) {
        selected = Some({ tree: source.tree, node: branch, })
        break
      }
    }
    if selected is Some(branch) {
      output.append(diagram_active(branch))
    }
  }
  output
}

///|
fn diagram_check_algorithm(
  source : Ref,
  kind : String,
  parameters : Map[String, String],
) -> Unit raise @failure.Failure {
  let algorithms = diagram_active(source).filter(n => n.node.name == "alg")
  guard algorithms is [algorithm] &&
    algorithm.node.attribute("type") == Some(kind) else {
    @failure.reject(
      "unsupported-style", "Unsupported SmartArt hierarchy algorithm",
    )
  }
  let params = algorithm.tree.children.get(algorithm.node.id).unwrap_or([])
  guard params.length() == parameters.length() &&
    parameters
    .keys()
    .all(key => {
      params.filter(n => n.attribute("type") == Some(key)).length() == 1
    }) &&
    params.all(n => {
      n.uri == diagram_uri &&
      n.name == "param" &&
      parameters.get(n.attribute("type").unwrap_or("")) == n.attribute("val")
    }) else {
    @failure.reject(
      "unsupported-style", "Unsupported SmartArt hierarchy parameters",
    )
  }
}

///|
fn diagram_content(root : Ref) -> Array[DiagramNode] raise @failure.Failure {
  let points = root.diagram_child("ptLst")
  guard points.tree.children
    .get(points.node.id)
    .unwrap_or([])
    .all(n => n.uri == diagram_uri && n.name == "pt") else {
    @failure.reject(
      "unsupported-style", "Unsupported SmartArt point declaration",
    )
  }
  let nodes : Map[String, Ref] = Map([])
  let edges : Map[String, Array[(Int32, String)]] = Map([])
  let parents : Map[String, String] = Map([])
  let identities : Map[String, Bool] = Map([])
  for node in root.tree.all(points.node.id, "pt", uri=diagram_uri) {
    guard identities.length() < 4096 else {
      @failure.reject(
        "limit-exceeded", "SmartArt presentation exceeds point budget",
      )
    }
    let key = node.attribute("modelId").unwrap_or("")
    guard !key.is_empty() && key.length() <= 128 && !identities.contains(key) else {
      @failure.reject("malformed-pptx", "Invalid SmartArt point identity")
    }
    identities[key] = true
    let kind = node.attribute("type").unwrap_or("node")
    guard ["doc", "node", "asst", "pres", "parTrans", "sibTrans"].contains(kind) else {
      @failure.reject("unsupported-style", "Unsupported SmartArt point type")
    }
    if ["doc", "node", "asst"].contains(kind) {
      guard nodes.length() < 128 else {
        @failure.reject(
          "limit-exceeded", "SmartArt content exceeds node budget",
        )
      }
      nodes[key] = { tree: root.tree, node, }
    }
  }
  let connections = root.diagram_child("cxnLst")
  guard connections.tree.children
    .get(connections.node.id)
    .unwrap_or([])
    .all(n => n.uri == diagram_uri && n.name == "cxn") else {
    @failure.reject(
      "unsupported-style", "Unsupported SmartArt connection declaration",
    )
  }
  let connection_ids : Map[String, Bool] = Map([])
  for node in root.tree.all(connections.node.id, "cxn", uri=diagram_uri) {
    guard connection_ids.length() < 4096 else {
      @failure.reject("limit-exceeded", "SmartArt connections exceed budget")
    }
    let key = node.attribute("modelId").unwrap_or("")
    let from = node.attribute("srcId").unwrap_or("")
    let to = node.attribute("destId").unwrap_or("")
    guard !key.is_empty() &&
      key.length() <= 128 &&
      !connection_ids.contains(key) &&
      identities.contains(from) &&
      identities.contains(to) else {
      @failure.reject("malformed-pptx", "Invalid SmartArt connection identity")
    }
    connection_ids[key] = true
    let kind = node.attribute("type").unwrap_or("parOf")
    guard ["parOf", "presOf", "presParOf"].contains(kind) else {
      @failure.reject(
        "unsupported-style", "Unsupported SmartArt connection type",
      )
    }
    if kind != "parOf" {
      continue
    }
    guard nodes.contains(from) && nodes.contains(to) && !parents.contains(to) else {
      @failure.reject("malformed-pptx", "Invalid SmartArt content parent")
    }
    let order = number(node.attribute("srcOrd").unwrap_or("0"), 0, 4095).to_int()
    let items = edges.get_or_init(from, () => [])
    guard !items.any(item => item.0 == order) else {
      @failure.reject("malformed-pptx", "Duplicate SmartArt sibling order")
    }
    items.push((order, to))
    parents[to] = from
  }
  let documents = nodes
    .values()
    .filter(n => n.node.attribute("type") == Some("doc"))
    .to_array()
  guard documents is [document] &&
    !parents.contains(document.node.attribute("modelId").unwrap()) else {
    @failure.reject("malformed-pptx", "SmartArt requires one content root")
  }
  let visited : Map[String, Bool] = Map([])
  fn visit(key : String, depth : Int32) -> DiagramNode raise @failure.Failure {
    guard !visited.contains(key) else {
      @failure.reject("malformed-pptx", "Cyclic SmartArt content")
    }
    guard depth <= 32 else {
      @failure.reject("limit-exceeded", "SmartArt content exceeds depth budget")
    }
    visited[key] = true
    let source = nodes[key]
    let items = edges.get(key).unwrap_or([])
    items.sort_by((a, b) => a.0.compare(b.0))
    let children = items.map(item => visit(item.1, depth + 1))
    {
      source,
      key,
      kind: source.node.attribute("type").unwrap_or("node"),
      children,
    }
  }
  let document = visit(document.node.attribute("modelId").unwrap(), 0)
  guard visited.length() == nodes.length() else {
    @failure.reject("malformed-pptx", "Disconnected SmartArt content")
  }
  document.children
}

///|
fn diagram_decimal(
  node : @xml.Node,
  key : String,
) -> Double raise @failure.Failure {
  let value = @string.parse_double(node.attribute(key).unwrap_or("0")) catch {
    _ => @failure.reject("malformed-pptx", "Invalid SmartArt constraint number")
  }
  guard !value.is_nan() && !value.is_inf() && value >= 0 && value <= 65 else {
    @failure.reject(
      "unsupported-style", "SmartArt constraint exceeds supported bounds",
    )
  }
  value
}

///|
fn diagram_constraint(
  layout : Ref,
  kind : String,
  target : String,
) -> Double raise @failure.Failure {
  let list = layout.diagram_child("constrLst")
  let values = layout.tree
    .all(list.node.id, "constr", uri=diagram_uri)
    .filter(n => {
      n.attribute("type") == Some(kind) &&
      n.attribute("forName").unwrap_or("") == target
    })
  guard values is [value] && value.attribute("refType") == Some("w") else {
    @failure.reject(
      "unsupported-style", "Unsupported SmartArt hierarchy constraint",
    )
  }
  let factor = diagram_decimal(value, "fact")
  guard factor > 0 else {
    @failure.reject(
      "unsupported-style", "SmartArt hierarchy requires positive spacing",
    )
  }
  factor
}

///|
fn diagram_hierarchy_boxes(
  roots : Array[DiagramNode],
  layout : Ref,
  frame : Geometry,
) -> Array[(DiagramNode, Geometry)] raise @failure.Failure {
  let h = diagram_constraint(layout, "h", "rootComposite1")
  let gap = diagram_constraint(layout, "sp", "hierRoot1")
  let sibling = diagram_constraint(layout, "sibSp", "")
  let secondary = diagram_constraint(layout, "secSibSp", "")
  let boxes : Array[(DiagramNode, Double, Double)] = []
  // ONLYOFFICE SmartArtTree packs intersecting levels before centering the forest.
  for root in roots {
    guard root.kind == "node" && root.children.all(n => n.children.is_empty()) else {
      @failure.reject(
        "unsupported-style", "SmartArt hierarchy requires deeper branch layout",
      )
    }
    let assistants = root.children.filter(n => n.kind == "asst")
    let children = root.children.filter(n => n.kind == "node")
    guard assistants.length() <= 1 &&
      assistants.length() + children.length() == root.children.length() else {
      @failure.reject(
        "unsupported-style", "SmartArt hierarchy requires further assistant layout",
      )
    }
    let branch : Array[(DiagramNode, Double, Double)] = [(root, 0, 0)]
    let child_top = if assistants.is_empty() { h + gap } else { 2 * (h + gap) }
    if assistants is [assistant] {
      branch.push((assistant, -0.5 - secondary / 2, h + gap))
    }
    let width = children.length().to_double() * (1 + sibling) - sibling
    for index, child in children {
      branch.push(
        (child, (1 - width) / 2 + index.to_double() * (1 + sibling), child_top),
      )
    }
    let mut shift = 0.0
    for (_, x, y) in branch {
      for (_, previous_x, previous_y) in boxes {
        if y < previous_y + h && previous_y < y + h {
          shift = shift.max(previous_x + 1 + sibling - x)
        }
      }
    }
    for (node, x, y) in branch {
      boxes.push((node, x + shift, y))
    }
  }
  guard !boxes.is_empty() else {
    @failure.reject("unsupported-style", "SmartArt hierarchy has no content")
  }
  let left = boxes.fold(init=0.0, (v, b) => v.min(b.1))
  let right = boxes.fold(init=0.0, (v, b) => v.max(b.1 + 1))
  let bottom = boxes.fold(init=0.0, (v, b) => v.max(b.2 + h))
  let unit = (frame.width / (right - left)).min(frame.height / bottom)
  let dx = (frame.width - unit * (right - left)) / 2
  let dy = (frame.height - unit * bottom) / 2
  boxes.map(b => {
    (
      b.0,
      geometry_in_parent(
        dx + (b.1 - left) * unit,
        dy + b.2 * unit,
        unit,
        h * unit,
        0,
        false,
        false,
        frame.matrix,
      ),
    )
  })
}
