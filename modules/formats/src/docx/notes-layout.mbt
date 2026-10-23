///|
fn Session::note_numbering(
  self : Session,
  tree : WordTree,
  kind : String,
) -> @layout.PageNumbering raise @failure.Failure {
  let mut format = if kind == "endnote" { "lowerRoman" } else { "decimal" }
  let mut start = 1L
  let sources = [tree]
  if self.settings_part() is Some(part) {
    sources.insert(0, WordTree::new(self.part_xml(part)))
  }
  for source in sources {
    let properties = source.order.filter(id => {
      source.nodes[id].uri == word_uri && source.nodes[id].name == kind + "Pr"
    })
    guard properties.length() <= 1 else {
      @failure.reject(
        "unsupported-layout", "Multiple note numbering sections are unsupported",
      )
    }
    for id in properties {
      let seen : Set[String] = Set([])
      for child in source.children[id] {
        let node = source.nodes[child]
        guard node.uri == word_uri else {
          @failure.reject("unsupported-layout", "Unknown note property")
        }
        let value = node.attribute("val", uri=word_uri).unwrap_or("")
        if node.name == kind &&
          node.attributes.length() == 1 &&
          node.attribute("id", uri=word_uri) is Some(mark) &&
          ["-1", "0"].contains(mark) &&
          source.children[child].is_empty() {
          continue
        }
        guard !seen.contains(node.name) &&
          source.children[child].is_empty() &&
          node.text.trim().is_empty() &&
          node.attributes.all(a => a.uri == word_uri && a.name == "val") else {
          @failure.reject(
            "unsupported-layout", "Invalid note numbering property",
          )
        }
        seen.add(node.name)
        match node.name {
          "numFmt" => format = value
          "numStart" =>
            start = @string.parse_int(value).to_int64() catch {
              _ => @failure.reject("unsupported-layout", "Invalid note start")
            }
          "numRestart" if value == "continuous" => ()
          "pos" if (kind == "footnote" && value == "pageBottom") ||
            (kind == "endnote" && ["sectEnd", "docEnd"].contains(value)) => ()
          _ =>
            @failure.reject(
              "unsupported-layout", "Unsupported note numbering or placement",
            )
        }
      }
    }
  }
  let numbering = @layout.PageNumbering::new(start~, format~)
  numbering.validate()
  numbering
}

///|
fn Session::layout_notes(
  self : Session,
  tree : WordTree,
  styles : Styles,
  background : String,
) -> (Map[Int, (String, String)], Array[@layout.Note]) raise @failure.Failure {
  let references : Map[Int, (String, String)] = Map([])
  let notes : Array[@layout.Note] = []
  let mut story_id = -1000000000
  for kind in ["footnote", "endnote"] {
    let ids = tree.order.filter(id => {
      tree.nodes[id].uri == word_uri &&
      tree.nodes[id].name == kind + "Reference"
    })
    if ids.is_empty() {
      continue
    }
    guard self.note_source(kind) is Some(source) else {
      @failure.reject(
        "unsupported-layout", "Note references have no content part",
      )
    }
    let numbering = self.note_numbering(tree, kind)
    for special in source.tree.children[0] {
      let role = source.tree.nodes[special]
        .attribute("type", uri=word_uri)
        .unwrap_or("")
      if ["", "normal"].contains(role) {
        continue
      }
      let mark = if role == "separator" {
        "separator"
      } else {
        "continuationSeparator"
      }
      let descendants = source.tree
        .descendants(special)
        .filter(id => id != special)
      guard role != "continuationNotice" &&
        descendants.filter(id => source.tree.nodes[id].name == mark).length() ==
        1 &&
        descendants.all(id => {
          let node = source.tree.nodes[id]
          node.uri == word_uri &&
          ["p", "r", mark].contains(node.name) &&
          node.attributes.is_empty() &&
          node.text.trim().is_empty()
        }) else {
        @failure.reject(
          "unsupported-layout", "Custom note separators require note-story layout",
        )
      }
    }
    let used : Set[String] = Set([])
    for index, id in ids {
      let node = tree.nodes[id]
      guard node.attributes.all(a => a.uri == word_uri && a.name == "id") &&
        tree.children[id].is_empty() &&
        node.text.trim().is_empty() else {
        @failure.reject(
          "unsupported-layout", "Custom note reference marks are unsupported",
        )
      }
      let key = note_key(node.attribute("id", uri=word_uri).unwrap_or(""))
      guard !used.contains(key) &&
        source.entries.iter().find_first(entry => entry.key == key)
        is Some(entry) else {
        @failure.reject("unsupported-layout", "Missing or repeated note body")
      }
      used.add(key)
      let label = @layout.PageNumbering::new(
        start=numbering.start + index.to_int64(),
        format=numbering.format,
      ).field_text("PAGE", 0, 1)
      let markers : Map[Int, (String, String)] = Map([])
      for child in source.tree.descendants(entry.node) {
        if source.tree.nodes[child].uri == word_uri &&
          source.tree.nodes[child].name == kind + "Ref" {
          guard source.tree.nodes[child].attributes.is_empty() &&
            source.tree.children[child].is_empty() else {
            @failure.reject(
              "unsupported-layout", "Custom note markers are unsupported",
            )
          }
          markers[child] = (label, "")
        }
        guard ![
          "hyperlink", "bookmarkStart", "bookmarkEnd", "commentReference", "commentRangeStart",
          "commentRangeEnd",
        ].contains(source.tree.nodes[child].name) else {
          @failure.reject(
            "unsupported-layout", "Note links and review anchors require note-story positions",
          )
        }
      }
      guard markers.length() == 1 &&
        source.tree.children[entry.node].all(p => {
          source.tree.nodes[p].uri == word_uri &&
          source.tree.nodes[p].name == "p"
        }) else {
        @failure.reject(
          "unsupported-layout", "Note content requires paragraph layout",
        )
      }
      let diagnostics : Array[String] = []
      let content = source.tree.children[entry.node].map(p => {
        let paragraph = self.paragraph(
          source.tree,
          styles,
          p,
          diagnostics,
          background~,
          note_refs=markers,
          running=true,
        )
        guard paragraph.spans.all(span => {
          span.drawing is None && span.field.is_empty()
        }) else {
          @failure.reject(
            "unsupported-layout", "Note objects and fields require note-story layout",
          )
        }
        story_id -= 1
        {
          ..paragraph,
          id: story_id,
          container: -3,
          readOnlyReason: "protected-content:note-area",
        }
      })
      guard diagnostics.is_empty() else {
        @failure.reject(
          "unsupported-layout", "Unsupported note paragraph properties",
        )
      }
      let paragraph = tree.run_paragraph(node.parent)
      guard paragraph >= 0 &&
        tree.nodes[paragraph].parent >= 0 &&
        ["body", "tc"].contains(tree.nodes[tree.nodes[paragraph].parent].name) else {
        @failure.reject(
          "unsupported-layout", "Note reference is outside a body paragraph",
        )
      }
      references[id] = (label, "NOTE:" + kind + ":" + key)
      notes.push({ kind, key, paragraph, node: id, content, })
    }
  }
  (references, notes)
}
