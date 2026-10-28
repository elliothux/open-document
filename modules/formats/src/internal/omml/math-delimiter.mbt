///|
fn MathRead::delimited(
  self : MathRead,
  tree : Tree,
  id : Int32,
  depth : Int32,
) -> @layout.MathExpression raise @failure.Failure {
  let children = tree.math_children(id, ["dPr", "e"])
  let properties = children.filter(id => tree.nodes[id].name == "dPr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated delimiter properties")
  }
  let values : Map[String, String] = {
    "begChr": "(",
    "endChr": ")",
    "sepChr": "|",
  }
  if properties is [properties] {
    let seen : Set[String] = Set([])
    for
      item in tree.math_children(properties, [
        "begChr", "endChr", "sepChr", "grow", "shp",
      ]) {
      let node = tree.nodes[item]
      guard !seen.contains(node.name) &&
        tree.children[item].is_empty() &&
        node.text.is_empty() else {
        @failure.reject("unsupported-math", "Invalid delimiter properties")
      }
      seen.add(node.name)
      let value = node.attribute("val", uri=math_uri)
      if node.name == "grow" {
        guard (
            node.attributes.is_empty() ||
            (node.attributes.length() == 1 && value is Some(_))
          ) &&
          (value is None || value is Some("1" | "true" | "on")) else {
          @failure.reject(
            "unsupported-math", "Only growing delimiters are supported",
          )
        }
      } else {
        guard node.attributes.length() == 1 && value is Some(value) else {
          @failure.reject(
            "unsupported-math", "Missing delimiter property value",
          )
        }
        if node.name == "shp" {
          guard value == "centered" else {
            @failure.reject(
              "unsupported-math", "Only centered delimiters are supported",
            )
          }
        } else {
          values[node.name] = value
        }
      }
    }
  }
  let arguments = children.filter(id => tree.nodes[id].name == "e")
  guard arguments.length() >= 1 && arguments.length() <= 64 else {
    @failure.reject(
      "unsupported-math", "Delimiter requires one to 64 arguments",
    )
  }
  Delimited(
    values["begChr"],
    values["endChr"],
    // A single argument has no visible separator or LaTeX middle token.
    if arguments.length() == 1 {
      "|"
    } else {
      values["sepChr"]
    },
    ReadOnlyArray::from_array(
      arguments.map(id => self.sequence(tree, id, depth + 1)),
    ),
  )
}
