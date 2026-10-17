///|
fn comment_text(text : String) -> String raise @failure.Failure {
  guard text.length() <= 32767 &&
    !text.trim().is_empty() &&
    @xml.valid_text(text) else {
    @failure.reject(
      "invalid-text", "Comments require nonempty text within 32767 UTF-16 units",
    )
  }
  text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
fn check_comment_id(id : String) -> Unit raise @failure.Failure {
  guard id.length() <= 21 &&
    id.split(":").to_array() is [author, index] &&
    comment_uint(author.to_owned()) == author.to_owned() &&
    comment_uint(index.to_owned()) == index.to_owned() else {
    @failure.reject("invalid-operation", "Invalid comment identity")
  }
}

///|
fn Session::edit_comments(
  self : Session,
  index : Int,
  change : SlideEdit,
) -> Json raise @failure.Failure {
  let slide = self.slides[index].tree.part
  let links = self.relationships()
  let tree = self.comment_part(slide, "comments", links)
  let author_tree = self.comment_part(self.main.part, "commentAuthors", links)
  let authors = author_tree.map(read_comment_authors).unwrap_or([])
  let entries = tree.map(read_comment_entries).unwrap_or([])
  guard entries.all(e => authors.any(a => a.id == e.author)) else {
    @failure.reject("protected-content", "Comment author is missing")
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  match change {
    AddComment(text, name, initials, date, parent) => {
      let text = comment_text(text)
      guard entries.length() < 4096 &&
        entries
        .iter()
        .fold(init=text.length(), (sum, e) => sum + e.text.text.length()) <=
        1048576 else {
        @failure.reject("limit-exceeded", "Slide comments exceed budget")
      }
      let parent = parent.map(id => {
        check_comment_id(id)
        let entry = entries
          .iter()
          .find_first(e => e.id == id)
          .unwrap_or_else(() => {
            @failure.reject("invalid-operation", "Reply parent is missing")
          })
        guard entry.parent is None else {
          @failure.reject("invalid-operation", "Reply to the root comment")
        }
        entry
      })
      self.append_comment(
        slide, tree, author_tree, authors, text, name, initials, date, parent, parts,
        created, edits,
      )
    }
    UpdateComment(id, text) => {
      check_comment_id(id)
      let text = comment_text(text)
      let entry = entries
        .iter()
        .find_first(e => e.id == id)
        .unwrap_or_else(() => {
          @failure.reject("invalid-operation", "Comment is missing")
        })
      if entry.text.text == text {
        return self.query()
      }
      guard entries
        .iter()
        .fold(init=text.length() - entry.text.text.length(), (sum, e) => {
          sum + e.text.text.length()
        }) <=
        1048576 else {
        @failure.reject("limit-exceeded", "Slide comments exceed text budget")
      }
      let tree = tree.unwrap()
      let node = entry.text
      let markup = xml_attribute(text)
      let change = if node.empty {
        insertion(node, markup)
      } else {
        {
          node: node.id,
          offset: node.opening_end - node.start,
          length: node.closing_start - node.opening_end,
          xml: markup,
        }
      }
      let (document, edit) = tree.document.edit_source([change])
      parts[tree.part] = document
      edits.push((tree.part, edit))
    }
    RemoveComment(id) => {
      check_comment_id(id)
      guard entries.any(e => e.id == id) else {
        @failure.reject("invalid-operation", "Comment is missing")
      }
      let tree = tree.unwrap()
      let changes = entries
        .filter(e => e.id == id || e.parent == Some(id))
        .map(e => remove_slide_node(tree, e.node))
      let (document, edit) = tree.document.edit_source(changes)
      parts[tree.part] = document
      edits.push((tree.part, edit))
    }
    _ => @failure.reject("invalid-operation", "Expected a comment edit")
  }
  self.commit_slides(
    self.main,
    self.slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
