///|
fn NotesSource::edit_text(
  self : NotesSource,
  note : DocNote,
  text : String,
) -> (@xml.Document, Array[@xml.Edit]) raise @failure.Failure {
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  let retained = note.paragraphs[:lines.length().min(note.paragraphs.length())]
  let by_paragraph : Map[Int32, Array[Int32]] = Map([])
  for id in note.texts {
    let paragraph = self.tree.nodes[self.tree.nodes[id].parent].parent
    by_paragraph.get_or_init(paragraph, () => []).push(id)
  }
  let replacements : Map[Int32, String] = Map([])
  let firsts : Array[(Int32, String)] = []
  for index, paragraph in retained {
    let texts = by_paragraph.get(paragraph).unwrap_or([])
    for offset, id in texts {
      replacements[id] = if offset == 0 { lines[index] } else { "" }
    }
    if texts.get(0) is Some(first) {
      firsts.push((first, lines[index]))
    }
  }
  let steps : Array[@xml.Edit] = []
  let mut candidate = self.document
  if !replacements.is_empty() {
    let (updated, edit) = candidate.edit_text(replacements)
    candidate = updated
    steps.push(edit)
  }
  let tree = WordTree::new(candidate)
  let changes : Array[@xml.SourceChange] = []
  for (first, value) in firsts {
    if value.trim().to_owned() == value {
      continue
    }
    let node = tree.nodes[first]
    let attribute = node.attributes
      .iter()
      .find_first(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
      })
    if attribute.map(a => a.value) == Some("preserve") {
      continue
    }
    changes.push(
      match attribute {
        Some(attribute) =>
          {
            node: first,
            offset: attribute.start - node.start,
            length: attribute.end - attribute.start,
            xml: "preserve",
          }
        None =>
          {
            node: first,
            offset: node.opening_end - node.start - 1,
            length: 0,
            xml: " xml:space=\"preserve\"",
          }
      },
    )
  }
  for index, paragraph in retained {
    if by_paragraph.contains(paragraph) || lines[index].is_empty() {
      continue
    }
    let node = tree.nodes[paragraph]
    let marker = tree
      .descendants(paragraph)
      .iter()
      .find_first(id => {
        ["footnoteRef", "endnoteRef"].contains(tree.nodes[id].name)
      })
    let properties = marker
      .map(id => tree.note_input_properties(candidate, id))
      .unwrap_or_else(() => tree.empty_run_properties(candidate, paragraph))
    let markup = "<od:r xmlns:od='\{word_uri}'>\{properties}<od:t xml:space='preserve'>\{@xml.escape_text(lines[index])}</od:t></od:r>"
    changes.push(
      if node.empty {
        {
          node: paragraph,
          offset: node.opening_end - node.start - 2,
          length: 2,
          xml: ">\{markup}</\{node.qualified}>",
        }
      } else {
        {
          node: paragraph,
          offset: node.closing_start - node.start,
          length: 0,
          xml: markup,
        }
      },
    )
  }
  let owner = tree.nodes[note.node]
  for paragraph in note.paragraphs[retained.length():] {
    let node = tree.nodes[paragraph]
    changes.push({
      node: note.node,
      offset: node.start - owner.start,
      length: node.end - node.start,
      xml: "",
    })
  }
  if lines.length() > note.paragraphs.length() {
    let paragraph = note.paragraphs.last().unwrap()
    let properties = tree
      .child(paragraph, "pPr")
      .map(id => tree.standalone_markup(candidate, id))
      .unwrap_or("")
    let run = note.texts.last().map(id => tree.nodes[id].parent)
    let marker = tree
      .descendants(paragraph)
      .iter()
      .find_first(id => {
        ["footnoteRef", "endnoteRef"].contains(tree.nodes[id].name)
      })
    let character = if run is Some(run) {
      tree
      .child(run, "rPr")
      .map(id => tree.standalone_markup(candidate, id))
      .unwrap_or("")
    } else if marker is Some(marker) {
      tree.note_input_properties(candidate, marker)
    } else {
      tree.empty_run_properties(candidate, paragraph)
    }
    let markup = lines[note.paragraphs.length():]
      .map(line => {
        "<od:p xmlns:od='\{word_uri}'>\{properties}<od:r>\{character}<od:t xml:space='preserve'>\{@xml.escape_text(line)}</od:t></od:r></od:p>"
      })
      .join("")
    changes.push({
      node: note.node,
      offset: owner.closing_start - owner.start,
      length: 0,
      xml: markup,
    })
  }
  if !changes.is_empty() {
    let (updated, edit) = candidate.edit_source(changes)
    candidate = updated
    steps.push(edit)
  }
  (candidate, steps)
}
