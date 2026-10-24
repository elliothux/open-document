///|
priv struct NoteSettings {
  numbering : @layout.PageNumbering
  restart : String
  position : String
}

///|
fn NoteSettings::read(
  self : NoteSettings,
  tree : WordTree,
  owner : Int,
  kind : String,
  document~ : Bool,
) -> NoteSettings raise @failure.Failure {
  let roots = tree.children[owner].filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == kind + "Pr"
  })
  guard roots.length() <= 1 else {
    @failure.reject("unsupported-layout", "Duplicate note properties")
  }
  guard roots is [id] else { return self }
  guard tree.nodes[id].attributes.is_empty() &&
    tree.nodes[id].text.trim().is_empty() else {
    @failure.reject("unsupported-layout", "Unknown note properties")
  }
  let mut format = self.numbering.format
  let mut start = self.numbering.start
  let mut restart = self.restart
  let mut position = self.position
  let seen : Set[String] = Set([])
  for child in tree.children[id] {
    let node = tree.nodes[child]
    if document &&
      node.uri == word_uri &&
      node.name == kind &&
      node.attributes.length() == 1 &&
      [Some("-1"), Some("0")].contains(node.attribute("id", uri=word_uri)) &&
      tree.children[child].is_empty() {
      continue
    }
    guard node.uri == word_uri &&
      !seen.contains(node.name) &&
      tree.children[child].is_empty() &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => a.uri == word_uri && a.name == "val") else {
      @failure.reject("unsupported-layout", "Invalid note numbering property")
    }
    seen.add(node.name)
    let value = node.attribute("val", uri=word_uri).unwrap_or("")
    match node.name {
      "numFmt" => format = value
      "numStart" =>
        start = @string.parse_int64(value) catch {
          _ => @failure.reject("unsupported-layout", "Invalid note start")
        }
      "numRestart" if ["continuous", "eachSect"].contains(value) =>
        restart = value
      "pos" if (kind == "footnote" && value == "pageBottom") ||
        (kind == "endnote" && ["sectEnd", "docEnd"].contains(value)) =>
        // ONLYOFFICE preserves section pos but uses the document-wide placement.
        if document {
          position = value
        }
      _ =>
        @failure.reject(
          "unsupported-layout", "Unsupported note numbering or placement",
        )
    }
  }
  let numbering = @layout.PageNumbering::new(start~, format~)
  numbering.validate()
  { numbering, restart, position, }
}

///|
fn Session::note_settings(
  self : Session,
  kind : String,
) -> NoteSettings raise @failure.Failure {
  let defaults : NoteSettings = {
    numbering: @layout.PageNumbering::new(
      format=if kind == "endnote" { "lowerRoman" } else { "decimal" },
    ),
    restart: "continuous",
    position: if kind == "endnote" {
      "docEnd"
    } else {
      "pageBottom"
    },
  }
  match self.settings_part() {
    None => defaults
    Some(part) =>
      defaults.read(WordTree::new(self.part_xml(part)), 0, kind, document=true)
  }
}

///|
fn WordTree::note_sections(self : WordTree) -> Map[Int, Int] {
  let result : Map[Int, Int] = Map([])
  let body = self.child(0, "body").unwrap()
  let mut section = -1
  for id in self.children[body].rev() {
    let node = self.nodes[id]
    if node.uri != word_uri {
      continue
    }
    if node.name == "sectPr" {
      section = id
      continue
    }
    if node.name == "p" &&
      self.child(id, "pPr").bind(p => self.child(p, "sectPr")) is Some(id) {
      section = id
    }
    for child in self.descendants(id) {
      if self.nodes[child].uri == word_uri && self.nodes[child].name == "p" {
        result[child] = section
      }
    }
  }
  result
}
