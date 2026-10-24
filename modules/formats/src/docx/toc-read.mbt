///|
priv struct TableOfContents {
  paragraphs : Array[Int]
  markers : Array[Int]
  first : Int
  last : Int
  hyperlink : Bool
  outline : Bool
  instruction : String
  reason : String
  control : Int?
}

///|
fn TableOfContents::edit_reason(self : TableOfContents) -> String {
  if self.instruction.trim().to_upper().has_prefix("INDEX") {
    "Index results require an index update"
  } else {
    "Table of contents results require a table of contents update"
  }
}

///|
fn toc_instruction(
  instruction : String,
) -> (Int, Int, Bool, Bool) raise @failure.Failure {
  guard instruction.length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Table of contents instruction exceeds budget",
    )
  }
  let tokens = instruction
    .replace_all(old="\t", new=" ")
    .split(" ")
    .filter(token => !token.is_empty())
    .map(token => token.to_owned())
    .to_array()
  if tokens.get(0).map(command => command.to_upper()) == Some("INDEX") {
    ignore(index_separator(instruction))
    return (1, 3, false, false)
  }
  guard tokens.get(0).map(token => token.to_upper()) == Some("TOC") else {
    @failure.reject("protected-content", "Expected a table of contents field")
  }
  let mut first = 1
  let mut last = 3
  let seen : Set[String] = Set([])
  for index = 1; index < tokens.length(); {
    let switch = tokens[index].to_lower()
    guard ["\\o", "\\h", "\\z", "\\u"].contains(switch) &&
      !seen.contains(switch) else {
      @failure.reject(
        "protected-content", "Unsupported table of contents switch",
      )
    }
    seen.add(switch)
    if switch == "\\o" {
      guard tokens.get(index + 1) is Some(range) &&
        range.length() >= 2 &&
        range.has_prefix("\"") &&
        range.has_suffix("\"") else {
        @failure.reject(
          "protected-content", "Table of contents requires a quoted heading range",
        )
      }
      let range = range[1:range.length() - 1].split("-").to_array()
      guard range is [start, end] else {
        @failure.reject(
          "protected-content", "Invalid table of contents heading range",
        )
      }
      first = @string.parse_int(start) catch { _ => 0 }
      last = @string.parse_int(end) catch { _ => 0 }
      guard first >= 1 && first <= last && last <= 9 else {
        @failure.reject(
          "protected-content", "Table of contents levels must be between one and nine",
        )
      }
      continue index + 2
    }
    continue index + 1
  }
  guard seen.contains("\\o") else {
    @failure.reject(
      "protected-content", "Table of contents requires a heading range",
    )
  }
  (first, last, seen.contains("\\h"), seen.contains("\\u"))
}

///|
fn WordTree::contents_profile(
  self : WordTree,
  paragraphs : Array[Int],
  markers : Array[Int],
  instruction : String,
  complete : Bool,
) -> TableOfContents {
  let mut first = 1
  let mut last = 3
  let mut hyperlink = false
  let mut outline = false
  let mut control = None
  let reason = try {
    guard complete && paragraphs.length() <= 4096 else {
      @failure.reject(
        "protected-content", "Incomplete or oversized table of contents field",
      )
    }
    let (start, end, links, levels) = toc_instruction(instruction)
    first = start
    last = end
    hyperlink = links
    outline = levels
    let begin = self.nodes[markers[0]]
    let finish = self.nodes[markers.last().unwrap()]
    let body = self.nodes[paragraphs[0]].parent
    if self.nodes[body].uri != word_uri || self.nodes[body].name != "body" {
      control = Some(self.toc_control(body, paragraphs))
    }
    guard self.children[body].filter(id => {
        self.nodes[id].start >= self.nodes[paragraphs[0]].start &&
        self.nodes[id].end <= self.nodes[paragraphs.last().unwrap()].end
      }) ==
      paragraphs else {
      @failure.reject(
        "protected-content", "Table of contents requires ordinary body paragraphs",
      )
    }
    let source = self.source[self.nodes[paragraphs[0]].start:self.nodes[paragraphs
      .last()
      .unwrap()].end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated table of contents source is protected",
      )
    }
    let mut state = 0
    for index, marker in markers {
      let node = self.nodes[marker]
      let run = self.nodes[node.parent]
      guard run.uri == word_uri &&
        run.name == "r" &&
        self.nodes[run.parent].parent == body else {
        @failure.reject(
          "protected-content", "Extended table of contents field markers",
        )
      }
      if node.name == "fldChar" {
        self.check_running_field_node(marker, [
          "fldCharType", "dirty", "fldLock",
        ])
        guard self.children[marker].is_empty() && node.text.trim().is_empty() else {
          @failure.reject(
            "protected-content", "Extended table of contents field marker",
          )
        }
        match (state, node.attribute("fldCharType", uri=word_uri)) {
          (0, Some("begin")) if index == 0 => state = 1
          (1, Some("separate")) => state = 2
          (2, Some("end")) if index == markers.length() - 1 => state = 3
          _ =>
            @failure.reject(
              "protected-content", "Unbalanced table of contents field markers",
            )
        }
      } else {
        guard state == 1 else {
          @failure.reject(
            "protected-content", "Table of contents instruction outside its field code",
          )
        }
        self.check_field_text(marker)
      }
    }
    for paragraph in [paragraphs[0], paragraphs.last().unwrap()] {
      for id in self.descendants(paragraph) {
        let node = self.nodes[id]
        if node.uri == word_uri &&
          node.name == "tab" &&
          self.nodes[node.parent].uri == word_uri &&
          self.nodes[node.parent].name == "tabs" {
          continue
        }
        if node.uri == word_uri &&
          [
            "t", "tab", "br", "cr", "drawing", "fldSimple", "bookmarkStart", "bookmarkEnd",
          ].contains(node.name) {
          guard node.start >= begin.start && node.end <= finish.end else {
            @failure.reject(
              "protected-content", "Table of contents shares its boundary paragraph with other content",
            )
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
  {
    paragraphs,
    markers,
    first,
    last,
    hyperlink,
    outline,
    instruction,
    reason,
    control,
  }
}

///|
fn WordTree::read_contents(
  self : WordTree,
) -> (Map[Int, TableOfContents], Set[Int]) {
  let contents : Map[Int, TableOfContents] = Map([])
  let protected_paragraphs : Set[Int] = Set([])
  guard self.child(0, "body") is Some(body) else {
    return (contents, protected_paragraphs)
  }
  let mut depth = 0
  let mut separated = false
  let mut overlong = false
  let mut instruction = ""
  let mut markers : Array[Int] = []
  let mut paragraphs : Array[Int] = []
  for id in self.descendants(body) {
    let node = self.nodes[id]
    if node.uri != word_uri {
      continue
    }
    if node.name == "p" && depth > 0 {
      paragraphs.push(id)
    }
    if node.name == "fldChar" {
      match node.attribute("fldCharType", uri=word_uri) {
        Some("begin") => {
          if depth == 0 {
            let paragraph = for ancestor = node.parent
                                ancestor >= 0
                                ancestor = self.nodes[ancestor].parent {
              if self.nodes[ancestor].uri == word_uri &&
                self.nodes[ancestor].name == "p" {
                break Some(ancestor)
              }
            } nobreak {
              None
            }
            guard paragraph is Some(paragraph) else { continue }
            instruction = ""
            separated = false
            overlong = false
            markers = [id]
            paragraphs = [paragraph]
          }
          depth += 1
        }
        Some("separate") if depth == 1 => {
          markers.push(id)
          separated = true
        }
        Some("end") if depth > 0 => {
          if depth == 1 {
            markers.push(id)
            if paragraphs.length() > 1 {
              for paragraph in paragraphs {
                protected_paragraphs.add(paragraph)
              }
            }
            let code = instruction
              .replace_all(old="\t", new=" ")
              .trim()
              .to_upper()
            if code.has_prefix("TOC ") ||
              code == "TOC" ||
              code.has_prefix("INDEX ") ||
              code == "INDEX" {
              let value = self.contents_profile(
                paragraphs,
                markers,
                instruction,
                separated && !overlong,
              )
              for paragraph in paragraphs {
                contents[paragraph] = value
              }
            }
          }
          depth -= 1
        }
        _ => ()
      }
    } else if node.name == "instrText" && depth == 1 && !separated {
      markers.push(id)
      if instruction.length() <= 256 {
        let remaining = 257 - instruction.length()
        let mut length = remaining.min(node.text.length())
        overlong = overlong || node.text.length() > remaining
        if length > 0 &&
          length < node.text.length() &&
          node.text[length - 1].to_int() >= 0xD800 &&
          node.text[length - 1].to_int() <= 0xDBFF {
          length -= 1
        }
        instruction += node.text[:length].to_owned()
      }
    }
  }
  if depth > 0 && paragraphs.length() > 1 {
    for paragraph in paragraphs {
      protected_paragraphs.add(paragraph)
    }
  }
  let code = instruction.replace_all(old="\t", new=" ").trim().to_upper()
  if depth > 0 &&
    (
      code.has_prefix("TOC ") ||
      code == "TOC" ||
      code.has_prefix("INDEX ") ||
      code == "INDEX"
    ) {
    let value = self.contents_profile(paragraphs, markers, instruction, false)
    for paragraph in paragraphs {
      contents[paragraph] = value
    }
  }
  (contents, protected_paragraphs)
}

///|
/// Lists native body TOC fields and their supported heading range without changing source or history.
pub fn Session::table_of_contents(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let items : Array[Json] = []
  for id in tree.order {
    if tree.contents.get(id) is Some(toc) &&
      toc.paragraphs[0] == id &&
      !toc.instruction.trim().to_upper().has_prefix("INDEX") {
      items.push({
        "paragraph": id,
        "endParagraph": toc.paragraphs.last().unwrap(),
        "firstLevel": toc.first,
        "lastLevel": toc.last,
        "hyperlink": toc.hyperlink,
        "outline": toc.outline,
        "instruction": toc.instruction,
        "reason": toc.reason,
      })
      guard items.length() <= 256 else {
        @failure.reject("limit-exceeded", "Too many table of contents fields")
      }
    }
  }
  { "revision": revision, "items": items }
}
