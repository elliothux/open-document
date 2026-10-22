///|
fn MathRead::nary(
  self : MathRead,
  tree : Tree,
  id : Int,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  let children = tree.math_children(id, ["naryPr", "sub", "sup", "e"])
  let properties = children.filter(id => tree.nodes[id].name == "naryPr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated n-ary properties")
  }
  let values : Map[String, String] = {
    "chr": "∫",
    "subHide": "0",
    "supHide": "0",
  }
  if properties is [properties] {
    let seen : Set[String] = Set([])
    for
      item in tree.math_children(properties, [
        "chr", "limLoc", "grow", "subHide", "supHide",
      ]) {
      let node = tree.nodes[item]
      let value = node.attribute("val", uri=math_uri)
      guard !seen.contains(node.name) &&
        tree.children[item].is_empty() &&
        node.text.is_empty() &&
        (
          node.attributes.is_empty() ||
          (node.attributes.length() == 1 && value is Some(_))
        ) else {
        @failure.reject("unsupported-math", "Invalid n-ary property")
      }
      seen.add(node.name)
      if ["grow", "subHide", "supHide"].contains(node.name) {
        let flag = match value {
          None | Some("1" | "true" | "on") => "1"
          Some("0" | "false" | "off") => "0"
          _ => @failure.reject("unsupported-math", "Invalid n-ary flag")
        }
        guard node.name != "grow" || flag == "0" else {
          @failure.reject(
            "unsupported-math", "Growing n-ary source requires support",
          )
        }
        values[node.name] = flag
      } else {
        guard value is Some(value) else {
          @failure.reject("unsupported-math", "Missing n-ary property value")
        }
        values[node.name] = value
      }
    }
  }
  let operator = values["chr"]
  let location = match values.get("limLoc") {
    Some(value) => value
    None => (self.nary_limit)(operator)
  }
  let arguments : Map[String, @layout.MathExpression?] = Map([])
  for name in ["sub", "sup", "e"] {
    let items = children.filter(id => tree.nodes[id].name == name)
    guard items is [item] else {
      @failure.reject(
        "unsupported-math",
        "N-ary requires exactly one " + name + " argument",
      )
    }
    if name != "e" && values[name + "Hide"] == "1" {
      ignore(tree.math_children(item, []))
      arguments[name] = None
    } else {
      arguments[name] = Some(self.sequence(tree, item, depth + 1))
    }
  }
  Nary(
    operator,
    location,
    arguments["sub"],
    arguments["sup"],
    arguments["e"].unwrap(),
  )
}
