///|
priv struct Bookmark {
  key : String
  name : String
  start : Int
  end : Int
  selection : Selection?
  reason : String
}

///|
fn WordTree::next_bookmark_key(
  self : WordTree,
) -> String raise @failure.Failure {
  let used : Map[String, Bool] = Map([])
  for id in self.order {
    if self.is_bookmark(id) {
      let key = self.nodes[id].attribute("id", uri=word_uri).unwrap_or("")
      used[key] = true
      let number = @string.parse_int(key) catch { _ => -1 }
      if number >= 0 {
        used[number.to_string()] = true
      }
    }
  }
  for i in 0..<16384 {
    if !used.contains(i.to_string()) {
      return i.to_string()
    }
  }
  @failure.reject("limit-exceeded", "Bookmark identities exhausted")
}

///|
fn check_bookmark_name(name : String) -> Unit raise @failure.Failure {
  guard !name.is_empty() &&
    name.length() <= 40 &&
    name
    .iter()
    .all(c => {
      c == '_' ||
      (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9')
    }) &&
    !(name[0] >= 48 && name[0] <= 57) else {
    @failure.reject(
      "invalid-operation", "Bookmark names require 1–40 letters, digits or underscores and cannot start with a digit",
    )
  }
}

///|
fn WordTree::is_bookmark(self : WordTree, id : Int) -> Bool {
  let node = self.nodes[id]
  node.uri == word_uri && ["bookmarkStart", "bookmarkEnd"].contains(node.name)
}

///|
fn WordTree::check_bookmark_marker(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  let key = node.attribute("id", uri=word_uri).unwrap_or("")
  let number = @string.parse_int(key) catch { _ => -1 }
  let start = node.name == "bookmarkStart"
  guard self.is_bookmark(id) &&
    number >= 0 &&
    key == number.to_string() &&
    node.attributes.all(a => {
      a.uri == word_uri && (a.name == "id" || (start && a.name == "name"))
    }) &&
    (!start || !node.attribute("name", uri=word_uri).unwrap_or("").is_empty()) &&
    self.children[id].is_empty() &&
    node.text.trim().is_empty() else {
    @failure.reject(
      "protected-content", "Extended or incomplete bookmark markers require editing support",
    )
  }
}

///|
fn WordTree::inline_marker_positions(self : WordTree) -> Map[Int, Position] {
  let atoms = Map::from_array(docx_texts(self).map(t => (t.id, t.paragraph)))
  let offsets : Map[Int, Int] = Map([])
  let positions : Map[Int, Position] = Map([])
  for id in self.order {
    let node = self.nodes[id]
    if atoms.get(id) is Some(p) {
      offsets[p] = offsets.get(p).unwrap_or(0) + inline_text(node).length()
    }
    if !self.is_bookmark(id) && !self.is_comment_marker(id) {
      continue
    }
    let mut p = node.parent
    while p >= 0 &&
          self.nodes[p].uri == word_uri &&
          ["r", "hyperlink"].contains(self.nodes[p].name) {
      p = self.nodes[p].parent
    }
    if p >= 0 && self.nodes[p].uri == word_uri && self.nodes[p].name == "p" {
      positions[id] = {
        paragraph: p,
        offset: offsets.get(p).unwrap_or(0),
        affinity: "after",
        bidiLevel: None,
        frameStart: None,
      }
    }
  }
  positions
}

///|
fn WordTree::bookmarks(self : WordTree) -> Array[Bookmark] {
  if !self.order.any(id => self.is_bookmark(id)) {
    return []
  }
  let positions = self.inline_marker_positions()
  let starts : Map[String, Array[Int]] = Map([])
  let ends : Map[String, Array[Int]] = Map([])
  let names : Map[String, Int] = Map([])
  for id in self.order {
    if !self.is_bookmark(id) {
      continue
    }
    let node = self.nodes[id]
    let key = node.attribute("id", uri=word_uri).unwrap_or("")
    let map = if node.name == "bookmarkStart" { starts } else { ends }
    if !map.contains(key) {
      map[key] = []
    }
    map[key].push(id)
    if node.name == "bookmarkStart" {
      let name = node.attribute("name", uri=word_uri).unwrap_or("").to_lower()
      names[name] = names.get(name).unwrap_or(0) + 1
    }
  }
  let result : Array[Bookmark] = []
  let checked : Map[Int, String] = Map([])
  for id in self.order {
    let node = self.nodes[id]
    if node.uri != word_uri || node.name != "bookmarkStart" {
      continue
    }
    let key = node.attribute("id", uri=word_uri).unwrap_or("")
    let name = node.attribute("name", uri=word_uri).unwrap_or("")
    let end = ends.get(key).bind(items => items.get(0)).unwrap_or(-1)
    let reason = try {
      self.check_bookmark_marker(id)
      guard starts[key].length() == 1 &&
        ends.get(key).map(v => v.length()) == Some(1) &&
        names[name.to_lower()] == 1 &&
        end >= 0 &&
        self.nodes[end].start >= node.end else {
        @failure.reject(
          "protected-content", "Bookmark names and paired identities must be unique and ordered",
        )
      }
      self.check_bookmark_marker(end)
      guard positions.contains(id) && positions.contains(end) else {
        @failure.reject(
          "protected-content", "Bookmark is inside a protected container",
        )
      }
      for p in [positions[id].paragraph, positions[end].paragraph] {
        if !checked.contains(p) {
          checked[p] = try {
            self.check_editable_paragraph(
              p,
              part="",
              pictures=true,
              fields=true,
              notes=true,
              sectionBoundary=true,
            )
            ""
          } catch {
            @failure.Failure(message~, ..) => message
          }
        }
        if !checked[p].is_empty() {
          @failure.reject("protected-content", checked[p])
        }
      }
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    result.push({
      key,
      name,
      start: id,
      end,
      selection: if reason.is_empty() {
        Some({ anchor: positions[id], focus: positions[end], })
      } else {
        None
      },
      reason,
    })
  }
  result
}

///|
fn WordTree::bookmark_targets(self : WordTree) -> Map[String, Bool] {
  if !self.order.any(id => self.is_bookmark(id)) {
    return Map([])
  }
  Map::from_array(
    self
    .bookmarks()
    .filter(b => b.reason.is_empty())
    .map(b => (b.name.to_lower(), true)),
  )
}

///|
fn check_bookmark_integrity(
  original : @xml.Document,
  candidate : @xml.Document,
) -> Unit raise @failure.Failure {
  let before = WordTree::new(original)
  if !before.order.any(id => before.is_bookmark(id)) {
    return
  }
  let after = WordTree::new(candidate)
  let catalog = Map::from_array(after.bookmarks().map(b => (b.key, b)))
  let known : Map[Int, Bool] = Map([])
  for b in before.bookmarks() {
    if !b.reason.is_empty() {
      continue
    }
    guard catalog.get(b.key) is Some(next) &&
      next.reason.is_empty() &&
      next.name == b.name else {
      @failure.reject(
        "protected-content", "This structural edit would remove or break a bookmark",
      )
    }
    known[b.start] = true
    known[b.end] = true
  }
  let remaining : Map[String, Int] = Map([])
  for id in after.order {
    if after.is_bookmark(id) {
      let n = after.nodes[id]
      let raw = candidate.source()[n.start:n.end].to_owned()
      remaining[raw] = remaining.get(raw).unwrap_or(0) + 1
    }
  }
  for id in before.order {
    if before.is_bookmark(id) && !known.contains(id) {
      let n = before.nodes[id]
      let raw = original.source()[n.start:n.end].to_owned()
      guard remaining.get(raw).unwrap_or(0) > 0 else {
        @failure.reject(
          "protected-content", "Unknown bookmark markup must be preserved",
        )
      }
      remaining[raw] = remaining[raw] - 1
    }
  }
}

///|
/// Lists body and cell bookmarks without changing selection or history.
pub fn Session::bookmarks(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let items = WordTree::new(self.document()).bookmarks()
  guard items.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Bookmark catalog exceeds budget")
  }
  {
    "revision": revision,
    "items": items.map(fn(b) -> Json {
      {
        "name": b.name,
        "reason": b.reason,
        "selection": b.selection.map(s => s.to_json()).unwrap_or(Json::null()),
      }
    }),
  }
}
