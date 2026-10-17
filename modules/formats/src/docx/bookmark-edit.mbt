///|
pub(all) enum BookmarkEdit {
  CreateBookmark(String, Selection)
  RenameBookmark(String, String)
  RemoveBookmark(String)
  GoToBookmark(String)
}

///|
fn bookmark_boundary(
  document : @xml.Document,
  position : Position,
  markup : String,
) -> @xml.SourceChange {
  let tree = WordTree::new(document)
  let p = tree.nodes[position.paragraph]
  let texts = docx_texts(tree)
  let counts : Map[Int, Int] = Map([])
  for t in texts {
    if t.paragraph == p.id {
      counts[t.run] = counts.get(t.run).unwrap_or(0) +
        inline_text(tree.nodes[t.id]).length()
    }
  }
  let at = for run in tree.paragraph_runs(p.id); offset = 0 {
    let node = tree.nodes[run]
    if position.offset == offset {
      break node.start
    }
    let next = offset + counts.get(run).unwrap_or(0)
    if position.offset == next {
      break node.end
    }
    continue next
  } nobreak {
    p.closing_start
  }
  if p.empty {
    {
      node: p.id,
      offset: p.opening_end - p.start - 2,
      length: 2,
      xml: ">\{markup}</\{p.qualified}>",
    }
  } else {
    { node: p.id, offset: at - p.start, length: 0, xml: markup, }
  }
}

///|
fn Session::split_bookmark_boundary(
  self : Session,
  document : @xml.Document,
  selection : Selection,
) -> (@xml.Document, Array[@xml.Edit]) raise @failure.Failure {
  let range = self.formatting_range(document, selection)
  let selection = if range.start.paragraph == range.end.paragraph &&
    range.start.offset == range.end.offset {
    { anchor: { ..range.start, offset: 0, }, focus: range.end, }
  } else {
    selection
  }
  match
    self.format_character_document(
      document,
      selection,
      CharacterFormat::new(),
      split=true,
    ) {
    Some((candidate, edit)) => (candidate, [edit])
    None => (document, [])
  }
}

///|
fn Session::restore_bookmarks(
  self : Session,
  prepared : PreparedEdit,
) -> PreparedEdit raise @failure.Failure {
  let before = WordTree::new(self.document())
  if !before.order.any(id => before.is_bookmark(id)) {
    return prepared
  }
  let next = WordTree::new(prepared.document)
  let present : Map[String, Bool] = Map([])
  for id in next.order {
    if next.is_bookmark(id) {
      let n = next.nodes[id]
      present[n.name + ":" + n.attribute("id", uri=word_uri).unwrap_or("")] = true
    }
  }
  let lost : Map[Int, Bool] = Map([])
  for b in before.bookmarks() {
    if !b.reason.is_empty() {
      continue
    }
    for id in [b.start, b.end] {
      let n = before.nodes[id]
      if !present.contains(n.name + ":" + b.key) {
        lost[id] = true
      }
    }
  }
  if lost.is_empty() {
    return prepared
  }
  let after = prepared.edit.after.unwrap()
  let (document, steps) = self.split_bookmark_boundary(prepared.document, after)
  let starts = StringBuilder()
  let ends = StringBuilder()
  for id in before.order {
    if lost.contains(id) {
      let buffer = if before.nodes[id].name == "bookmarkStart" {
        starts
      } else {
        ends
      }
      buffer.write_string(before.standalone_markup(self.document(), id))
    }
  }
  let start = starts.to_string()
  let end = ends.to_string()
  let boundary = bookmark_boundary(document, after.focus, start + end)
  let current = WordTree::new(document)
  let mut left = boundary.offset
  let mut right = boundary.offset
  for id, position in current.inline_marker_positions() {
    if !current.is_bookmark(id) {
      continue
    }
    if position.paragraph == after.focus.paragraph &&
      position.offset == after.focus.offset {
      let marker = current.nodes[id]
      left = left.min(marker.start - current.nodes[position.paragraph].start)
      right = right.max(marker.end - current.nodes[position.paragraph].start)
    }
  }
  // At a collapsed boundary, starts precede retained markers and ends follow them.
  let changes = if left == right || current.nodes[after.focus.paragraph].empty {
    [boundary]
  } else {
    let items : Array[@xml.SourceChange] = []
    if !start.is_empty() {
      items.push({ ..boundary, offset: left, xml: start, })
    }
    if !end.is_empty() {
      items.push({ ..boundary, offset: right, xml: end, })
    }
    items
  }
  let (candidate, step) = document.edit_source(changes)
  let xml = prepared.edit.xml.copy()
  xml.append(steps)
  xml.push(step)
  let bytes = xml.iter().fold(init=0, (total, edit) => total + edit_bytes(edit))
  guard bytes <= history_byte_limit else {
    @failure.reject("limit-exceeded", "Bookmark history exceeds budget")
  }
  {
    ..prepared,
    document: candidate,
    typing_text: None,
    edit: { ..prepared.edit, xml, bytes, },
  }
}

///|
fn Session::bookmark_references(
  self : Session,
  name : String,
) -> Array[Int] raise @failure.Failure {
  let paths = self.opc.names.copy()
  for path, _ in self.parts {
    paths[path.to_lower()] = path
  }
  let links : Array[Int] = []
  for path in paths.values() {
    if !path.to_lower().has_suffix(".xml") {
      continue
    }
    let document = self.part_xml(path)
    let nodes = document.nodes()
    let fields = StringBuilder()
    for node in nodes {
      if node.uri != word_uri {
        continue
      }
      if node.name == "instrText" {
        fields.write_string(node.text)
      }
      if node.name == "fldSimple" {
        fields.write_string(node.attribute("instr", uri=word_uri).unwrap_or(""))
      }
      if node.attribute("anchor", uri=word_uri).map(s => s.to_lower()) ==
        Some(name.to_lower()) {
        guard path == self.main && node.name == "hyperlink" else {
          @failure.reject(
            "protected-content", "Bookmark references in other document parts require editing support",
          )
        }
        links.push(node.id)
      }
    }
    guard !fields.to_string().to_lower().contains(name.to_lower()) else {
      @failure.reject(
        "protected-content", "Bookmark fields require atomic field editing support",
      )
    }
  }
  links
}

///|
/// Creates, renames or removes a bookmark in one source and history transaction.
pub fn Session::edit_bookmark(
  self : Session,
  revision : Int,
  change : BookmarkEdit,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let tree = WordTree::new(original)
  let catalog = tree.bookmarks()
  let mut document = original
  let xml : Array[@xml.Edit] = []
  let changes : Array[@xml.SourceChange] = []
  let affected : Array[Int] = []
  match change {
    GoToBookmark(name) => return self.go_to_bookmark(revision, name)
    CreateBookmark(name, selection) => {
      check_bookmark_name(name)
      guard catalog.length() < 4096 &&
        !catalog.any(b => b.name.to_lower() == name.to_lower()) else {
        @failure.reject(
          "invalid-operation", "Bookmark name already exists or catalog is full",
        )
      }
      let range = self.formatting_range(original, selection)
      affected.append(range.paragraphs)
      let (candidate, steps) = self.split_bookmark_boundary(original, selection)
      document = candidate
      xml.append(steps)
      let used : Map[String, Bool] = Map([])
      for id in tree.order {
        if tree.is_bookmark(id) {
          let key = tree.nodes[id].attribute("id", uri=word_uri).unwrap_or("")
          used[key] = true
          let number = @string.parse_int(key) catch { _ => -1 }
          if number >= 0 {
            used[number.to_string()] = true
          }
        }
      }
      let key = for i in 0..<16384 {
        if !used.contains(i.to_string()) {
          break i.to_string()
        }
      } nobreak {
        @failure.reject("limit-exceeded", "Bookmark identities exhausted")
      }
      let start = "<od:bookmarkStart xmlns:od=\"\{word_uri}\" od:id=\"\{key}\" od:name=\"\{name}\"/>"
      let end = "<od:bookmarkEnd xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/>"
      if range.start.paragraph == range.end.paragraph &&
        range.start.offset == range.end.offset {
        changes.push(bookmark_boundary(document, range.start, start + end))
      } else {
        changes.push(bookmark_boundary(document, range.start, start))
        changes.push(bookmark_boundary(document, range.end, end))
      }
    }
    RenameBookmark(name, _) | RemoveBookmark(name) => {
      let next = match change {
        RenameBookmark(_, replacement) => Some(replacement)
        _ => None
      }
      guard catalog.iter().find_first(b => b.name.to_lower() == name.to_lower())
        is Some(b) &&
        b.reason.is_empty() else {
        @failure.reject("protected-content", "Unknown or protected bookmark")
      }
      if next is Some(value) {
        check_bookmark_name(value)
        if value == b.name {
          return self.edit_result([])
        }
        guard !catalog.any(other => {
          other.key != b.key && other.name.to_lower() == value.to_lower()
        }) else {
          @failure.reject("invalid-operation", "Bookmark name already exists")
        }
      }
      let links = self.bookmark_references(name)
      affected.push(b.selection.unwrap().anchor.paragraph)
      affected.push(b.selection.unwrap().focus.paragraph)
      for id in links {
        tree.check_hyperlink(id)
        let n = tree.nodes[id]
        tree.check_editable_paragraph(n.parent, part=self.main, pictures=true)
        guard n.attribute(
            "id",
            uri="http://schemas.openxmlformats.org/officeDocument/2006/relationships",
          )
          is None &&
          n.attribute("docLocation", uri=word_uri) is None else {
          @failure.reject(
            "protected-content", "Extended bookmark links require editing support",
          )
        }
        affected.push(n.parent)
        if next is Some(value) {
          let a = n.attributes
            .iter()
            .find_first(a => a.uri == word_uri && a.name == "anchor")
            .unwrap()
          changes.push({
            node: id,
            offset: a.start - n.start,
            length: a.end - a.start,
            xml: property_attribute(value),
          })
        } else {
          guard !n.empty else {
            @failure.reject(
              "protected-content", "Empty hyperlink source requires editing support",
            )
          }
          for child in tree.children[id] {
            if child == b.start || child == b.end {
              continue
            }
            let child = tree.nodes[child]
            let extra = tree.namespace_additions(child.id, n.parent)
            if !extra.is_empty() {
              changes.push({
                node: child.id,
                offset: child.opening_end -
                child.start -
                (if child.empty { 2 } else { 1 }),
                length: 0,
                xml: extra,
              })
            }
          }
          changes.push({
            node: n.parent,
            offset: n.start - tree.nodes[n.parent].start,
            length: n.opening_end - n.start,
            xml: "",
          })
          changes.push({
            node: n.parent,
            offset: n.closing_start - tree.nodes[n.parent].start,
            length: n.end - n.closing_start,
            xml: "",
          })
        }
      }
      if next is Some(value) {
        let n = tree.nodes[b.start]
        let a = n.attributes
          .iter()
          .find_first(a => a.uri == word_uri && a.name == "name")
          .unwrap()
        changes.push({
          node: b.start,
          offset: a.start - n.start,
          length: a.end - a.start,
          xml: property_attribute(value),
        })
      } else {
        for id in [b.start, b.end] {
          let n = tree.nodes[id]
          changes.push({
            node: n.parent,
            offset: n.start - tree.nodes[n.parent].start,
            length: n.end - n.start,
            xml: "",
          })
        }
      }
    }
  }
  let (candidate, step) = document.edit_source(changes)
  xml.push(step)
  let bytes = xml.iter().fold(init=0, (total, edit) => total + edit_bytes(edit))
  guard bytes <= history_byte_limit else {
    @failure.reject("limit-exceeded", "Bookmark history exceeds budget")
  }
  self.commit_edit(
    {
      xml,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: affected,
      bytes,
    },
    candidate,
    bookmark_edit=true,
  )
  self.edit_result(affected)
}

///|
/// Places the caret at a committed bookmark's start without changing history.
fn Session::go_to_bookmark(
  self : Session,
  revision : Int,
  name : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard WordTree::new(self.document())
    .bookmarks()
    .iter()
    .find_first(b => b.name.to_lower() == name.to_lower() && b.reason.is_empty())
    is Some(b) else {
    @failure.reject("invalid-operation", "Unknown or protected bookmark")
  }
  let p = b.selection.unwrap().anchor
  self.select(revision, { anchor: p, focus: p, })
}
