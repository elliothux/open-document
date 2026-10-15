///|
fn NumberingContext::restart_markup(
  self : NumberingContext,
  tree : WordTree,
  styles : Styles,
  paragraph : Int,
  instance : Int,
  abstract_id : Int,
  start : Int,
) -> String raise @failure.Failure {
  let (old, target) = styles.numbering_reference(tree, paragraph).unwrap()
  let definition = self.definition(old)
  let counter = self.counter_at(tree, styles, paragraph)
  let root = self.tree.nodes[self.abstracts[definition.abstract_id]]
  let attribute = root.attributes
    .iter()
    .find_first(a => a.uri == word_uri && a.name == "abstractNumId")
    .unwrap()
  let changes : Array[@xml.SourceChange] = [
    {
      node: root.id,
      offset: attribute.start - root.start,
      length: attribute.end - attribute.start,
      xml: abstract_id.to_string(),
    },
  ]
  for level, value in definition.levels {
    let number = if level < target {
      counter.values[level]
    } else if level == target {
      start
    } else {
      definition.overrides.get(level).unwrap_or(value.start)
    }
    let markup = "<od:start xmlns:od=\"\{word_uri}\" od:val=\"\{number}\"/>"
    if properties_change(self.tree, self.document, value.node, "start", markup)
      is Some(change) {
      changes.push(change)
    }
  }
  let mut candidate = self.document.edit_source(changes).0
  let numbers = WordTree::new(candidate)
  let replacements : Array[@xml.SourceChange] = []
  let extra = StringBuilder()
  for index, level in definition.levels {
    if definition.base_levels.get(index).map(l => l.node) == Some(level.node) {
      continue
    }
    let markup = numbers.standalone_markup(candidate, level.node)
    if definition.base_levels.get(index) is Some(base) {
      let node = numbers.nodes[base.node]
      replacements.push({
        node: root.id,
        offset: node.start - numbers.nodes[root.id].start,
        length: node.end - node.start,
        xml: markup,
      })
    } else {
      extra.write_string(markup)
    }
  }
  if !extra.to_string().is_empty() {
    let node = numbers.nodes[root.id]
    replacements.push({
      node: root.id,
      offset: (if node.empty {
        node.opening_end - 2
      } else {
        node.closing_start
      }) -
      node.start,
      length: if node.empty {
        2
      } else {
        0
      },
      xml: if node.empty {
        ">" + extra.to_string() + "</\{node.qualified}>"
      } else {
        extra.to_string()
      },
    })
  }
  if !replacements.is_empty() {
    candidate = candidate.edit_source(replacements).0
  }
  WordTree::new(candidate).standalone_markup(candidate, root.id) +
  "<od:num xmlns:od=\"\{word_uri}\" od:numId=\"\{instance}\"><od:abstractNumId od:val=\"\{abstract_id}\"/></od:num>"
}

///|
fn NumberingContext::counter_at(
  self : NumberingContext,
  tree : WordTree,
  styles : Styles,
  paragraph : Int,
) -> NumberCounter raise @failure.Failure {
  let (old, _) = styles.numbering_reference(tree, paragraph).unwrap()
  let definition = self.definition(old)
  let counter : NumberCounter = {
    values: Array::make(9, 0),
    seen: Map([]),
    previous: -1,
  }
  for p in tree.order {
    if tree.nodes[p].uri != word_uri || tree.nodes[p].name != "p" {
      continue
    }
    if styles.numbering_reference(tree, p) is Some((id, level)) {
      let current = self.definition(id)
      if current.abstract_id == definition.abstract_id {
        counter.advance(current, id, level)
      }
    }
    if p == paragraph {
      break
    }
  }
  counter
}
