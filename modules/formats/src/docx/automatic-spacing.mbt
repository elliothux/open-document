///|
fn spacing_auto_flag(
  node : @xml.Node,
  name : String,
  fallback : Bool,
) -> Bool raise @failure.Failure {
  match node.attribute(name, uri=word_uri) {
    None => fallback
    Some("1" | "true" | "on") => true
    Some("0" | "false" | "off") => false
    _ => @failure.reject("invalid-style", "Invalid automatic paragraph spacing")
  }
}

///|
fn Styles::automatic_spacing(
  self : Styles,
  tree : WordTree,
  paragraph : Int32,
) -> (Bool, Bool) raise @failure.Failure {
  let sources : Array[(WordTree, Int32)] = []
  if self.tree is Some(source) {
    if source
      .child(0, "docDefaults")
      .bind(id => source.child(id, "pPrDefault"))
      .bind(id => source.child(id, "pPr"))
      is Some(id) {
      sources.push((source, id))
    }
    let key = tree
      .contextual_style(paragraph)
      .unwrap_or(self.default_paragraph.unwrap_or(""))
    if !key.is_empty() {
      for style in self.chain(key, []) {
        if source.child(style, "pPr") is Some(id) {
          sources.push((source, id))
        }
      }
    }
  }
  if tree.child(paragraph, "pPr") is Some(id) {
    sources.push((tree, id))
  }
  let mut before = false
  let mut after = false
  for (source, id) in sources {
    if source.child(id, "spacing") is Some(id) {
      before = spacing_auto_flag(source.nodes[id], "beforeAutospacing", before)
      after = spacing_auto_flag(source.nodes[id], "afterAutospacing", after)
    }
  }
  (before, after)
}

///|
fn Styles::apply_automatic_spacing(
  self : Styles,
  tree : WordTree,
  paragraphs : Map[Int32, @layout.Paragraph],
) -> Unit raise @failure.Failure {
  let original = paragraphs.copy()
  for id, paragraph in original {
    let (before, after) = self.automatic_spacing(tree, id)
    if !before && !after {
      continue
    }
    let parent = tree.nodes[id].parent
    let content = tree.children[parent].filter(id => {
      tree.nodes[id].uri == word_uri &&
      ["p", "tbl"].contains(tree.nodes[id].name)
    })
    let mut index = 0
    while content[index] != id {
      index += 1
    }
    let same_number = fn(other : Int32?) {
      guard other is Some(other) &&
        original.get(other) is Some(previous) &&
        paragraph.marker.bind(m => m.numbering).map(n => n.instance)
        is Some(number) &&
        previous.marker.bind(m => m.numbering).map(n => n.instance) ==
        Some(number) else {
        return false
      }
      tree.contextual_style(id).unwrap_or(self.default_paragraph.unwrap_or("")) ==
      tree
      .contextual_style(other)
      .unwrap_or(self.default_paragraph.unwrap_or(""))
    }
    // ONLYOFFICE ParaSpacing uses 14 pt, with story/cell and list-neighbor exceptions.
    paragraphs[id] = {
      ..paragraph,
      before: if before {
        if index == 0 || same_number(content.get(index - 1)) {
          0
        } else {
          14
        }
      } else {
        paragraph.before
      },
      after: if after {
        if (tree.nodes[parent].name == "tc" && index == content.length() - 1) ||
          same_number(content.get(index + 1)) {
          0
        } else {
          14
        }
      } else {
        paragraph.after
      },
    }
  }
}
