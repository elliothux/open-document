///|
pub(all) struct FindOptions {
  matchCase : Bool
  wholeWord : Bool
}

///|
pub fn FindOptions::new(
  matchCase~ : Bool = false,
  wholeWord~ : Bool = false,
) -> FindOptions {
  { matchCase, wholeWord, }
}

///|
priv struct SearchGroup {
  paragraphs : Array[Int]
  starts : Array[Int]
  text : String
}

///|
priv struct SearchResult {
  matches : Array[(Selection, String, String)]
  truncated : Bool
}

///|
fn search_word_char(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() ||
  ch.is_ascii_digit() ||
  (!ch.is_ascii() && @unicode.non_ascii_id_continue.contains(ch))
}

///|
fn SearchGroup::position(
  self : SearchGroup,
  offset : Int,
  affinity : String,
) -> Position {
  let index = self.index(offset)
  {
    paragraph: self.paragraphs[index],
    offset: offset - self.starts[index],
    affinity,
    bidiLevel: None,
    frameStart: None,
  }
}

///|
fn SearchGroup::index(self : SearchGroup, offset : Int) -> Int {
  let index = match self.starts.binary_search(offset) {
    Ok(index) => index
    Err(index) => index - 1
  }
  index
}

///|
fn Session::search_groups(
  self : Session,
  tree : WordTree,
) -> Array[SearchGroup] raise @failure.Failure {
  let by_paragraph : Map[Int, StringBuilder] = Map([])
  for node in self.texts {
    let out = by_paragraph.get(node.paragraph).unwrap_or(StringBuilder())
    out.write_string(tree.nodes[node.id].text)
    by_paragraph[node.paragraph] = out
  }
  let body = tree.child(0, "body").unwrap()
  let groups : Array[SearchGroup] = []
  let mut paragraphs : Array[Int] = []
  let mut starts : Array[Int] = []
  let mut content = StringBuilder()
  let mut length = 0
  let mut parent = -1
  let mut previous = -1
  let cursors : Map[Int, Int] = Map([])
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri || node.name != "p" {
      continue
    }
    let in_body = for ancestor = id
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
    let siblings = tree.children[node.parent]
    let mut index = cursors.get(node.parent).unwrap_or(0)
    while siblings[index] != id {
      index += 1
    }
    cursors[node.parent] = index + 1
    let adjacent = parent == node.parent &&
      index > 0 &&
      siblings[index - 1] == previous
    if !adjacent && !paragraphs.is_empty() {
      groups.push({ paragraphs, starts, text: content.to_string(), })
      paragraphs = []
      starts = []
      content = StringBuilder()
      length = 0
    }
    if !paragraphs.is_empty() {
      content.write_char('\n')
      length += 1
    }
    let text = by_paragraph.get(id).map(out => out.to_string()).unwrap_or("")
    starts.push(length)
    paragraphs.push(id)
    content.write_string(text)
    length += text.length()
    guard length <= self.opc.budget.entry_bytes else {
      @failure.reject("limit-exceeded", "Search text exceeds budget")
    }
    parent = node.parent
    previous = id
  }
  if !paragraphs.is_empty() {
    groups.push({ paragraphs, starts, text: content.to_string(), })
  }
  groups
}

///|
fn Session::find_matches(
  self : Session,
  text : String,
  options : FindOptions,
) -> SearchResult raise @failure.Failure {
  guard !text.is_empty() &&
    text.length() <= command_limit &&
    @xml.valid_text(text) else {
    @failure.reject(
      "invalid-operation", "Search requires bounded nonempty literal text",
    )
  }
  let folded = fn(ch : Char) {
    if options.matchCase {
      ch
    } else {
      @unicode.to_lowercase(ch)
    }
  }
  let pattern = text.iter().map(folded).collect()
  let prefix = Array::make(pattern.length(), 0)
  for i in 1..<pattern.length() {
    let mut matched = prefix[i - 1]
    while matched > 0 && pattern[i] != pattern[matched] {
      matched = prefix[matched - 1]
    }
    if pattern[i] == pattern[matched] {
      matched += 1
    }
    prefix[i] = matched
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let styles = try self.styles([]) catch {
    error => Err(error)
  } noraise {
    value => Ok(value)
  }
  let reasons : Map[Int, String] = Map([])
  let matches : Array[(Selection, String, String)] = []
  for group in self.search_groups(tree) {
    let chars : Array[(Int, Char)] = []
    for offset, ch in group.text.iter2() {
      chars.push((offset, ch))
    }
    let boundaries = @layout.grapheme_boundaries(group.text)
    let mut matched = 0
    for index, (offset, ch) in chars {
      let value = folded(ch)
      while matched > 0 && value != pattern[matched] {
        matched = prefix[matched - 1]
      }
      if value == pattern[matched] {
        matched += 1
      }
      if matched != pattern.length() {
        continue
      }
      let first = index + 1 - matched
      let start = chars[first].0
      let end = offset + (if ch.to_int() > 0xffff { 2 } else { 1 })
      let whole = !options.wholeWord ||
        (
          (first == 0 || !search_word_char(chars[first - 1].1)) &&
          (index + 1 == chars.length() || !search_word_char(chars[index + 1].1))
        )
      if whole &&
        boundaries.binary_search(start) is Ok(_) &&
        boundaries.binary_search(end) is Ok(_) {
        if matches.length() == 1000 {
          return { matches, truncated: true, }
        }
        let selection = {
          anchor: group.position(start, "after"),
          focus: group.position(end, "before"),
        }
        let mut reason = ""
        for index in group.index(start)..<=group.index(end) {
          let id = group.paragraphs[index]
          let value = match reasons.get(id) {
            Some(value) => value
            None => {
              let value = try {
                tree.check_editable_paragraph(id, part=self.main)
                tree.check_structure_paragraph(id)
                let styles = match styles {
                  Ok(styles) => styles
                  Err(error) => raise error
                }
                self.paragraph(tree, styles, id, []).readOnlyReason
              } catch {
                @failure.Failure(message~, ..) => message
              }
              reasons[id] = value
              value
            }
          }
          if !value.is_empty() {
            reason = value
            break
          }
        }
        let snippet = group.text[(start - 16).max(0):(end + 32)
        .min(start + 80)
        .min(group.text.length())].to_owned()
        matches.push((selection, snippet, reason))
        matched = 0
      } else {
        matched = prefix[matched - 1]
      }
    }
  }
  { matches, truncated: false, }
}

///|
/// Finds nonoverlapping literal matches in body paragraph/cell order, bound to revision.
pub fn Session::find(
  self : Session,
  revision : Int,
  text : String,
  options : FindOptions,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let result = self.find_matches(text, options)
  {
    "revision": revision,
    "truncated": result.truncated,
    "matches": result.matches.map(item => {
      "selection": item.0.to_json(),
      "snippet": Json(item.1),
      "reason": Json(item.2),
    }),
  }
}
