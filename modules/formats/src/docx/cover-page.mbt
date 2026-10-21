///|
let cover_bookmark = "_OpenDocumentCoverPage"

///|
fn WordTree::cover_page(
  self : WordTree,
) -> (Array[Int], String)? raise @failure.Failure {
  let covers = self
    .bookmarks()
    .filter(b => b.name.to_lower() == cover_bookmark.to_lower())
  guard !covers.is_empty() else { return None }
  guard covers.length() == 1 &&
    covers[0].reason.is_empty() &&
    covers[0].selection is Some(selection) else {
    @failure.reject("protected-content", "Incomplete cover page bookmark")
  }
  let body = self.child(0, "body").unwrap()
  let children = self.children[body]
  let first = selection.anchor.paragraph
  let last = selection.focus.paragraph
  guard children.get(0) == Some(first) &&
    selection.anchor.offset == 0 &&
    selection.focus.offset == 0 &&
    first != last &&
    children.search(last) is Some(end) else {
    @failure.reject(
      "protected-content", "Cover page must begin at the document start",
    )
  }
  let paragraphs = children[:end + 1].to_owned()
  for id in paragraphs {
    guard self.nodes[id].uri == word_uri && self.nodes[id].name == "p" else {
      @failure.reject(
        "protected-content", "Cover replacement requires ordinary paragraphs",
      )
    }
    self.check_editable_paragraph(id, part="", pictures=true, fields=true)
  }
  let start = self.nodes[first].start
  let finish = self.nodes[last].end
  let source = self.source[start:finish]
  guard !source.contains("<!--") &&
    !source.contains("<?") &&
    self.order.all(id => {
      let node = self.nodes[id]
      node.start < start ||
      node.end > finish ||
      !self.is_bookmark(id) ||
      id == covers[0].start ||
      id == covers[0].end
    }) &&
    docx_texts(self).all(t => {
      t.paragraph != last || inline_text(self.nodes[t.id]).is_empty()
    }) &&
    self.child(last, "pPr").bind(id => self.child(id, "pageBreakBefore"))
    is Some(_) else {
    @failure.reject(
      "protected-content", "Retained cover content requires editing support",
    )
  }
  Some((paragraphs, covers[0].key))
}

///|
fn cover_markup(
  title : String,
  subtitle : String,
  key : String,
) -> String raise @failure.Failure {
  let start = "<od:bookmarkStart od:id=\"\{key}\" od:name=\"\{cover_bookmark}\"/>"
  let end = "<od:bookmarkEnd od:id=\"\{key}\"/>"
  let paragraph = fn(
    text : String,
    size : Int,
    before : Int,
    marker : String,
    bold : Bool,
  ) raise @failure.Failure {
    "<od:p xmlns:od=\"\{word_uri}\"><od:pPr><od:jc od:val=\"center\"/><od:ind od:left=\"0\" od:right=\"0\" od:firstLine=\"0\"/><od:spacing od:before=\"\{before}\" od:after=\"480\" od:line=\"240\" od:lineRule=\"auto\"/><od:keepLines/><od:keepNext/><od:pageBreakBefore od:val=\"0\"/><od:numPr><od:numId od:val=\"0\"/></od:numPr></od:pPr>\{marker}<od:r><od:rPr><od:sz od:val=\"\{size}\"/><od:szCs od:val=\"\{size}\"/><od:b od:val=\"\{if bold { 1 } else { 0 }}\"/></od:rPr><od:t xml:space=\"preserve\">\{@xml.escape_text(text)}</od:t></od:r></od:p>"
  }
  paragraph(title, 64, 2880, start, true) +
  (if subtitle.is_empty() { "" } else { paragraph(subtitle, 32, 0, "", false) }) +
  "<od:p xmlns:od=\"\{word_uri}\"><od:pPr><od:pageBreakBefore/><od:keepNext od:val=\"0\"/><od:spacing od:before=\"0\" od:after=\"0\"/></od:pPr>\{end}</od:p>"
}

///|
/// Inserts or replaces an editable title cover; null removes the owned cover.
pub fn Session::set_cover_page(
  self : Session,
  revision : Int,
  title : String?,
  subtitle : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard title
    .map(t => !t.trim().is_empty() && t.length() <= 256)
    .unwrap_or(subtitle.is_empty()) &&
    subtitle.length() <= 512 &&
    [title.unwrap_or(""), subtitle].all(text => {
      @xml.valid_text(text) &&
      text
      .iter()
      .all(c => {
        c.to_int() >= 32 && c != '\u007f' && c != '\u2028' && c != '\u2029'
      })
    }) else {
    @failure.reject(
      "invalid-operation", "Cover requires a single-line title of 1-256 units and subtitle of at most 512 units",
    )
  }
  let original = self.document()
  let tree = WordTree::new(original)
  let cover = tree.cover_page()
  if title is None && cover is None {
    return self.edit_state()
  }
  guard cover is Some(_) || tree.bookmarks().length() < 4096 else {
    @failure.reject("limit-exceeded", "Cover bookmark catalog is full")
  }
  let section = self.editable_page_section(tree)
  // shortcut: A full-width cover in a column document needs section-scoped pagination.
  guard tree.page_columns(section).count == 1 else {
    @failure.reject(
      "protected-content", "Cover pages require a single-column document",
    )
  }
  if title is None {
    guard self
      .bookmark_references(cover_bookmark)
      .values()
      .all(ids => ids.is_empty()) &&
      tree.page_reference_renames(cover_bookmark, cover_bookmark).is_empty() else {
      @failure.reject(
        "protected-content", "Remove references to the cover bookmark first",
      )
    }
  }
  let body = tree.child(0, "body").unwrap()
  let old = cover.map(c => c.0).unwrap_or([])
  let key = cover.map(c => c.1).unwrap_or_else(() => tree.next_bookmark_key())
  let start = old
    .get(0)
    .map(id => tree.nodes[id].start)
    .unwrap_or(tree.nodes[body].opening_end)
  let finish = old.last().map(id => tree.nodes[id].end).unwrap_or(start)
  let markup = title.map(t => cover_markup(t, subtitle, key)).unwrap_or("")
  let (candidate, edit) = original.edit_source([
    {
      node: body,
      offset: start - tree.nodes[body].start,
      length: finish - start,
      xml: markup,
    },
  ])
  let updated = WordTree::new(candidate)
  let flow = self.flow_from(candidate)
  if title is Some(_) {
    let first = flow.paragraphs[0]
    guard first.before + first.after <
      flow.page.height - flow.page.top - flow.page.bottom else {
      @failure.reject(
        "layout-overflow", "Cover title and subtitle must fit on one page",
      )
    }
  }
  let layout = @layout.paginate(probe, flow, profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject("protected-content", "Cover page requires supported layout")
  }
  let paragraphs = flow.paragraphs.map(p => p.id)
  let position = if title is Some(title) {
    let inserted = updated.cover_page().unwrap().0
    let content = inserted[:inserted.length() - 1]
    guard layout.pages.length() >= 2 &&
      content.all(id => layout.pages[0].lines.any(line => line.paragraph == id)) &&
      layout.pages[1].lines.any(line => {
        line.paragraph == inserted.last().unwrap()
      }) &&
      layout.pages[1:].all(page => {
        !page.lines.any(line => content.contains(line.paragraph))
      }) else {
      @failure.reject(
        "layout-overflow", "Cover title and subtitle must fit on one page",
      )
    }
    Position::{
      paragraph: inserted[0],
      offset: title.length(),
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    }
  } else {
    guard paragraphs.get(0) is Some(first) else {
      @failure.reject(
        "protected-content", "Cover removal requires remaining document content",
      )
    }
    Position::{
      paragraph: first,
      offset: 0,
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    }
  }
  self.commit_edit(
    {
      xml: [edit],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: position, focus: position, }),
      paragraphs,
      bytes: edit_bytes(edit),
    },
    candidate,
    bookmark_edit=true,
  )
  self.edit_result(paragraphs)
}
