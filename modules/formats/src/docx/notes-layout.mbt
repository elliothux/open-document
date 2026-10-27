///|
fn Session::layout_notes(
  self : Session,
  tree : WordTree,
  styles : Styles,
  background : String,
) -> (Map[Int, (String, String)], Array[@layout.Note], String) raise @failure.Failure {
  let references : Map[Int, (String, String)] = Map([])
  let notes : Array[@layout.Note] = []
  let mut story_id = -1000000000
  let sections = tree.note_sections()
  let mut endnotes_at = "docEnd"
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
    guard ids.length() <= 8192 - notes.length() else {
      @failure.reject("limit-exceeded", "Note count exceeds limits")
    }
    let defaults = self.note_settings(kind)
    if kind == "endnote" {
      endnotes_at = defaults.position
    }
    let settings : Map[Int, NoteSettings] = Map([])
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
    let mut previous_section = -2
    let mut section_count = 0
    for index, id in ids {
      let node = tree.nodes[id]
      let paragraph = tree.run_paragraph(node.parent)
      guard sections.get(paragraph) is Some(section) &&
        tree.nodes[paragraph].parent >= 0 &&
        ["body", "tc"].contains(tree.nodes[tree.nodes[paragraph].parent].name) else {
        @failure.reject(
          "unsupported-layout", "Note reference is outside a body paragraph",
        )
      }
      if section != previous_section {
        section_count = 0
        previous_section = section
      }
      let setting = match settings.get(section) {
        Some(setting) => setting
        None => {
          let setting = if section < 0 {
            defaults
          } else {
            defaults.read(tree, section, kind, document=false)
          }
          settings[section] = setting
          setting
        }
      }
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
      let ordinal = if setting.restart == "eachPage" {
        1L
      } else if setting.restart == "eachSect" {
        section_count.to_int64() + 1L
      } else {
        setting.numbering.start + index.to_int64()
      }
      let numbering : @layout.NoteNumbering = {
        value: ordinal,
        format: setting.numbering.format,
        restart: setting.restart,
        marker: 0,
      }
      let label = numbering.text()
      section_count += 1
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
      references[id] = (label, "NOTE:" + kind + ":" + key)
      notes.push({
        kind,
        key,
        paragraph,
        node: id,
        content,
        numbering: { ..numbering, marker: markers.keys().to_array()[0], },
      })
    }
  }
  (references, notes, endnotes_at)
}
