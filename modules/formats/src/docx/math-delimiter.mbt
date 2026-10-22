///|
fn MathRead::delimited(
  self : MathRead,
  tree : WordTree,
  id : Int,
  depth : Int,
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

///|
fn MathLatex::delimiter_boundary(self : MathLatex) -> Bool {
  ["middle", "right"].contains(self.peek_command())
}

///|
fn MathLatex::delimiter_char(self : MathLatex) -> String raise @failure.Failure {
  self.space()
  let ch = self.take()
  let value = if ch == '\\' {
    match self.command() {
      "lbrace" => "{"
      "rbrace" => "}"
      "langle" => "⟨"
      "rangle" => "⟩"
      "lfloor" => "⌊"
      "rfloor" => "⌋"
      "lceil" => "⌈"
      "rceil" => "⌉"
      "vert" | "lvert" | "rvert" => "|"
      "Vert" | "lVert" | "rVert" => "‖"
      "" =>
        match self.take() {
          '{' => "{"
          '}' => "}"
          '|' => "‖"
          _ => self.invalid()
        }
      _ => self.invalid()
    }
  } else if ch == '.' {
    ""
  } else if ch == '<' {
    "⟨"
  } else if ch == '>' {
    "⟩"
  } else {
    ch.to_string()
  }
  guard value.is_empty() ||
    (value.length() == 1 && "()[]{}|‖⌈⌉⌊⌋⟨⟩".contains(value)) else {
    self.invalid()
  }
  value
}

///|
fn MathLatex::delimiter(
  self : MathLatex,
  depth : Int,
) -> @layout.MathExpression raise @failure.Failure {
  let open = self.delimiter_char()
  let arguments : Array[@layout.MathExpression] = []
  let mut separator : String? = None
  for ;; {
    arguments.push(self.sequence(depth + 1, delimited=true))
    guard arguments.length() <= 64 else {
      @failure.reject("limit-exceeded", "Delimiter exceeds 64 arguments")
    }
    guard self.take() == '\\' else { self.invalid() }
    let boundary = self.command()
    guard boundary == "right" || boundary == "middle" else { self.invalid() }
    let value = self.delimiter_char()
    if boundary == "right" {
      return Delimited(
        open,
        value,
        separator.unwrap_or("|"),
        ReadOnlyArray::from_array(arguments),
      )
    }
    guard separator.map(before => before == value).unwrap_or(true) else {
      self.invalid()
    }
    separator = Some(value)
  }
}

///|
fn math_latex_delimiter(value : String) -> String {
  match value {
    "" => "."
    "{" => "\\{"
    "}" => "\\}"
    "‖" => "\\Vert "
    "⟨" => "\\langle "
    "⟩" => "\\rangle "
    "⌊" => "\\lfloor "
    "⌋" => "\\rfloor "
    "⌈" => "\\lceil "
    "⌉" => "\\rceil "
    _ => value
  }
}
