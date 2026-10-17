///|
pub(all) enum CommentEdit {
  AddComment(String, String, String, String, Selection)
  ReplyComment(String, String, String, String, String)
  SetCommentResolved(String, Bool)
  UpdateComment(String, String)
  RemoveComment(String)
  GoToComment(String)
}

///|
fn comment_text(value : String) -> String raise @failure.Failure {
  guard value.length() <= 32767 &&
    !value.trim().is_empty() &&
    @xml.valid_text(value) else {
    @failure.reject(
      "invalid-text", "Comment text must be nonempty and within 32767 UTF-16 units",
    )
  }
  value.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// Edits classic local comments and body anchors in one exact source transaction.
pub fn Session::edit_comment(
  self : Session,
  revision : Int,
  change : CommentEdit,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let source = self.comment_source()
  let tree = WordTree::new(original)
  let anchors = tree.comment_anchors()
  let entries = source.map(s => s.entries).unwrap_or([])
  let mut comment_part = source.map(s => s.part)
  let mut extended_part = source.bind(s => s.extended.map(e => e.0))
  guard anchors.all(a => a.reason.is_empty() && entries.any(e => e.key == a.key)) else {
    @failure.reject("protected-content", "Comments have unresolved anchors")
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let part_edits : Map[String, Array[@xml.Edit]] = Map([])
  let xml : Array[@xml.Edit] = []
  let affected : Array[Int] = []
  let changes : Array[@xml.SourceChange] = []
  let mut document = original
  match change {
    AddComment(raw, author, initials, date, _)
    | ReplyComment(_, raw, author, initials, date) => {
      let text = comment_text(raw)
      guard !author.trim().is_empty() &&
        author.length() <= 255 &&
        initials.length() <= 32 &&
        @xml.valid_text(author) &&
        @xml.valid_text(initials) &&
        !author.iter().any(c => c < ' ') &&
        !initials.iter().any(c => c < ' ') else {
        @failure.reject(
          "invalid-operation", "Comments require an explicit bounded author",
        )
      }
      check_comment_date(date)
      guard entries.length() < 4096 &&
        entries
        .iter()
        .fold(init=text.length(), (sum, e) => sum + e.text.length()) <=
        1048576 else {
        @failure.reject("limit-exceeded", "Comments exceed budget")
      }
      let parent = match change {
        ReplyComment(key, _, _, _, _) => {
          ignore(comment_key(key))
          guard entries.iter().find_first(e => e.key == key) is Some(root) &&
            root.parent is None else {
            @failure.reject(
              "invalid-operation", "Replies require an existing root comment",
            )
          }
          Some(root)
        }
        _ => None
      }
      let selection = match change {
        AddComment(_, _, _, _, selection) => selection
        _ => {
          guard anchors.iter().find_first(a => a.key == parent.unwrap().key)
            is Some(anchor) &&
            anchor.selection is Some(selection) else {
            @failure.reject(
              "protected-content", "Reply root has no editable anchor",
            )
          }
          selection
        }
      }
      let range = self.formatting_range(original, selection)
      affected.append(range.paragraphs)
      let key = for i in 0..<16384 {
        if !entries.any(e => e.key == i.to_string()) &&
          !anchors.any(a => a.key == i.to_string()) {
          break i.to_string()
        }
      } nobreak {
        @failure.reject("limit-exceeded", "Comment identities exhausted")
      }
      let parent_para = if parent is Some(root) {
        let (para, path) = self.ensure_comment_thread(
          source.unwrap(),
          root,
          parts,
          created,
          part_edits,
        )
        extended_part = Some(path)
        Some(para)
      } else {
        None
      }
      let current = source.map(s => parts.get(s.part).unwrap_or(s.document))
      let para = if extended_part is Some(_) {
        next_comment_para(current.unwrap())
      } else {
        ""
      }
      let markup = "<od:comment xmlns:od=\"\{word_uri}\" od:id=\"\{key}\" od:author=\"\{property_attribute(author)}\" od:initials=\"\{property_attribute(initials)}\" od:date=\"\{date}\">\{comment_body(None, None, text, para~)}</od:comment>"
      if source is Some(source) {
        let (next, edit) = append_part_xml(current.unwrap(), markup)
        ignore(read_doc_comments(next))
        store_comment_edit(source.part, next, edit, parts, created, part_edits)
      } else {
        comment_part = Some(
          self.create_comments_part(markup, parts, created, part_edits),
        )
      }
      if extended_part is Some(path) {
        let extended = match parts.get(path) {
          Some(document) => document
          None => self.part_xml(path)
        }
        let (next, edit) = append_part_xml(
          extended,
          comment_thread_markup(
            para,
            parent_para,
            parent.map(p => p.done).unwrap_or(false),
          ),
        )
        store_comment_edit(path, next, edit, parts, created, part_edits)
      }
      if parent is None {
        let (next, steps) = self.split_bookmark_boundary(document, selection)
        document = next
        xml.append(steps)
        let start = "<od:commentRangeStart xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/>"
        let end = "<od:commentRangeEnd xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/><od:r xmlns:od=\"\{word_uri}\"><od:commentReference od:id=\"\{key}\"/></od:r>"
        if range.start.paragraph == range.end.paragraph &&
          range.start.offset == range.end.offset {
          changes.push(bookmark_boundary(document, range.start, start + end))
        } else {
          changes.push(bookmark_boundary(document, range.start, start))
          changes.push(bookmark_boundary(document, range.end, end))
        }
      }
    }
    UpdateComment(key, _)
    | RemoveComment(key)
    | GoToComment(key)
    | SetCommentResolved(key, _) => {
      ignore(comment_key(key))
      guard source is Some(source) &&
        entries.iter().find_first(e => e.key == key) is Some(entry) &&
        anchors.iter().find_first(a => a.key == entry.parent.unwrap_or(key))
        is Some(anchor) else {
        @failure.reject(
          "invalid-operation", "Comment or editable anchor is missing",
        )
      }
      let selection = anchor.selection.unwrap()
      if change is GoToComment(_) {
        self.selection = Some(selection)
        self.typing_text = None
        self.typing_format = None
        self.input_group = None
        self.vertical_x = None
        self.navigation_layout = -1
        return self.edit_result([])
      }
      affected.push(selection.anchor.paragraph)
      affected.push(selection.focus.paragraph)
      if change is SetCommentResolved(_, done) {
        let root = entries
          .iter()
          .find_first(e => e.key == entry.parent.unwrap_or(key))
          .unwrap()
        let members = entries.filter(e => {
          e.key == root.key || e.parent == Some(root.key)
        })
        if members.all(e => e.done == done) {
          return self.edit_result([])
        }
        let (para, path) = self.ensure_comment_thread(
          source, root, parts, created, part_edits,
        )
        extended_part = Some(path)
        let extended = match parts.get(path) {
          Some(document) => document
          None => self.part_xml(path)
        }
        let ext_tree = WordTree::new(extended)
        let targets = members.map(e => {
          if e.key == root.key {
            para
          } else {
            e.para
          }
        })
        let updates : Array[@xml.SourceChange] = []
        for id in ext_tree.children[0] {
          let n = ext_tree.nodes[id]
          if targets.contains(
              comment_para_id(
                n.attribute("paraId", uri=comment_extended_uri).unwrap_or(""),
              ),
            ) {
            let value = if done { "1" } else { "0" }
            updates.push(
              comment_attribute_change(
                ext_tree, id, comment_extended_uri, "done", value,
              ),
            )
          }
        }
        let (next, edit) = extended.edit_source(updates)
        store_comment_edit(path, next, edit, parts, created, part_edits)
      } else {
        let node = source.tree.nodes[entry.node]
        let updates : Array[@xml.SourceChange] = []
        if change is UpdateComment(_, raw) {
          let text = comment_text(raw)
          if text == entry.text {
            return self.edit_result([])
          }
          guard entries
            .iter()
            .fold(init=text.length() - entry.text.length(), (sum, e) => {
              sum + e.text.length()
            }) <=
            1048576 else {
            @failure.reject("limit-exceeded", "Comments exceed text budget")
          }
          let body = comment_body(
            Some(source.document),
            Some(node.id),
            text,
            para=entry.para,
          )
          updates.push(comment_body_change(node, body))
        } else {
          let removed = entries.filter(e => {
            e.key == key || e.parent == Some(key)
          })
          for e in removed {
            let n = source.tree.nodes[e.node]
            updates.push({
              node: n.parent,
              offset: n.start - source.tree.nodes[n.parent].start,
              length: n.end - n.start,
              xml: "",
            })
          }
          for anchor in anchors.filter(a => removed.any(e => e.key == a.key)) {
            for id in [anchor.start, anchor.end, Some(anchor.reference)] {
              if id is Some(id) {
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
          if source.extended is Some((path, extended)) {
            let ext_tree = WordTree::new(extended)
            let removals : Array[@xml.SourceChange] = ext_tree.children[0]
              .filter(id => {
                removed.any(e => {
                  Some(e.para) ==
                  ext_tree.nodes[id]
                  .attribute("paraId", uri=comment_extended_uri)
                  .map(comment_para_id)
                })
              })
              .map(id => {
                let n = ext_tree.nodes[id]
                {
                  node: n.parent,
                  offset: n.start - ext_tree.nodes[n.parent].start,
                  length: n.end - n.start,
                  xml: "",
                }
              })
            if !removals.is_empty() {
              let (next, edit) = extended.edit_source(removals)
              store_comment_edit(path, next, edit, parts, created, part_edits)
            }
          }
        }
        let (next, edit) = source.document.edit_source(updates)
        ignore(read_doc_comments(next))
        store_comment_edit(source.part, next, edit, parts, created, part_edits)
      }
    }
  }
  if !changes.is_empty() {
    let (next, edit) = document.edit_source(changes)
    document = next
    xml.push(edit)
  }
  guard WordTree::new(document).comment_anchors().all(a => a.reason.is_empty()) else {
    @failure.reject("protected-content", "Comment anchor candidate is invalid")
  }
  if comment_part is Some(path) && extended_part is Some(extension) {
    let body = match parts.get(path) {
      Some(document) => document
      None => self.part_xml(path)
    }
    let extended = match parts.get(extension) {
      Some(document) => document
      None => self.part_xml(extension)
    }
    ignore(read_comment_threads(read_doc_comments(body), extended))
  }
  let mut bytes = xml_part_edit_bytes(part_edits, created)
  for step in xml {
    guard edit_bytes(step) <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Comment history exceeds budget")
    }
    bytes += edit_bytes(step)
  }
  self.commit_edit(
    {
      xml,
      parts: part_edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: affected,
      bytes,
    },
    document,
    parts~,
    comment_edit=true,
  )
  self.edit_result(affected)
}
