///|
fn shape_tree(tree : Tree) -> @xml.Node raise @failure.Failure {
  let root = tree.document.nodes()[0]
  tree.required(
    tree.required(root.id, "cSld", uri=presentation_uri).id,
    "spTree",
    uri=presentation_uri,
  )
}

///|
fn placeholder(source : Ref) -> (String, String)? raise @failure.Failure {
  let nv = match source.child("nvSpPr", uri=presentation_uri) {
    Some(value) => Some(value)
    None => source.child("nvPicPr", uri=presentation_uri)
  }
  nv
  .bind(item => item.child("nvPr", uri=presentation_uri))
  .bind(item => item.child("ph", uri=presentation_uri))
  .map(item => {
    let index = item.node.attribute("idx").unwrap_or("0")
    guard !index.is_empty() && index.iter().all(c => c >= '0' && c <= '9') else {
      @failure.reject("malformed-pptx", "Invalid placeholder index")
    }
    (
      item.node.attribute("type").unwrap_or("body"),
      number(index, 0, 4294967295).to_int64().to_string(),
    )
  })
}

///|
fn matching(
  tree : Tree,
  ph : (String, String),
  master : Bool,
) -> Ref? raise @failure.Failure {
  let objects = tree.children.get(shape_tree(tree).id).unwrap_or([])
  let normalize = fn(kind : String) {
    if kind == "ctrTitle" {
      "title"
    } else {
      kind
    }
  }
  let candidates : Array[(Ref, (String, String))] = []
  for node in objects {
    let source : Ref = { tree, node, }
    if placeholder(source) is Some(value) {
      candidates.push((source, value))
    }
  }
  if candidates
    .iter()
    .find_first(item => {
      normalize(item.1.0) == normalize(ph.0) && item.1.1 == ph.1
    })
    is Some(item) {
    return Some(item.0)
  }
  if master ||
    ["title", "ctrTitle", "sldNum", "dt", "ftr", "hdr"].contains(ph.0) {
    return candidates
      .iter()
      .find_first(item => normalize(item.1.0) == normalize(ph.0))
      .map(item => item.0)
  }
  // ONLYOFFICE falls back to the single body placeholder when the index differs.
  let bodies = candidates.filter(item => item.1.0 == "body")
  if ph.0 == "body" && bodies is [item] {
    Some(item.0)
  } else {
    None
  }
}

///|
fn read_object(
  opc : @opc.Package,
  theme : Theme,
  chain : Array[Ref],
  master : Tree,
  defaults : Ref?,
  parent : @layout.Matrix,
  reason : String,
  parts : Map[String, @xml.Document],
) -> Object raise @failure.Failure {
  let source = chain[0]
  let nv_name = match source.node.name {
    "pic" => "nvPicPr"
    "grpSp" => "nvGrpSpPr"
    "graphicFrame" => "nvGraphicFramePr"
    "cxnSp" => "nvCxnSpPr"
    _ => "nvSpPr"
  }
  let nv = source.child(nv_name, uri=presentation_uri)
  let identity = nv.bind(item => item.child("cNvPr", uri=presentation_uri))
  let id = if identity is Some(item) {
    source_identity(item.node.attribute("id").unwrap_or(""))
  } else if ["sp", "pic", "grpSp", "graphicFrame", "cxnSp"].contains(
      source.node.name,
    ) {
    @failure.reject(
      "malformed-pptx",
      "Missing object identity",
      part=source.tree.part,
    )
  } else {
    "unknown-\{source.node.id}"
  }
  let name = identity
    .bind(item => item.node.attribute("name"))
    .unwrap_or(source.node.qualified)
  guard name.length() <= 1024 else {
    @failure.reject("limit-exceeded", "Object name exceeds budget")
  }
  let properties = children(chain, "spPr", uri=presentation_uri)
  let geometry = if source.node.name == "graphicFrame" {
    let transforms = source.child("xfrm", uri=presentation_uri)
    transforms.map(item => {
      let off = item.child("off")
      let ext = item.child("ext")
      let x = number(
          off.bind(item => item.node.attribute("x")).unwrap_or("0"),
          -182880000,
          182880000,
        ) /
        12700
      let y = number(
          off.bind(item => item.node.attribute("y")).unwrap_or("0"),
          -182880000,
          182880000,
        ) /
        12700
      let width = number(
          ext.bind(item => item.node.attribute("cx")).unwrap_or("0"),
          1,
          182880000,
        ) /
        12700
      let height = number(
          ext.bind(item => item.node.attribute("cy")).unwrap_or("0"),
          1,
          182880000,
        ) /
        12700
      geometry_in_parent(x, y, width, height, 0, false, false, parent)
    })
  } else {
    geometry(chain, parent, source.node.name == "grpSp")
  }
  let mut diagnostic = ""
  let mut text_reason = ""
  let mut read_only = reason
  let kind = match source.node.name {
    "sp" => "shape"
    "pic" => "image"
    "grpSp" => "group"
    _ => "unsupported"
  }
  let preset = attribute(children(properties, "prstGeom"), "prst").unwrap_or(
    "rect",
  )
  let adjustments = read_shape_adjustments(
    children(properties, "prstGeom").get(0),
    preset,
  ) catch {
    @failure.Failure(code="unsupported-geometry", message~, ..) => {
      diagnostic = message
      (0.0, 0.0)
    }
    error => raise error
  }
  if kind == "unsupported" ||
    !supported_shape(preset) ||
    !children(properties, "custGeom").is_empty() {
    diagnostic = "Unsupported object geometry: " +
      source.node.name +
      "/" +
      preset
  }
  for item in properties {
    for child in item.tree.children.get(item.node.id).unwrap_or([]) {
      if ["effectDag", "effectLst", "scene3d", "sp3d"].contains(child.name) &&
        !item.tree.children.get(child.id).unwrap_or([]).is_empty() {
        diagnostic = "Unsupported object effect: " + child.name
      }
    }
  }
  let effects = style_reference(theme, chain, "effect") catch {
    @failure.Failure(code="unsupported-style", message~, ..) => {
      diagnostic = message
      None
    }
    error => raise error
  }
  if effects is Some((effect, _)) {
    for child in effect.tree.children.get(effect.node.id).unwrap_or([]) {
      if child.name != "effectLst" ||
        !effect.tree.children.get(child.id).unwrap_or([]).is_empty() {
        diagnostic = "Unsupported theme effect: " + child.name
      }
    }
  }
  let paint = (fn() raise @failure.Failure {
    let has_fill = properties.any(item => {
      item.tree.children
      .get(item.node.id)
      .unwrap_or([])
      .any(node => {
        ["noFill", "solidFill", "gradFill", "pattFill", "blipFill", "grpFill"].contains(
          node.name,
        )
      })
    })
    let mut gradient = None
    let (shape_fill, fill_source) = if has_fill {
      let first = properties
        .iter()
        .find_first(item => {
          item.tree.children
          .get(item.node.id)
          .unwrap_or([])
          .any(n => {
            [
              "noFill", "solidFill", "gradFill", "pattFill", "blipFill", "grpFill",
            ].contains(n.name)
          })
        })
        .unwrap()
      if first.child("gradFill") is Some(fill) {
        ignore(paint_fill(first))
        gradient = Some(shape_gradient(fill, theme, None))
        (("", 1.0), None)
      } else {
        (
          fill_rgba(theme, properties),
          solid_fill_source(properties).map(item => (item, None)),
        )
      }
    } else if style_reference(theme, chain, "fill") is Some((item, ph)) {
      match item.node.name {
        "noFill" => (("", 1.0), None)
        "solidFill" =>
          (
            color_rgba(theme, item, placeholder=Some(ph)),
            Some((item, Some(ph))),
          )
        "gradFill" => {
          gradient = Some(shape_gradient(item, theme, Some(ph)))
          (("", 1.0), None)
        }
        _ => @failure.reject("unsupported-style", "Unsupported theme fill")
      }
    } else {
      (("", 1.0), None)
    }
    let lines = children(properties, "ln")
    let placeholder = if style_reference(theme, chain, "ln") is Some((item, ph)) {
      lines.push(item)
      Some(ph)
    } else {
      None
    }
    let stroke = fill_rgba(theme, lines, placeholder~)
    let (join, miter) = line_join(lines)
    let cap = attribute(lines, "cap").unwrap_or("flat")
    ignore(line_cap_code(cap))
    (
      shape_fill.0,
      stroke.0,
      number(attribute(lines, "w").unwrap_or("12700"), 1, 12700000) / 12700,
      line_dash(lines),
      cap,
      join,
      miter,
      shape_fill.1,
      stroke.1,
      fill_source,
      solid_fill_source(lines).map(item => (item, placeholder)),
      gradient,
      (line_end(lines, "headEnd"), line_end(lines, "tailEnd")),
    )
  })() catch {
    @failure.Failure(code~, message~, ..) if code == "unsupported-style" ||
      code == "protected-content" => {
      diagnostic = message
      (
        "",
        "",
        1.0,
        "solid",
        "flat",
        "round",
        8.0,
        1.0,
        1.0,
        None,
        None,
        None,
        (no_line_end(), no_line_end()),
      )
    }
    error => raise error
  }
  let (paragraphs, body, limitation) = read_text(theme, chain, master, defaults) catch {
    @failure.Failure(code~, message~, ..) if code == "unsupported-text" ||
      code == "unsupported-style" => {
      diagnostic = message
      (
        [],
        {
          left: 7.2,
          right: 7.2,
          top: 3.6,
          bottom: 3.6,
          anchor: "t",
          wrap: true,
          fit: "none",
        },
        message,
      )
    }
    error => raise error
  }
  text_reason = limitation
  let mut image : String? = None
  let mut crop = [0.0, 0.0, 0.0, 0.0]
  let mut opacity = 1.0
  if kind == "image" &&
    source.child("blipFill", uri=presentation_uri) is Some(blip_fill) {
    if blip_fill.child("blip") is Some(blip) {
      let embed = blip.node
        .attribute("embed", uri=relationship_uri)
        .unwrap_or("")
      let target = image_target(opc, source.tree.part, embed, parts)
      if target is Some(target) &&
        [Some("image/png"), Some("image/jpeg")].contains(
          image_content_type(opc, target, parts),
        ) {
        image = Some(target)
      } else {
        diagnostic = "Unsupported or external image"
      }
      opacity = image_opacity(blip) catch {
        @failure.Failure(message~, ..) => {
          diagnostic = message
          1.0
        }
      }
    } else {
      diagnostic = "Missing embedded image"
    }
    if blip_fill.child("srcRect") is Some(rect) {
      crop = ["l", "t", "r", "b"].map(key => {
        number(rect.node.attribute(key).unwrap_or("0"), 0, 99999) / 100000
      })
      guard crop[0] + crop[2] < 1 && crop[1] + crop[3] < 1 else {
        @failure.reject("malformed-pptx", "Invalid image crop")
      }
    }
    if blip_fill.child("tile") is Some(_) {
      diagnostic = "Tiled images are unsupported"
    }
  }
  if geometry is None {
    diagnostic = "Object bounds cannot be resolved"
  }
  if !diagnostic.is_empty() {
    read_only = diagnostic
  }
  if !read_only.is_empty() {
    text_reason = read_only
  }
  for
    item in nv
    .map(item => item.tree.children.get(item.node.id).unwrap_or([]))
    .unwrap_or([]) {
    for lock in source.tree.children.get(item.id).unwrap_or([]) {
      if lock.name.has_suffix("Locks") {
        if flag(lock, "noMove") || flag(lock, "noResize") {
          read_only = "Object transform is locked"
        }
        if flag(lock, "noTextEdit") {
          text_reason = "Text is locked"
        }
      }
    }
  }
  {
    id: source.tree.part + "#" + id,
    parent: source.parent_group(),
    name,
    kind,
    source,
    geometry,
    preset,
    adjustments,
    fill: paint.0,
    gradient: paint.11,
    stroke: paint.1,
    line_width: paint.2,
    dash: paint.3,
    cap: paint.4,
    join: paint.5,
    miter: paint.6,
    ends: paint.12,
    fill_alpha: paint.7,
    stroke_alpha: paint.8,
    fill_source: paint.9,
    stroke_source: paint.10,
    image,
    crop,
    opacity,
    paragraphs,
    body,
    read_only,
    text_reason,
    diagnostic,
  }
}

///|
fn read_objects(
  opc : @opc.Package,
  tree : Tree,
  parent_node : Int,
  theme : Theme,
  layout : Tree?,
  master : Tree,
  defaults : Ref?,
  parent : @layout.Matrix,
  reason : String,
  depth : Int,
  output : Array[Object],
  ids : Map[String, Bool],
  parts : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  guard depth <= 16 else {
    @failure.reject("limit-exceeded", "Group depth exceeds 16")
  }
  for node in tree.children.get(parent_node).unwrap_or([]) {
    if ["nvGrpSpPr", "grpSpPr", "extLst"].contains(node.name) {
      continue
    }
    guard ids.length() < 4096 else {
      @failure.reject("limit-exceeded", "Slide objects exceed 4096")
    }
    let source : Ref = { tree, node, }
    let ph = placeholder(source)
    if !reason.is_empty() && ph is Some(_) {
      continue
    }
    let chain = [source]
    if ph is Some(ph) {
      if layout is Some(layout) && matching(layout, ph, false) is Some(item) {
        chain.push(item)
      }
      if tree.part != master.part && matching(master, ph, true) is Some(item) {
        chain.push(item)
      }
    }
    let object = read_object(
      opc, theme, chain, master, defaults, parent, reason, parts,
    )
    guard !ids.contains(object.id) else {
      @failure.reject(
        "malformed-pptx",
        "Duplicate object identity",
        part=tree.part,
      )
    }
    ids[object.id] = true
    if object.kind == "group" && object.geometry is Some(geometry) {
      let first = output.length()
      read_objects(
        opc,
        tree,
        node.id,
        theme,
        None,
        master,
        defaults,
        group_matrix(source, geometry),
        "Group members are read-only",
        depth + 1,
        output,
        ids,
        parts,
      )
      let problem = source.group_problem()
      let blocked = if !object.read_only.is_empty() {
        object.read_only
      } else if !problem.is_empty() {
        problem
      } else {
        output[first:]
        .iter()
        .find_first(child => {
          !child.diagnostic.is_empty() ||
          child.read_only == "Object transform is locked"
        })
        .map(child => {
          if child.diagnostic.is_empty() {
            child.read_only
          } else {
            child.diagnostic
          }
        })
        .unwrap_or("")
      }
      output.push({
        ..object,
        read_only: blocked,
        diagnostic: problem,
        text_reason: "Groups do not have a text frame",
      })
    } else {
      output.push(object)
    }
  }
}
