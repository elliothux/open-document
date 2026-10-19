///|
fn fragment_bookmark_markers(
  tree : WordTree,
  grid : TableGrid,
  top : Int,
  bottom : Int,
  left : Int,
  right : Int,
) -> Map[Int, String] raise @failure.Failure {
  let paragraphs : Map[Int, Bool] = Map([])
  let selected : Map[Int, Bool] = Map([])
  for row in top..<bottom {
    for column, cell in grid.cells[row] {
      let start = grid.starts[row][column]
      if start >= left && start < right {
        for paragraph in tree.table_children(cell, "p") {
          paragraphs[paragraph] = true
          for id in tree.descendants(paragraph) {
            if tree.is_bookmark(id) {
              selected[id] = true
            }
          }
        }
      }
    }
  }
  if selected.is_empty() {
    return Map([])
  }
  guard selected.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Rich table bookmarks exceed 4096")
  }
  let markers : Map[Int, String] = Map([])
  let outside : Map[Int, Int] = Map([])
  let mut count = 0
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri == word_uri && node.name == "p" && !paragraphs.contains(id) {
      count += 1
    }
    if selected.contains(id) {
      outside[id] = count
    }
  }
  for bookmark in tree.bookmarks() {
    if !selected.contains(bookmark.start) && !selected.contains(bookmark.end) {
      continue
    }
    guard bookmark.reason.is_empty() &&
      selected.contains(bookmark.start) &&
      selected.contains(bookmark.end) &&
      outside[bookmark.start] == outside[bookmark.end] else {
      @failure.reject(
        "protected-content", "Rich table copy requires complete supported bookmark ranges",
      )
    }
    check_bookmark_name(bookmark.name) catch {
      @failure.Failure(..) =>
        @failure.reject(
          "protected-content", "Rich table copy requires supported bookmark names",
        )
    }
    let key = markers.length() / 2
    markers[bookmark.start] = "<od:bookmarkStart od:id=\"\{key}\" od:name=\"\{property_attribute(bookmark.name)}\"/>"
    markers[bookmark.end] = "<od:bookmarkEnd od:id=\"\{key}\"/>"
  }
  guard markers.length() == selected.length() else {
    @failure.reject(
      "protected-content", "Rich table copy contains incomplete bookmark markers",
    )
  }
  markers
}

///|
fn Session::import_fragment_bookmarks(
  self : Session,
  document : @xml.Document,
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  let markers = tree.order.filter(id => tree.is_bookmark(id))
  guard markers.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Rich table bookmarks exceed 4096")
  }
  let catalog = if markers.is_empty() { [] } else { tree.bookmarks() }
  guard catalog.length() * 2 == markers.length() &&
    catalog.all(bookmark => bookmark.reason.is_empty()) else {
    @failure.reject(
      "protected-content", "Rich table requires complete unique bookmark pairs",
    )
  }
  let current = WordTree::new(self.document())
  let names : Map[String, Bool] = Map([])
  let used : Map[String, Bool] = Map([])
  let targets = current.bookmark_targets()
  let mut count = 0
  for id in current.order {
    if !current.is_bookmark(id) {
      continue
    }
    let node = current.nodes[id]
    let key = node.attribute("id", uri=word_uri).unwrap_or("")
    used[key] = true
    let number = @string.parse_int(key) catch { _ => -1 }
    if number >= 0 {
      used[number.to_string()] = true
    }
    if node.name == "bookmarkStart" {
      names[node.attribute("name", uri=word_uri).unwrap_or("").to_lower()] = true
      count += 1
    }
  }
  let changes : Array[@xml.SourceChange] = []
  let mut sequence = 0
  for bookmark in catalog {
    check_bookmark_name(bookmark.name)
    let duplicate = names.contains(bookmark.name.to_lower())
    let key = if duplicate {
      ""
    } else {
      guard count < 4096 else {
        @failure.reject("limit-exceeded", "Bookmark catalog exceeds 4096")
      }
      while sequence < 16384 && used.contains(sequence.to_string()) {
        sequence += 1
      }
      guard sequence < 16384 else {
        @failure.reject("limit-exceeded", "Bookmark identities exhausted")
      }
      count += 1
      let key = sequence.to_string()
      used[key] = true
      names[bookmark.name.to_lower()] = true
      targets[bookmark.name.to_lower()] = true
      sequence += 1
      key
    }
    for id in [bookmark.start, bookmark.end] {
      let node = tree.nodes[id]
      let markup = if duplicate {
        ""
      } else if id == bookmark.start {
        "<od:bookmarkStart xmlns:od=\"\{word_uri}\" od:id=\"\{key}\" od:name=\"\{property_attribute(bookmark.name)}\"/>"
      } else {
        "<od:bookmarkEnd xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/>"
      }
      changes.push({
        node: node.parent,
        offset: node.start - tree.nodes[node.parent].start,
        length: node.end - node.start,
        xml: markup,
      })
    }
  }
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri == word_uri &&
      node.name == "hyperlink" &&
      node.attribute("anchor", uri=word_uri) is Some(name) {
      guard targets.contains(name.to_lower()) else {
        @failure.reject(
          "protected-content", "Copied hyperlink bookmark is missing in the receiving document",
        )
      }
    }
  }
  if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
}
