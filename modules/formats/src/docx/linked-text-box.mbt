///|
fn linked_box_number(
  node : @xml.Node,
  name : String,
) -> Int64 raise @failure.Failure {
  let value = node.attribute(name).unwrap_or("")
  let number = @string.parse_int64(value[:]) catch { _ => -1L }
  guard !value.is_empty() &&
    value.length() <= 10 &&
    value.iter().all(c => c.is_ascii_digit()) &&
    number >= 0 &&
    number <= 4294967295L else {
    @failure.reject(
      "unsupported-layout", "Invalid linked text box identity or sequence",
    )
  }
  number
}

///|
fn WordTree::linked_text_boxes(
  self : WordTree,
  shape : Int32,
) -> (Array[Int32], Int32)? raise @failure.Failure {
  let first = self.drawing_child(shape, "txbx", uri=word_shape_uri)
  let linked = self.drawing_child(shape, "linkedTxbx", uri=word_shape_uri)
  guard !(first is Some(_) && linked is Some(_)) else {
    @failure.reject(
      "unsupported-layout", "Conflicting text box content and continuation",
    )
  }
  let metadata = if linked is Some(_) { linked } else { first }
  guard metadata is Some(metadata) &&
    self.nodes[metadata].attribute("id") is Some(_) else {
    guard linked is None else {
      @failure.reject(
        "unsupported-layout", "Linked text box requires an identity",
      )
    }
    return None
  }
  let identity = linked_box_number(self.nodes[metadata], "id")
  let nodes = self.descendants(0)
  if linked is None &&
    !nodes.any(id => {
      let node = self.nodes[id]
      node.uri == word_shape_uri &&
      node.name == "linkedTxbx" &&
      node.attribute("id") is Some(_) &&
      linked_box_number(node, "id") == identity
    }) {
    return None
  }
  let members : Map[Int32, Int32] = Map([])
  let mut sequence = 0
  for id in nodes {
    let node = self.nodes[id]
    if node.uri != word_shape_uri ||
      !["txbx", "linkedTxbx"].contains(node.name) ||
      node.attribute("id") is None {
      continue
    }
    if linked_box_number(node, "id") != identity {
      continue
    }
    guard self.nodes[node.parent].uri == word_shape_uri &&
      self.nodes[node.parent].name == "wsp" else {
      @failure.reject(
        "unsupported-layout", "Linked text box metadata requires a Word shape",
      )
    }
    let index = if node.name == "txbx" {
      0L
    } else {
      linked_box_number(node, "seq")
    }
    guard index < 64 &&
      (node.name == "txbx" || index > 0) &&
      !members.contains(index.to_int()) &&
      node.attributes.all(a => {
        a.uri.is_empty() &&
        (a.name == "id" || (node.name == "linkedTxbx" && a.name == "seq"))
      }) &&
      (
        node.name == "txbx" ||
        (node.text.trim().is_empty() && self.children[id].is_empty())
      ) else {
      @failure.reject(
        "unsupported-layout", "Duplicate or unsupported text box chain member",
      )
    }
    members[index.to_int()] = node.parent
    if id == metadata {
      sequence = index.to_int()
    }
  }
  if linked is None && members.length() == 1 {
    return None
  }
  guard members.length() > 1 && members.length() <= 64 else {
    @failure.reject(
      "unsupported-layout", "Text box chain requires one origin and contiguous sequences",
    )
  }
  let ordered = []
  for index in 0..<members.length() {
    guard members.get(index) is Some(item) else {
      @failure.reject(
        "unsupported-layout", "Text box chain requires contiguous sequences",
      )
    }
    ordered.push(item)
  }
  Some((ordered, sequence))
}

///|
fn Session::linked_shape_text(
  self : Session,
  tree : WordTree,
  members : Array[Int32],
  sequence : Int32,
) -> @layout.DrawingContent raise @failure.Failure {
  guard tree.part == self.main else {
    @failure.reject(
      "unsupported-layout", "Linked header and footer text boxes require support",
    )
  }
  let origin = tree
    .drawing_child(members[0], "txbx", uri=word_shape_uri)
    .unwrap()
  let text = self.shape_text(tree, members[0], origin, linked=true)
  guard tree.descendants(origin).all(id => tree.nodes[id].name != "pBdr") &&
    text.paragraphs().all(p => !p.keepLines && !p.keepNext) else {
    @failure.reject(
      "unsupported-layout", "Linked text box paragraph borders and keep rules require support",
    )
  }
  let areas : Array[(Double, Double)] = []
  let mut paint : @layout.BasicShape? = None
  let mut current : @layout.DrawingTextBoxProperties? = None
  for index in 0..<=sequence {
    let shape = members[index]
    let mut drawing = shape
    while drawing >= 0 &&
          !(tree.nodes[drawing].uri == word_uri &&
          tree.nodes[drawing].name == "drawing") {
      drawing = tree.nodes[drawing].parent
    }
    guard drawing >= 0 else {
      @failure.reject(
        "unsupported-layout", "Linked text box requires a drawing",
      )
    }
    let (_, data) = tree.drawing_data(drawing)
    guard tree.children[data.id] is [found] && found == shape else {
      @failure.reject(
        "unsupported-layout", "Linked text box must own its drawing",
      )
    }
    let frame = tree.read_basic_shape(drawing, data.id)
    let properties = tree.text_box_properties(shape)
    guard frame.content is @layout.Shape(shape_paint) &&
      shape_paint.preset == "rect" &&
      frame.anchor is Some({ wrapping: "none", .. }) &&
      properties.wrap &&
      properties.anchor == "t" else {
      @failure.reject(
        "unsupported-layout", "Linked text boxes require unwrapped horizontal top-aligned rectangles",
      )
    }
    areas.push(
      (
        frame.width - properties.insets[1] - properties.insets[3],
        frame.height - properties.insets[0] - properties.insets[2],
      ),
    )
    paint = Some(shape_paint)
    current = Some(properties)
  }
  @layout.TextBox(
    paint.unwrap(),
    @layout.DrawingTextBox::new(
      text
      .paragraphs()
      .map(p => { ..p, readOnlyReason: "protected-content:linked-text-box", }),
      current.unwrap().insets,
      "t",
      true,
      true,
      flowFrames=areas,
    ),
  )
}
