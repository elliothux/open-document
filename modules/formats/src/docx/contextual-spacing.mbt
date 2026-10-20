///|
fn WordTree::contextual_style(self : WordTree, paragraph : Int) -> String? {
  self.child(paragraph, "pPr").bind(id => self.value(id, "pStyle"))
}

///|
fn Styles::contextual_spacing(
  self : Styles,
  tree : WordTree,
  paragraph : Int,
) -> Bool raise @failure.Failure {
  let mut enabled = false
  if self.tree is Some(source) {
    if source
      .child(0, "docDefaults")
      .bind(id => source.child(id, "pPrDefault"))
      .bind(id => source.child(id, "pPr"))
      is Some(id) {
      enabled = source.character_toggle(id, "contextualSpacing", enabled, false)
    }
    let key = match tree.contextual_style(paragraph) {
      Some(key) => Some(key)
      None => self.default_paragraph
    }
    if key is Some(key) {
      for style in self.chain(key, []) {
        if source.child(style, "pPr") is Some(id) {
          enabled = source.character_toggle(
            id, "contextualSpacing", enabled, false,
          )
        }
      }
    }
  }
  tree
  .child(paragraph, "pPr")
  .map(id => tree.character_toggle(id, "contextualSpacing", enabled, false))
  .unwrap_or(enabled)
}

///|
// Resolve native neighbor rules before portable layout; formatting queries keep declared spacing.
fn Styles::apply_contextual_spacing(
  self : Styles,
  tree : WordTree,
  paragraphs : Map[Int, @layout.Paragraph],
) -> Unit raise @failure.Failure {
  let keys : Map[Int, String?] = Map([])
  let enabled : Map[Int, Bool] = Map([])
  for id, _ in paragraphs {
    keys[id] = tree.contextual_style(id)
    enabled[id] = self.contextual_spacing(tree, id)
  }
  let neighbors : Map[Int, (Int?, Int?)] = Map([])
  for _, children in tree.children {
    let content = children.filter(id => {
      tree.nodes[id].uri == word_uri &&
      ["p", "tbl"].contains(tree.nodes[id].name)
    })
    for index, id in content {
      neighbors[id] = (content.get(index - 1), content.get(index + 1))
    }
  }
  for id in tree.order {
    if tree.nodes[id].uri != word_uri || tree.nodes[id].name != "tbl" {
      continue
    }
    for row_index, row in tree.table_children(id, "tr") {
      let cells = tree.table_children(row, "tc")
      for index, cell in cells {
        let content = tree.table_children(cell, "p")
        if content.get(0) is Some(first) &&
          neighbors.get(first) is Some((None, next)) {
          let previous = if index == 0 && row_index == 0 {
            neighbors.get(id).bind(pair => pair.0)
          } else {
            cells
            .get(index - 1)
            .bind(cell => tree.table_children(cell, "p").last())
          }
          neighbors[first] = (previous, next)
        }
        if content.last() is Some(last) &&
          neighbors.get(last) is Some((previous, None)) {
          let next = cells
            .get(index + 1)
            .bind(cell => tree.table_children(cell, "p").get(0))
          neighbors[last] = (previous, next)
        }
      }
    }
  }
  let original = paragraphs.copy()
  for id, paragraph in original {
    if !enabled[id] {
      continue
    }
    let key = keys[id]
    let cell = tree.nodes[tree.nodes[id].parent].name == "tc"
    let (previous, next) = neighbors.get(id).unwrap_or((None, None))
    let same = fn(neighbor) {
      match neighbor {
        Some(id) => keys.get(id) == Some(key)
        None => cell && key is None
      }
    }
    let after = if same(next) {
      0.0
    } else if next is Some(table) && tree.nodes[table].name == "tbl" {
      match
        tree.descendants(table).iter().find_first(id => original.contains(id)) {
        Some(first) if keys[first] == key =>
          original[first].before.max(paragraph.after) - paragraph.after
        _ => paragraph.after
      }
    } else {
      paragraph.after
    }
    paragraphs[id] = {
      ..paragraph,
      before: if same(previous) {
        0
      } else {
        paragraph.before
      },
      after,
    }
  }
}
