///|
let math_uri = "http://schemas.openxmlformats.org/officeDocument/2006/math"

///|
let drawing_math_uri = "http://schemas.microsoft.com/office/drawing/2010/main"

///|
let math_text_reason = "Mathematical text editing requires the expression editor"

///|
fn Tree::math_copy_nodes(
  self : Tree,
  start : Int,
  end : Int,
) -> Set[Int] raise @failure.Failure {
  let result : Set[Int] = Set([])
  for node in self.document.nodes() {
    if node.start < start ||
      node.end > end ||
      node.parent < 0 ||
      self.nodes[node.parent].uri != drawing_uri ||
      self.nodes[node.parent].name != "p" {
      continue
    }
    let source : Ref = { tree: self, node, }
    if source.math_source() is Some((root, _)) {
      let fallback = source.child(
        "Fallback",
        uri="http://schemas.openxmlformats.org/markup-compatibility/2006",
      )
      if fallback
        .map(value => {
          !value.node.attributes.is_empty() ||
          !value.node.text.trim().is_empty() ||
          !self.children.get(value.node.id).unwrap_or([]).is_empty()
        })
        .unwrap_or(false) {
        continue
      }
      ignore(
        root.read_math(@layout.TextStyle::new("Cambria Math", 18, "000000")),
      )
      let stack = [node]
      while stack.pop() is Some(node) {
        result.add(node.id)
        stack.append(self.children.get(node.id).unwrap_or([]))
      }
    }
  }
  result
}

///|
fn Ref::math_source(self : Ref) -> (Ref, String?)? raise @failure.Failure {
  let compatibility = "http://schemas.openxmlformats.org/markup-compatibility/2006"
  let source = if self.node.uri == compatibility &&
    self.node.name == "AlternateContent" {
    let children = self.tree.children.get(self.node.id).unwrap_or([])
    let choices = children.filter(node => {
      node.uri == compatibility && node.name == "Choice"
    })
    guard self.node.attributes.is_empty() &&
      self.node.text.trim().is_empty() &&
      choices is [choice] &&
      children.all(node => {
        node.uri == compatibility && ["Choice", "Fallback"].contains(node.name)
      }) &&
      children.filter(node => node.name == "Fallback").length() <= 1 else {
      @failure.reject(
        "unsupported-math", "Extended mathematical compatibility wrapper",
      )
    }
    let children = self.tree.children.get(choice.id).unwrap_or([])
    guard children is [child] &&
      child.uri == drawing_math_uri &&
      child.name == "m" &&
      choice.text.trim().is_empty() &&
      choice.attributes.length() == 1 &&
      choice.attribute("Requires") ==
      Some(child.qualified.split(":").head().unwrap().to_owned()) else {
      @failure.reject(
        "unsupported-math", "Unsupported mathematical compatibility choice",
      )
    }
    { tree: self.tree, node: child, }
  } else if self.node.uri == drawing_math_uri && self.node.name == "m" {
    self
  } else {
    return None
  }
  guard source.node.attributes.is_empty() &&
    source.node.text.trim().is_empty() &&
    source.tree.children.get(source.node.id).unwrap_or([]) is [root] &&
    root.uri == math_uri else {
    @failure.reject(
      "unsupported-math", "DrawingML math requires one OMML expression",
    )
  }
  if root.name == "oMath" {
    return Some(({ tree: source.tree, node: root, }, None))
  }
  guard root.name == "oMathPara" &&
    root.attributes.is_empty() &&
    root.text.trim().is_empty() else {
    @failure.reject("unsupported-math", "Unsupported mathematical paragraph")
  }
  let children = source.tree.children.get(root.id).unwrap_or([])
  let expressions = children.filter(node => {
    node.uri == math_uri && node.name == "oMath"
  })
  let properties = children.filter(node => {
    node.uri == math_uri && node.name == "oMathParaPr"
  })
  guard expressions is [expression] &&
    properties.length() <= 1 &&
    children.length() == 1 + properties.length() else {
    @failure.reject(
      "unsupported-math", "Mathematical paragraph requires one expression",
    )
  }
  let mut align = "center"
  if properties is [properties] {
    let values = source.tree.children.get(properties.id).unwrap_or([])
    guard properties.attributes.is_empty() &&
      properties.text.trim().is_empty() &&
      values.length() <= 1 else {
      @failure.reject(
        "unsupported-math", "Extended mathematical paragraph properties",
      )
    }
    if values is [value] {
      guard value.uri == math_uri &&
        value.name == "jc" &&
        value.attributes.length() == 1 &&
        value.text.is_empty() &&
        source.tree.children.get(value.id).unwrap_or([]).is_empty() &&
        value.attribute("val", uri=math_uri) is Some(location) &&
        ["left", "center", "centerGroup", "right"].contains(location) else {
        @failure.reject(
          "unsupported-math", "Unsupported mathematical paragraph alignment",
        )
      }
      align = if location == "centerGroup" { "center" } else { location }
    }
  }
  Some(({ tree: source.tree, node: expression, }, Some(align)))
}

///|
fn Ref::read_math(
  self : Ref,
  base : @layout.TextStyle,
) -> @layout.MathFormula raise @failure.Failure {
  let nodes : Map[Int, @xml.Node] = Map([])
  let children : Map[Int, Array[Int]] = Map([])
  let stack = [self.node]
  while stack.pop() is Some(node) {
    guard nodes.length() < 2048 else {
      @failure.reject("limit-exceeded", "Mathematical XML exceeds node budget")
    }
    nodes[node.id] = node
    let nested = self.tree.children.get(node.id).unwrap_or([])
    children[node.id] = nested.map(node => node.id)
    stack.append(nested)
  }
  @omml.read(
    nodes,
    children,
    self.node.id,
    {
      ..base,
      font: "Cambria Math",
      underline: false,
      strike: false,
      highlight: "",
      script: "baseline",
      spacing: 0,
    },
    operator => {
      if "∫∬∭∮∯∰".contains(operator) {
        "subSup"
      } else {
        "undOvr"
      }
    },
  )
}
