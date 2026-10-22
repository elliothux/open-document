///|
fn WordTree::run_paragraph(self : WordTree, run : Int) -> Int {
  let parent = self.nodes[run].parent
  if parent >= 0 &&
    self.nodes[parent].uri == word_uri &&
    ["hyperlink", "fldSimple"].contains(self.nodes[parent].name) {
    self.nodes[parent].parent
  } else {
    parent
  }
}

///|
fn WordTree::paragraph_runs(
  self : WordTree,
  paragraph : Int,
  running~ : Bool = false,
  review~ : Bool = false,
  math~ : Bool = false,
) -> Array[Int] {
  let runs : Array[Int] = []
  for child in self.children[paragraph] {
    let node = self.nodes[child]
    if math && node.uri == math_uri && node.name == "oMath" {
      runs.push(child)
    } else if node.uri == word_uri && node.name == "r" {
      runs.push(child)
    } else if review &&
      node.uri == word_uri &&
      ["ins", "del"].contains(node.name) {
      let supported = try {
        ignore(self.check_text_revision(child))
        true
      } catch {
        @failure.Failure(..) => false
      }
      if supported {
        runs.append(self.children[child])
      }
    } else if node.uri == word_uri &&
      (node.name == "hyperlink" || (running && node.name == "fldSimple")) {
      runs.append(
        self.children[child].filter(id => {
          self.nodes[id].uri == word_uri && self.nodes[id].name == "r"
        }),
      )
    }
  }
  runs
}

///|
fn WordTree::check_hyperlink(
  self : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  guard node.attributes.all(a => {
      (a.uri == rel && a.name == "id") ||
      (
        a.uri == word_uri &&
        ["anchor", "docLocation", "history", "tgtFrame", "tooltip"].contains(
          a.name,
        )
      )
    }) &&
    self.children[id].all(child => {
      self.is_bookmark(child) ||
      self.is_comment_marker(child) ||
      (self.nodes[child].uri == word_uri && self.nodes[child].name == "r")
    }) &&
    node.text.trim().is_empty() &&
    (
      !node.attribute("id", uri=rel).unwrap_or("").is_empty() ||
      !node.attribute("anchor", uri=word_uri).unwrap_or("").is_empty()
    ) &&
    ["0", "1", "true", "false", "on", "off"].contains(
      node.attribute("history", uri=word_uri).unwrap_or("1"),
    ) else {
    @failure.reject(
      "protected-content", "Extended or incomplete hyperlinks require editing support",
    )
  }
  for child in self.children[id] {
    if self.is_bookmark(child) {
      self.check_bookmark_marker(child)
    } else if self.is_comment_marker(child) {
      self.check_comment_marker(child)
    }
  }
}

///|
fn WordTree::hyperlink_frame(
  self : WordTree,
  document : @xml.Document,
  run : Int,
) -> (String, String) {
  let parent = self.nodes[self.nodes[run].parent]
  if parent.uri == word_uri && parent.name == "hyperlink" {
    (
      document.source()[parent.start:parent.opening_end].to_owned(),
      "</\{parent.qualified}>",
    )
  } else {
    ("", "")
  }
}
