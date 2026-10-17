///|
priv struct CommentAnchor {
  key : String
  start : Int?
  end : Int?
  reference : Int
  selection : Selection?
  reason : String
}

///|
fn comment_key(value : String) -> String raise @failure.Failure {
  let number = @string.parse_int(value) catch { _ => -1 }
  guard number >= 0 && number.to_string() == value else {
    @failure.reject("protected-content", "Invalid comment identity")
  }
  value
}

///|
fn WordTree::is_comment_marker(self : WordTree, id : Int) -> Bool {
  let node = self.nodes[id]
  node.uri == word_uri &&
  ["commentRangeStart", "commentRangeEnd", "commentReference"].contains(
    node.name,
  )
}

///|
fn WordTree::check_comment_marker(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  ignore(comment_key(node.attribute("id", uri=word_uri).unwrap_or("")))
  guard self.is_comment_marker(id) &&
    node.parent >= 0 &&
    self.nodes[node.parent].uri == word_uri &&
    (if node.name == "commentReference" {
      self.nodes[node.parent].name == "r"
    } else {
      ["p", "hyperlink"].contains(self.nodes[node.parent].name)
    }) &&
    node.attributes.all(a => a.uri == word_uri && a.name == "id") &&
    self.children[id].is_empty() &&
    node.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown comment anchor markup")
  }
}

///|
fn WordTree::comment_anchors(self : WordTree) -> Array[CommentAnchor] {
  let markers : Map[String, Array[Int]] = Map([])
  let keys : Array[String] = []
  for id in self.order {
    if self.is_comment_marker(id) {
      let key = self.nodes[id].attribute("id", uri=word_uri).unwrap_or("")
      if !markers.contains(key) {
        markers[key] = []
        keys.push(key)
      }
      markers[key].push(id)
    }
  }
  if keys.is_empty() {
    return []
  }
  let positions = self.inline_marker_positions()
  let checked : Map[Int, String] = Map([])
  keys.map(key => {
    let ids = markers[key]
    let starts = ids.filter(id => self.nodes[id].name == "commentRangeStart")
    let ends = ids.filter(id => self.nodes[id].name == "commentRangeEnd")
    let refs = ids.filter(id => self.nodes[id].name == "commentReference")
    let start = starts.get(0)
    let end = ends.get(0)
    let reference = refs.get(0).unwrap_or(-1)
    let reason = try {
      for id in ids {
        self.check_comment_marker(id)
      }
      guard refs.length() == 1 &&
        starts.length() == ends.length() &&
        starts.length() <= 1 &&
        positions.contains(reference) else {
        @failure.reject(
          "protected-content", "Incomplete or duplicate comment anchors",
        )
      }
      if start is Some(start) && end is Some(end) {
        guard positions.contains(start) &&
          positions.contains(end) &&
          self.nodes[start].end <= self.nodes[end].start &&
          self.nodes[end].end <= self.nodes[reference].start &&
          positions[end].paragraph == positions[reference].paragraph &&
          positions[end].offset == positions[reference].offset else {
          @failure.reject(
            "protected-content", "Unordered or detached comment anchors",
          )
        }
      }
      for id in ids {
        guard positions.contains(id) else {
          @failure.reject(
            "protected-content", "Comment anchor is inside a protected container",
          )
        }
        let p = positions[id].paragraph
        if !checked.contains(p) {
          checked[p] = try {
            self.check_editable_paragraph(p, part="", pictures=true)
            ""
          } catch {
            @failure.Failure(message~, ..) => message
          }
        }
        guard checked[p].is_empty() else {
          @failure.reject("protected-content", checked[p])
        }
      }
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    {
      key,
      start,
      end,
      reference,
      reason,
      selection: if reason.is_empty() {
        Some({
          anchor: positions[start.unwrap_or(reference)],
          focus: positions[end.unwrap_or(reference)],
        })
      } else {
        None
      },
    }
  })
}

///|
fn check_comment_integrity(
  original : @xml.Document,
  candidate : @xml.Document,
) -> Unit raise @failure.Failure {
  let before = WordTree::new(original)
  if !before.order.any(id => before.is_comment_marker(id)) {
    return
  }
  let after = WordTree::new(candidate)
  let next = Map::from_array(after.comment_anchors().map(a => (a.key, a)))
  let known : Map[Int, Bool] = Map([])
  for anchor in before.comment_anchors() {
    if !anchor.reason.is_empty() {
      continue
    }
    guard next.get(anchor.key) is Some(next) && next.reason.is_empty() else {
      @failure.reject(
        "protected-content", "This structural edit would remove or break a comment anchor",
      )
    }
    for id in [anchor.start, anchor.end, Some(anchor.reference)] {
      if id is Some(id) {
        known[id] = true
      }
    }
  }
  let remaining : Map[String, Int] = Map([])
  for id in after.order {
    if after.is_comment_marker(id) {
      let n = after.nodes[id]
      let raw = candidate.source()[n.start:n.end].to_owned()
      remaining[raw] = remaining.get(raw).unwrap_or(0) + 1
    }
  }
  for id in before.order {
    if before.is_comment_marker(id) && !known.contains(id) {
      let n = before.nodes[id]
      let raw = original.source()[n.start:n.end].to_owned()
      guard remaining.get(raw).unwrap_or(0) > 0 else {
        @failure.reject(
          "protected-content", "Unknown comment anchors must be preserved",
        )
      }
      remaining[raw] -= 1
    }
  }
}
