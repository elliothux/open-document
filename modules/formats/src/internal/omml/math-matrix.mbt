///|
fn matrix_grid(
  columns : Array[String],
  rows : Array[Array[@layout.MathExpression?]],
) -> (
  ReadOnlyArray[String],
  ReadOnlyArray[ReadOnlyArray[@layout.MathExpression?]],
) raise @failure.Failure {
  guard !rows.is_empty() &&
    rows.length() <= 64 &&
    columns.length() <= 64 &&
    rows.iter().all(row => row.length() <= 64) else {
    @failure.reject("limit-exceeded", "Matrix exceeds 64 rows or columns")
  }
  let width = rows.fold(init=columns.length(), (value, row) => {
    value.max(row.length())
  })
  guard width >= 1 && rows.length() * width <= 256 else {
    @failure.reject("limit-exceeded", "Matrix exceeds 256 cells")
  }
  while columns.length() < width {
    columns.push("center")
  }
  for row in rows {
    while row.length() < width {
      row.push(None)
    }
  }
  (
    ReadOnlyArray::from_array(columns),
    ReadOnlyArray::from_array(rows.map(row => ReadOnlyArray::from_array(row))),
  )
}

///|
fn Tree::matrix_property(
  self : Tree,
  id : Int32,
) -> String raise @failure.Failure {
  let node = self.nodes[id]
  guard self.children[id].is_empty() && node.text.is_empty() else {
    @failure.reject("unsupported-math", "Extended matrix property")
  }
  if node.name == "plcHide" && node.attributes.is_empty() {
    return "1"
  }
  guard node.attributes.length() == 1 &&
    node.attribute("val", uri=math_uri) is Some(value) else {
    @failure.reject("unsupported-math", "Missing matrix property value")
  }
  value
}

///|
fn Tree::matrix_columns(
  self : Tree,
  id : Int32,
) -> Array[String] raise @failure.Failure {
  let groups = self.math_children(id, ["mc"])
  guard !groups.is_empty() && groups.length() <= 64 else {
    @failure.reject("unsupported-math", "Matrix requires bounded column groups")
  }
  let columns : Array[String] = []
  for group in groups {
    let properties = self.math_children(group, ["mcPr"])
    guard properties.length() <= 1 else {
      @failure.reject("unsupported-math", "Repeated matrix column properties")
    }
    let values : Map[String, String] = Map([])
    if properties is [properties] {
      for item in self.math_children(properties, ["count", "mcJc"]) {
        let name = self.nodes[item].name
        guard !values.contains(name) else {
          @failure.reject("unsupported-math", "Repeated matrix column property")
        }
        values[name] = self.matrix_property(item)
      }
    }
    let value = values.get("count").unwrap_or("1")
    guard !value.is_empty() &&
      value.length() <= 20 &&
      value.iter().all(ch => ch.is_ascii_digit()) else {
      @failure.reject("unsupported-math", "Invalid matrix column count")
    }
    let mut count = 0
    for ch in value {
      count = count * 10 + ch.to_int() - 48
      guard count <= 64 else {
        @failure.reject("limit-exceeded", "Matrix exceeds 64 columns")
      }
    }
    let alignment = values.get("mcJc").unwrap_or("center")
    guard count > 0 && ["left", "center", "right"].contains(alignment) else {
      @failure.reject(
        "unsupported-math", "Unsupported matrix column properties",
      )
    }
    guard count <= 64 - columns.length() else {
      @failure.reject("limit-exceeded", "Matrix exceeds 64 columns")
    }
    for _ in 0..<count {
      columns.push(alignment)
    }
  }
  columns
}

///|
fn MathRead::matrix(
  self : MathRead,
  tree : Tree,
  id : Int32,
  depth : Int32,
) -> @layout.MathExpression raise @failure.Failure {
  let children = tree.math_children(id, ["mPr", "mr"])
  let properties = children.filter(id => tree.nodes[id].name == "mPr")
  guard properties.length() <= 1 else {
    @failure.reject("unsupported-math", "Repeated matrix properties")
  }
  let mut base = "center"
  let mut columns : Array[String] = []
  let mut control : @layout.TextStyle? = None
  if properties is [properties] {
    let seen : Set[String] = Set([])
    for
      item in tree.math_children(properties, [
        "baseJc", "plcHide", "rSpRule", "cGpRule", "rSp", "cSp", "cGp", "mcs", "ctrlPr",
      ]) {
      let name = tree.nodes[item].name
      guard !seen.contains(name) else {
        @failure.reject("unsupported-math", "Repeated matrix property")
      }
      seen.add(name)
      if name == "mcs" {
        columns = tree.matrix_columns(item)
        continue
      }
      if name == "ctrlPr" {
        let node = tree.nodes[item]
        guard node.attributes.is_empty() &&
          node.text.trim().is_empty() &&
          tree.children[item] is [properties] &&
          [word_uri, drawing_uri].contains(tree.nodes[properties].uri) &&
          tree.nodes[properties].name == "rPr" else {
          @failure.reject(
            "unsupported-math", "Matrix control requires complete Word run properties",
          )
        }
        control = Some(tree.fraction_style(properties, self.base))
        continue
      }
      let value = tree.matrix_property(item)
      if name == "baseJc" {
        guard ["top", "center", "bottom"].contains(value) else {
          @failure.reject("unsupported-math", "Unsupported matrix baseline")
        }
        base = value
      } else if name == "plcHide" {
        guard ["0", "false", "off"].contains(value) else {
          @failure.reject(
            "unsupported-math", "Hidden matrix placeholders require support",
          )
        }
      } else {
        guard !value.is_empty() &&
          value.length() <= 20 &&
          value.iter().all(ch => ch == '0') else {
          @failure.reject(
            "unsupported-math", "Custom matrix spacing requires support",
          )
        }
      }
    }
  }
  let native_rows = children.filter(id => tree.nodes[id].name == "mr")
  guard native_rows.length() >= 1 && native_rows.length() <= 64 else {
    @failure.reject("limit-exceeded", "Matrix requires one to 64 rows")
  }
  let rows : Array[Array[@layout.MathExpression?]] = []
  let inherited = self.base
  defer {
    self.base = inherited
  }
  if control is Some(style) {
    self.appearance(style)
    self.base = style
  }
  for row in native_rows {
    let cells = tree.math_children(row, ["e"])
    guard !cells.is_empty() && cells.length() <= 64 else {
      @failure.reject("limit-exceeded", "Matrix requires one to 64 columns")
    }
    rows.push(
      cells.map(cell => {
        if tree.children[cell].is_empty() {
          ignore(tree.math_children(cell, []))
          None
        } else {
          Some(self.sequence(tree, cell, depth + 1))
        }
      }),
    )
  }
  let (columns, rows) = matrix_grid(columns, rows)
  for row in rows {
    for cell in row {
      if cell is None {
        self.node(depth + 1)
      }
    }
  }
  Matrix(base, columns, rows)
}
