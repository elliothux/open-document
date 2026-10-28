///|
fn MathRead::equation_array(
  self : MathRead,
  tree : Tree,
  id : Int32,
  depth : Int32,
) -> @layout.MathExpression raise @failure.Failure {
  let children = tree.math_children(id, ["eqArrPr", "e"])
  let properties = children.filter(id => tree.nodes[id].name == "eqArrPr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated equation array properties")
  }
  let mut base = "center"
  let inherited = self.base
  defer {
    self.base = inherited
  }
  if properties is [properties] {
    let seen : Set[String] = Set([])
    for
      item in tree.math_children(properties, [
        "baseJc", "maxDist", "objDist", "rSp", "rSpRule", "ctrlPr",
      ]) {
      let name = tree.nodes[item].name
      guard !seen.contains(name) else {
        @failure.reject("unsupported-math", "Repeated equation array property")
      }
      seen.add(name)
      if name == "ctrlPr" {
        let node = tree.nodes[item]
        guard node.attributes.is_empty() &&
          node.text.trim().is_empty() &&
          tree.children[item] is [properties] &&
          [word_uri, drawing_uri].contains(tree.nodes[properties].uri) &&
          tree.nodes[properties].name == "rPr" else {
          @failure.reject(
            "unsupported-math", "Unsupported equation array control properties",
          )
        }
        let style = tree.fraction_style(properties, self.base)
        self.appearance(style)
        self.base = style
        continue
      }
      let value = tree.matrix_property(item)
      if name == "baseJc" {
        guard ["top", "center", "bottom"].contains(value) else {
          @failure.reject(
            "unsupported-math", "Unsupported equation array baseline",
          )
        }
        base = value
      } else {
        guard ["0", "false", "off"].contains(value) &&
          (["maxDist", "objDist"].contains(name) || value == "0") else {
          @failure.reject(
            "unsupported-math", "Custom equation array spacing requires support",
          )
        }
      }
    }
  }
  let native_rows = children.filter(id => tree.nodes[id].name == "e")
  guard native_rows.length() >= 1 && native_rows.length() <= 64 else {
    @failure.reject("limit-exceeded", "Equation array requires one to 64 rows")
  }
  let rows = native_rows.map(row => {
    let terms = tree.math_children(row, [
      "r", "f", "sSub", "sSup", "sSubSup", "rad", "d", "nary", "m", "eqArr",
    ])
    let cells : Array[@layout.MathExpression?] = []
    let mut current : Array[@layout.MathExpression] = []
    fn flush() {
      cells.push(
        match current {
          [] => None
          [value] => Some(value)
          _ => Some(Row(ReadOnlyArray::from_array(current)))
        },
      )
      current = []
    }
    for term in terms {
      let value = self.term(tree, term, depth + 1)
      if value is Text(text) {
        for index, part in text.split("&") {
          if index > 0 {
            flush()
          }
          if !part.is_empty() {
            current.push(Text(part.to_owned()))
          }
        }
      } else {
        current.push(value)
      }
      guard cells.length() < 64 else {
        @failure.reject(
          "limit-exceeded", "Equation row exceeds 64 alignment segments",
        )
      }
    }
    flush()
    ReadOnlyArray::from_array(cells)
  })
  EquationArray(base, ReadOnlyArray::from_array(rows))
}

///|
fn equation_cell_markup(
  value : @layout.MathExpression,
  style : @layout.TextStyle?,
  drawing~ : Bool,
) -> String raise @failure.Failure {
  match value {
    Text(text) => {
      guard !text.contains("&") else {
        @failure.reject(
          "unsupported-math", "Literal ampersands in equation alignment segments require normal text support",
        )
      }
      math_expression_markup(value, style, drawing~)
    }
    Row(children) =>
      children
      .map(value => equation_cell_markup(value, style, drawing~))
      .join("")
    _ => math_expression_markup(value, style, drawing~)
  }
}
