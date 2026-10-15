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
  let (candidate, _) = self.document.edit_source(changes)
  let node = candidate.node(root.id)
  candidate.source()[node.start:node.end].to_owned() +
  "<od:num xmlns:od=\"\{word_uri}\" od:numId=\"\{instance}\"><od:abstractNumId od:val=\"\{abstract_id}\"/></od:num>"
}
