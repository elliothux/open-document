///|
fn WordTree::math_root(self : WordTree, id : Int32) -> Bool {
  let node = self.nodes[id]
  node.uri == math_uri &&
  ["oMath", "oMathPara"].contains(node.name) &&
  node.parent >= 0 &&
  self.nodes[node.parent].uri == word_uri &&
  self.nodes[node.parent].name == "p"
}

///|
fn Session::check_display_math_input(
  self : Session,
  selection : Selection,
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(self.document())
  let range = self.paragraph_range(
    tree,
    selection,
    structural=true,
    fields=true,
    math=true,
    tables=true,
  )
  let positions : Map[Int32, Int32] = Map([])
  for item in docx_texts(tree) {
    let offset = positions.get(item.paragraph).unwrap_or(0)
    let length = inline_text(tree.nodes[item.id]).length()
    positions[item.paragraph] = offset + length
    if tree.nodes[item.id].name != "oMathPara" ||
      !range.paragraphs.contains(item.paragraph) {
      continue
    }
    let start = if item.paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if item.paragraph == range.end.paragraph {
      range.end.offset
    } else {
      2147483647
    }
    guard start <= offset && end >= offset + length else {
      @failure.reject(
        "unsupported-math", "Display math line breaks require block-line layout",
      )
    }
  }
}

///|
fn WordTree::math_source(
  self : WordTree,
  id : Int32,
) -> (Int32, String?) raise @failure.Failure {
  let node = self.nodes[id]
  if node.name == "oMath" {
    return (id, None)
  }
  guard node.name == "oMathPara" &&
    node.uri == math_uri &&
    node.attributes.is_empty() &&
    node.text.trim().is_empty() else {
    @failure.reject("unsupported-math", "Invalid mathematical paragraph")
  }
  let children = self.children[id]
  let expressions = children.filter(id => {
    self.nodes[id].uri == math_uri && self.nodes[id].name == "oMath"
  })
  let properties = children.filter(id => {
    self.nodes[id].uri == math_uri && self.nodes[id].name == "oMathParaPr"
  })
  guard expressions is [expression] &&
    properties.length() <= 1 &&
    children.length() == 1 + properties.length() else {
    @failure.reject(
      "unsupported-math", "Mathematical paragraph requires one expression",
    )
  }
  let mut align = ""
  if properties is [properties] {
    let source = self.nodes[properties]
    guard source.attributes.is_empty() &&
      source.text.trim().is_empty() &&
      self.children[properties].length() <= 1 else {
      @failure.reject(
        "unsupported-math", "Extended mathematical paragraph properties",
      )
    }
    if self.children[properties] is [value] {
      let value = self.nodes[value]
      guard value.uri == math_uri &&
        value.name == "jc" &&
        value.attributes.length() == 1 &&
        self.children[value.id].is_empty() &&
        value.text.is_empty() &&
        value.attribute("val", uri=math_uri) is Some(location) &&
        ["left", "center", "centerGroup", "right"].contains(location) else {
        @failure.reject(
          "unsupported-math", "Invalid mathematical paragraph alignment",
        )
      }
      align = if location == "centerGroup" { "center" } else { location }
    }
  }
  (expression, Some(align))
}

///|
fn Session::math_display_alignment(
  self : Session,
  tree : WordTree,
  id : Int32,
) -> String? raise @failure.Failure {
  let (_, align) = tree.math_source(id)
  guard align == Some("") else { return align }
  let mut align = "center"
  if self.settings_part() is Some(part) {
    let settings = WordTree::new(self.part_xml(part))
    let definitions = settings.order.filter(id => {
      settings.nodes[id].uri == math_uri && settings.nodes[id].name == "defJc"
    })
    guard definitions.length() <= 1 else {
      @failure.reject(
        "unsupported-math", "Repeated default mathematical alignment",
      )
    }
    if definitions is [id] {
      let node = settings.nodes[id]
      guard node.attributes.length() == 1 &&
        node.text.is_empty() &&
        settings.children[id].is_empty() &&
        node.attribute("val", uri=math_uri) is Some(value) &&
        ["left", "center", "centerGroup", "right"].contains(value) else {
        @failure.reject(
          "unsupported-math", "Invalid default mathematical alignment",
        )
      }
      align = if value == "centerGroup" { "center" } else { value }
    }
  }
  Some(align)
}

///|
fn WordTree::math_replacement(
  self : WordTree,
  document : @xml.Document,
  id : Int32,
  expression : String,
) -> String raise @failure.Failure {
  let node = self.nodes[id]
  if node.name != "oMathPara" {
    return expression
  }
  let properties = self.children[id]
    .filter(id => self.nodes[id].name == "oMathParaPr")
    .map(id => self.standalone_markup(document, id))
    .join("")
  structure_opening(node) + properties + expression + "</\{node.qualified}>"
}
