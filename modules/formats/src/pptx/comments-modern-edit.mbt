///|
fn Session::modern_comment_ids(
  self : Session,
  count : Int,
) -> Array[String] raise @failure.Failure {
  let reserved : Map[String, Bool] = Map([])
  let mut work = 0
  for link in self.relationships() {
    if link.external ||
      ![
        modern_comment_relationship + "/comments",
        modern_comment_relationship + "/authors",
      ].contains(link.kind) {
      continue
    }
    for node in self.part_document(link.target).nodes() {
      work += 1
      guard work <= 65536 else {
        @failure.reject(
          "limit-exceeded", "Modern comment identity scan exceeds budget",
        )
      }
      if node.attribute("id") is Some(id) {
        reserved[id.to_upper()] = true
      }
    }
  }
  let result : Array[String] = []
  let mut next = 1L
  while result.length() < count {
    let id = document_guid(next)
    next += 1
    guard next <= 65538L else {
      @failure.reject("limit-exceeded", "Modern comment identities exhausted")
    }
    if !reserved.contains(id) {
      result.push(id)
      reserved[id] = true
    }
  }
  result
}

///|
fn modern_comment_text(
  tree : Tree?,
  body : @xml.Node?,
  text : String,
) -> String raise @failure.Failure {
  let paragraphs = match (tree, body) {
    (Some(tree), Some(body)) => tree.all(body.id, "p")
    _ => []
  }
  let output = StringBuilder()
  let mut units = 256L
  output.write_string(
    "<mc:txBody xmlns:mc=\"\{modern_comment_uri}\" xmlns:a=\"\{drawing_uri}\"><a:bodyPr/><a:lstStyle/>",
  )
  for i, line in text.split("\n").to_array() {
    let paragraph = match paragraphs.get(i) {
      Some(p) => Some(p)
      None => paragraphs.get(0)
    }
    let style = match (tree, paragraph) {
      (Some(tree), Some(p)) =>
        tree
        .all(p.id, "r")
        .get(0)
        .bind(r => tree.all(r.id, "rPr").get(0))
        .map(node => tree.standalone_markup(tree.document, node.id))
        .unwrap_or("")
      _ => ""
    }
    let end = match (tree, paragraph) {
      (Some(tree), Some(p)) =>
        tree
        .all(p.id, "endParaRPr")
        .get(0)
        .map(node => tree.standalone_markup(tree.document, node.id))
        .unwrap_or("")
      _ => ""
    }
    units += style.length().to_int64() +
      end.length().to_int64() +
      line.length().to_int64() * 6 +
      128
    guard units <= 1048576L else {
      @failure.reject(
        "limit-exceeded", "Modern comment text source exceeds budget",
      )
    }
    output.write_string(
      "<a:p><a:r>\{style}<a:t xml:space=\"preserve\">\{@xml.escape_text(line.to_owned())}</a:t></a:r>\{end}</a:p>",
    )
  }
  output.write_string("</mc:txBody>")
  output.to_string()
}

///|
fn Session::edit_modern_comments(
  self : Session,
  tree : Tree?,
  author_tree : Tree?,
  slide : String,
  change : SlideEdit,
) -> Json raise @failure.Failure {
  guard [tree, author_tree].all(t => {
    t.map(t => t.document.nodes()[0].uri == modern_comment_uri).unwrap_or(true)
  }) else {
    @failure.reject(
      "protected-content", "Mixed comment formats require editing support",
    )
  }
  let entries = tree.map(read_modern_comments).unwrap_or([])
  if tree is Some(tree) {
    self.check_comment_anchors(tree, slide)
  }
  let authors = author_tree.map(read_modern_authors).unwrap_or([])
  guard entries.all(e => authors.any(a => a.id == e.author)) else {
    @failure.reject("protected-content", "Comment author is missing")
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let tree = tree.unwrap_or_else(() => {
    self.create_comment_part(
      slide,
      "comments",
      "cmLst",
      parts,
      created,
      edits,
      modern=true,
    )
  })
  let changes : Array[@xml.SourceChange] = []
  match change {
    AddComment(text, name, initials, date, parent) => {
      let text = comment_text(text)
      check_comment_author(name, initials)
      check_comment_date(date)
      guard entries.length() < 4096 &&
        entries
        .iter()
        .fold(init=text.length(), (sum, e) => sum + e.value.length()) <=
        1048576 else {
        @failure.reject("limit-exceeded", "Slide comments exceed budget")
      }
      let parent = parent.map(id => {
        check_comment_id(id)
        guard entries.iter().find_first(e => e.id == id) is Some(entry) &&
          entry.parent is None else {
          @failure.reject(
            "invalid-operation", "Reply to an existing root comment",
          )
        }
        entry
      })
      let matching = authors.filter(a => {
        a.name == name && a.initials == initials
      })
      guard matching.length() <= 1 else {
        @failure.reject(
          "protected-content", "Ambiguous comment authors are protected",
        )
      }
      guard !matching.is_empty() || authors.length() < 4096 else {
        @failure.reject("limit-exceeded", "Comment authors exceed budget")
      }
      let ids = self.modern_comment_ids(if matching.is_empty() { 2 } else { 1 })
      let author = matching.get(0).map(a => a.id).unwrap_or_else(() => ids[1])
      if matching.is_empty() {
        let authors = author_tree.unwrap_or_else(() => {
          self.create_comment_part(
            self.main.part,
            "commentAuthors",
            "authorLst",
            parts,
            created,
            edits,
            modern=true,
          )
        })
        let markup = "<mc:author xmlns:mc=\"\{modern_comment_uri}\" id=\"\{author}\" name=\"\{xml_attribute(name)}\" initials=\"\{xml_attribute(initials)}\" userId=\"\{author}\" providerId=\"\"/>"
        let (document, edit) = authors.document.edit_source([
          insertion(authors.root("authorLst", uri=modern_comment_uri), markup),
        ])
        parts[authors.part] = document
        edits.push((authors.part, edit))
      }
      let kind = if parent is Some(_) { "reply" } else { "cm" }
      let anchor = if parent is None {
        comment_anchor_markup(self.comment_slide_id(slide))
      } else {
        ""
      }
      let markup = "<mc:\{kind} xmlns:mc=\"\{modern_comment_uri}\" id=\"\{ids[0]}\" authorId=\"\{author}\" created=\"\{date}\">\{anchor}\{modern_comment_text(None, None, text)}</mc:\{kind}>"
      if parent is Some(parent) {
        if tree.one(parent.node.id, "replyLst", uri=modern_comment_uri)
          is Some(list) {
          changes.push(insertion(list, markup))
        } else {
          // Native replies precede the text body in the comment sequence.
          changes.push({
            node: parent.node.id,
            offset: parent.text.start - parent.node.start,
            length: 0,
            xml: "<mc:replyLst xmlns:mc=\"\{modern_comment_uri}\">\{markup}</mc:replyLst>",
          })
        }
      } else {
        changes.push(
          insertion(tree.root("cmLst", uri=modern_comment_uri), markup),
        )
      }
    }
    UpdateComment(id, text) => {
      check_comment_id(id)
      let text = comment_text(text)
      guard entries.iter().find_first(e => e.id == id) is Some(entry) else {
        @failure.reject("invalid-operation", "Comment is missing")
      }
      if entry.value == text {
        return self.query()
      }
      guard entries
        .iter()
        .fold(init=text.length() - entry.value.length(), (sum, e) => {
          sum + e.value.length()
        }) <=
        1048576 else {
        @failure.reject("limit-exceeded", "Slide comments exceed text budget")
      }
      changes.push({
        node: entry.node.id,
        offset: entry.text.start - entry.node.start,
        length: entry.text.end - entry.text.start,
        xml: modern_comment_text(Some(tree), Some(entry.text), text),
      })
    }
    CommentStatus(id, status) => {
      check_comment_id(id)
      guard ["active", "resolved", "closed"].contains(status) else {
        @failure.reject("invalid-operation", "Invalid modern comment status")
      }
      guard entries.iter().find_first(e => e.id == id) is Some(entry) else {
        @failure.reject("invalid-operation", "Comment is missing")
      }
      if entry.status == Some(status) {
        return self.query()
      }
      changes.push(
        attribute_change({ tree, node: entry.node, }, "status", status),
      )
    }
    RemoveComment(id) => {
      check_comment_id(id)
      guard entries.iter().find_first(e => e.id == id) is Some(entry) else {
        @failure.reject("invalid-operation", "Comment is missing")
      }
      changes.push(remove_slide_node(tree, entry.node))
    }
    _ => @failure.reject("invalid-operation", "Expected a comment edit")
  }
  let (document, edit) = tree.document.edit_source(changes)
  ignore(read_modern_comments(Tree::new(tree.part, document)))
  parts[tree.part] = document
  edits.push((tree.part, edit))
  let slides = self.slides.mapi((index, page) => {
    if page.tree.part == slide &&
      edits.any(edit => edit.0 == slide) &&
      parts.get(slide) is Some(document) {
      read_slide(
        self.opc,
        self.main,
        self.cache,
        Tree::new(page.tree.part, document),
        index~,
        parts~,
        date_time=self.date_time,
      )
    } else {
      page
    }
  })
  // The live slide owns its source; do not retain a stale duplicate after body edits.
  ignore(parts.remove(slide))
  self.commit_slides(
    self.main,
    slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
