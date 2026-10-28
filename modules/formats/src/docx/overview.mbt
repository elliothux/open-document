///|
/// Returns committed body headings and logical text counts without changing selection or history.
pub fn Session::overview(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let body = tree.child(0, "body").unwrap()
  let styles = self.styles([])
  let atoms : Map[Int32, Array[Int32]] = Map([])
  for node in self.texts {
    if !atoms.contains(node.paragraph) {
      atoms[node.paragraph] = []
    }
    atoms[node.paragraph].push(node.id)
  }
  let headings : Array[Json] = []
  let mut truncated = false
  let mut words = 0
  let mut characters = 0
  let mut no_spaces = 0
  let mut paragraphs = 0
  let mut work = 0
  let mut statistics_reason = ""
  if tree.children[body].any(id => {
      tree.nodes[id].uri != word_uri ||
      !["p", "tbl", "sectPr"].contains(tree.nodes[id].name)
    }) {
    statistics_reason = "Some document regions are not included in body statistics"
  }
  let diagnostics : Array[String] = []
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri || node.name != "p" {
      continue
    }
    let in_body = for ancestor = node.parent
                      ancestor >= 0
                      ancestor = tree.nodes[ancestor].parent {
      if ancestor == body {
        break true
      }
    } nobreak {
      false
    }
    if !in_body {
      continue
    }
    let parent = tree.nodes[node.parent]
    if node.parent != body && !(parent.uri == word_uri && parent.name == "tc") {
      statistics_reason = "Some document regions are not included in body statistics"
      continue
    }
    let reason = try {
      tree.check_editable_paragraph(id, part=self.main, pictures=true)
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    if !reason.is_empty() && statistics_reason.is_empty() {
      statistics_reason = reason
    }
    let label = StringBuilder()
    let mut word = false
    let mut nonempty = false
    for atom in atoms.get(id).unwrap_or([]) {
      let atom = tree.nodes[atom]
      if atom.name == "drawing" {
        continue
      }
      if atom.name != "t" && atom.name != "tab" {
        label.write_char(' ')
        continue
      }
      let text = inline_text(atom)
      work += text.length()
      guard work <= 1048576 else {
        @failure.reject("limit-exceeded", "Body statistics exceed text budget")
      }
      label.write_string(text)
      for character in text {
        characters += 1
        if character.is_whitespace() {
          word = false
        } else {
          no_spaces += 1
          nonempty = true
          if !word {
            words += 1
          }
          word = true
        }
      }
    }
    if nonempty {
      paragraphs += 1
    }
    let text = label.to_string().trim().to_owned()
    if text.is_empty() {
      continue
    }
    let level = styles.outline_level(tree, id) catch {
      @failure.Failure(message~, ..) => {
        let message = message[:8192].to_owned()
        if diagnostics.length() < 4096 && !diagnostics.contains(message) {
          diagnostics.push(message)
        }
        None
      }
    }
    if level is Some(level) {
      if headings.length() == 4096 {
        truncated = true
      } else {
        headings.push({
          "paragraph": id,
          "level": level + 1,
          "text": text[:256].to_owned(),
          "reason": reason,
        })
      }
    }
  }
  {
    "revision": revision,
    "bookmarks": match self.bookmarks(revision) {
      { "items": items, .. } => items
      _ => []
    },
    "headings": headings,
    "truncated": truncated,
    "diagnostics": diagnostics,
    "statistics": {
      "words": words,
      "characters": characters,
      "charactersNoSpaces": no_spaces,
      "paragraphs": paragraphs,
      "reason": statistics_reason,
    },
  }
}
