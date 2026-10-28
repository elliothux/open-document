///|
priv struct IndexEntry {
  id : Int32
  paragraph : Int32
  label : String
  runs : Array[Int32]
  reason : String
}

///|
fn index_separator(instruction : String) -> String raise @failure.Failure {
  guard instruction.length() <= 256 else {
    @failure.reject("limit-exceeded", "Index instruction exceeds budget")
  }
  let tokens = text_reference_tokens(instruction)
  guard !tokens.is_empty() &&
    tokens[0].0.to_upper() == "INDEX" &&
    !tokens[0].1 &&
    tokens.length() % 2 == 1 else {
    @failure.reject("protected-content", "Unsupported index instruction")
  }
  let seen : Set[String] = Set([])
  let mut separator = ", "
  for i = 1; i < tokens.length(); i = i + 2 {
    let switch = tokens[i].0.to_lower()
    let value = tokens[i + 1].0
    guard !tokens[i].1 && !seen.contains(switch) else {
      @failure.reject("protected-content", "Repeated or quoted index switch")
    }
    seen.add(switch)
    match switch {
      "\\c" if value == "1" => ()
      "\\e" if tokens[i + 1].1 &&
        value.length() <= 5 &&
        @xml.valid_text(value) &&
        value
        .iter()
        .all(ch => {
          ch == '\t' || (ch.to_int() >= 32 && ch != '\u2028' && ch != '\u2029')
        }) => separator = value
      _ =>
        @failure.reject(
          "protected-content", "Unsupported index layout or switch",
        )
    }
  }
  separator
}

///|
fn check_index_label(label : String) -> Unit raise @failure.Failure {
  let parts = label.split(":").to_array()
  guard !label.is_empty() &&
    label.length() <= 255 &&
    @xml.valid_text(label) &&
    parts.length() <= 3 &&
    parts.all(part => !part.trim().is_empty()) &&
    label
    .iter()
    .all(ch => {
      ch.to_int() >= 32 && !"\"\\;\u2028\u2029".contains(ch.to_string())
    }) else {
    @failure.reject(
      "invalid-operation", "Index entries require one to three nonempty levels and at most 255 plain characters",
    )
  }
}

///|
fn index_entry_label(instruction : String) -> String raise @failure.Failure {
  let code = instruction.trim().to_owned()
  guard code.length() <= 512 &&
    code.length() >= 5 &&
    code[:2].to_owned().to_upper() == "XE" &&
    [32, 9].contains(code[2].to_int()) else {
    @failure.reject("protected-content", "Expected an index entry instruction")
  }
  let value = code[2:].trim().to_owned()
  guard value.has_prefix("\"") && value.has_suffix("\"") && value.length() >= 3 else {
    @failure.reject(
      "protected-content", "Index entries require a quoted term without switches",
    )
  }
  let label = value[1:value.length() - 1].to_owned()
  check_index_label(label)
  label
}

///|
fn WordTree::index_entry_profile(
  self : WordTree,
  id : Int32,
  paragraph : Int32,
  runs : Array[Int32],
  markers : Array[Int32],
  instruction : String,
  complete : Bool,
) -> IndexEntry {
  let mut label = ""
  let reason = try {
    guard complete && runs.length() <= 64 else {
      @failure.reject("protected-content", "Incomplete or extended index entry")
    }
    label = index_entry_label(instruction)
    let simple = self.nodes[id].name == "fldSimple"
    let raw = self.source[self.nodes[id].start:self.nodes[id].end]
    guard !simple || (!raw.contains("<!--") && !raw.contains("<?")) else {
      @failure.reject("protected-content", "Annotated index entry is protected")
    }
    if self.nodes[id].name == "fldSimple" {
      self.check_running_field_node(id, ["instr", "dirty", "fldLock"])
    }
    let mut state = 0
    for run in runs {
      let node = self.nodes[run]
      guard node.uri == word_uri &&
        node.name == "r" &&
        node.attributes.all(a => {
          a.uri == word_uri && ["rsidR", "rsidRPr", "rsidDel"].contains(a.name)
        }) &&
        node.text.trim().is_empty() else {
        @failure.reject("protected-content", "Extended index entry run")
      }
      let raw = self.source[node.start:node.end]
      guard !raw.contains("<!--") && !raw.contains("<?") else {
        @failure.reject(
          "protected-content", "Annotated index entry is protected",
        )
      }
      for item in self.children[run] {
        let child = self.nodes[item]
        guard child.uri == word_uri &&
          ["rPr", "fldChar", "instrText", "t"].contains(child.name) else {
          @failure.reject(
            "protected-content", "Index entry shares a run with other content",
          )
        }
        if child.name == "fldChar" {
          guard !simple else {
            @failure.reject("protected-content", "Nested index entry")
          }
          self.check_running_field_node(item, [
            "fldCharType", "dirty", "fldLock",
          ])
          guard self.children[item].is_empty() && child.text.trim().is_empty() else {
            @failure.reject("protected-content", "Extended index field marker")
          }
          state = match (state, child.attribute("fldCharType", uri=word_uri)) {
            (0, Some("begin")) => 1
            (1, Some("separate")) => 2
            (1 | 2, Some("end")) => 3
            _ =>
              @failure.reject(
                "protected-content", "Nested or unbalanced index entry",
              )
          }
        } else if child.name == "instrText" || child.name == "t" {
          guard child.name != "instrText" || (!simple && state == 1) else {
            @failure.reject(
              "protected-content", "Index instruction outside its field",
            )
          }
          self.check_field_text(item)
          guard child.name != "t" || child.text.is_empty() else {
            @failure.reject(
              "protected-content", "Visible index entry results require support",
            )
          }
        } else {
          guard child.attributes.is_empty() &&
            child.text.trim().is_empty() &&
            self.children[item].all(property => {
              let n = self.nodes[property]
              n.uri == word_uri &&
              ["vanish", "rStyle", "lang", "noProof"].contains(n.name) &&
              n.attributes.all(a => {
                a.uri == word_uri &&
                ["val", "eastAsia", "bidi"].contains(a.name)
              }) &&
              n.text.trim().is_empty() &&
              self.children[property].is_empty()
            }) else {
            @failure.reject(
              "protected-content", "Extended hidden index entry properties",
            )
          }
        }
      }
    }
    guard simple || (state == 3 && markers.get(0) == Some(id)) else {
      @failure.reject("protected-content", "Incomplete index entry markers")
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
  { id, paragraph, label, runs, reason, }
}

///|
fn WordTree::read_index_entries(
  self : WordTree,
) -> (Map[Int32, IndexEntry], Set[Int32]) {
  let entries : Map[Int32, IndexEntry] = Map([])
  let ignored : Set[Int32] = Set([])
  for paragraph in self.order {
    let p = self.nodes[paragraph]
    if p.uri != word_uri || p.name != "p" {
      continue
    }
    let mut depth = 0
    let mut first = -1
    let mut code = ""
    let mut runs : Array[Int32] = []
    let mut markers : Array[Int32] = []
    let mut separated = false
    for child in self.children[paragraph] {
      let node = self.nodes[child]
      if node.uri != word_uri {
        continue
      }
      if node.name == "fldSimple" {
        let instruction = node
          .attribute("instr", uri=word_uri)
          .unwrap_or("")
          .trim()
          .to_owned()
        if instruction.to_upper().has_prefix("XE ") ||
          instruction.to_upper().has_prefix("XE\t") {
          let descendants = self.descendants(child)
          let value = self.index_entry_profile(
            child,
            paragraph,
            self.children[child],
            descendants,
            instruction,
            depth == 0,
          )
          entries[child] = value
          if value.reason.is_empty() {
            for id in descendants {
              ignored.add(id)
            }
          }
        }
        continue
      }
      if node.name != "r" {
        continue
      }
      for item in self.children[child] {
        let n = self.nodes[item]
        if n.uri != word_uri {
          continue
        }
        if n.name == "fldChar" {
          match n.attribute("fldCharType", uri=word_uri) {
            Some("begin") => {
              if depth == 0 {
                first = item
                code = ""
                runs = []
                markers = []
                separated = false
              }
              depth += 1
            }
            Some("separate") if depth == 1 => separated = true
            Some("end") if depth > 0 => {
              if depth == 1 &&
                (
                  code.trim().to_upper().has_prefix("XE ") ||
                  code.trim().to_upper().has_prefix("XE\t")
                ) {
                if runs.last() != Some(child) {
                  runs.push(child)
                }
                markers.push(item)
                let value = self.index_entry_profile(
                  first,
                  paragraph,
                  runs,
                  markers,
                  code,
                  !separated ||
                  self.children[child].all(id => {
                    self.nodes[id].name != "t" || self.nodes[id].text.is_empty()
                  }),
                )
                entries[first] = value
                if value.reason.is_empty() {
                  for run in runs {
                    ignored.add(run)
                    for id in self.descendants(run) {
                      ignored.add(id)
                    }
                  }
                }
              }
              depth -= 1
            }
            _ => ()
          }
        } else if n.name == "instrText" &&
          depth == 1 &&
          !separated &&
          code.length() <= 512 {
          code += n.text[:(513 - code.length()).min(n.text.length())].to_owned()
        }
        if depth > 0 {
          if runs.last() != Some(child) {
            runs.push(child)
          }
          markers.push(item)
        }
      }
    }
  }
  (entries, ignored)
}

///|
/// Lists native index entry fields and generated indexes without changing document history.
pub fn Session::indexes(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let entries : Array[Json] = []
  for id in tree.order {
    if tree.index_entries.get(id) is Some(entry) {
      guard entries.length() < 4096 else {
        @failure.reject("limit-exceeded", "Index entries exceed budget")
      }
      entries.push({
        "id": entry.id,
        "paragraph": entry.paragraph,
        "label": entry.label,
        "reason": entry.reason,
      })
    }
  }
  let indexes : Array[Json] = []
  for id in tree.order {
    if tree.contents.get(id) is Some(value) &&
      value.paragraphs[0] == id &&
      value.instruction.trim().to_upper().has_prefix("INDEX") {
      guard indexes.length() < 256 else {
        @failure.reject("limit-exceeded", "Index fields exceed budget")
      }
      indexes.push({
        "paragraph": id,
        "endParagraph": value.paragraphs.last().unwrap(),
        "instruction": value.instruction,
        "reason": value.reason,
      })
    }
  }
  { "revision": revision, "entries": entries, "indexes": indexes }
}
