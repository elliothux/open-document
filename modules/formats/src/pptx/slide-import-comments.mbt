///|
fn same_imported_author(
  left : CommentAuthor,
  right : CommentAuthor,
  modern : Bool,
) -> Bool {
  let keys = if modern {
    ["name", "initials", "userId", "providerId"]
  } else {
    ["name", "initials", "clrIdx"]
  }
  keys.all(key => left.node.attribute(key) == right.node.attribute(key))
}

///|
fn Session::import_comments(
  self : Session,
  source : Session,
  slides : Array[String],
  remap : Map[String, String],
  slide_ids : Map[String, String],
  parts : Map[String, @xml.Document],
  media : Map[String, Bytes],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let links = source.relationships()
  let retained = self.relationships()
  for modern in [false, true] {
    let imported : Array[(String, Tree, Array[CommentEntry])] = []
    for slide in slides {
      if source.comment_part(slide, "comments", links) is Some(tree) &&
        (tree.document.nodes()[0].uri == modern_comment_uri) == modern {
        imported.push((slide, tree, read_comment_entries(tree)))
      }
    }
    let count = imported.fold(init=0, (sum, page) => sum + page.2.length())
    if count == 0 {
      continue
    }
    let authors_tree = source
      .comment_part(source.main.part, "commentAuthors", links, modern~)
      .unwrap()
    let authors = read_comment_authors(authors_tree)
    let used = Set(imported.map(page => page.2.map(e => e.author)).flatten())
    let reserved : Map[String, Bool] = Map([])
    for author in authors {
      reserved[author.id] = true
    }
    for (_, _, entries) in imported {
      for entry in entries {
        reserved[entry.id] = true
      }
    }
    let ids = if modern {
      self.modern_comment_ids(count + used.length(), reserved~)
    } else {
      []
    }
    let mut cursor = 0
    let target = self.comment_part(
      self.main.part,
      "commentAuthors",
      retained,
      modern~,
    )
    let existing = target.map(read_comment_authors).unwrap_or([])
    let target = target.unwrap_or_else(() => {
      let staged = { ..self, parts: parts.copy(), media, }
      staged.create_comment_part(
        self.main.part,
        "commentAuthors",
        if modern {
          "authorLst"
        } else {
          "cmAuthorLst"
        },
        parts,
        created,
        edits,
        modern~,
      )
    })
    let mut sequence = existing.fold(init=0L, (max, a) => {
      if modern {
        max
      } else {
        max.max(number(a.id, 0, 4294967295).to_int64() + 1L)
      }
    })
    let indices = Map::from_array(existing.map(a => (a.id, a.last_index)))
    let mut work = count
    if !modern {
      // Imported lastIdx may lag behind retained comments, so reserve the actual indices.
      for link in retained {
        if !link.external && link.kind == relationship_uri + "/comments" {
          for node in self.part_document(link.target).nodes() {
            if node.uri != presentation_uri || node.name != "cm" {
              continue
            }
            work += 1
            guard work <= 16384 else {
              @failure.reject(
                "limit-exceeded", "Presentation comments exceed allocation budget",
              )
            }
            let id = comment_uint(node.attribute("authorId").unwrap_or(""))
            sequence = sequence.max(number(id, 0, 4294967295).to_int64() + 1L)
            if indices.get(id) is Some(last) {
              indices[id] = last.max(
                number(
                  comment_uint(node.attribute("idx").unwrap_or("")),
                  0,
                  4294967295,
                ).to_int64(),
              )
            }
          }
        }
      }
    }
    let authors_map : Map[String, String] = Map([])
    let appended : Array[(CommentAuthor, String)] = []
    for author in authors {
      if !used.contains(author.id) {
        continue
      }
      let matching = existing.filter(a => {
        same_imported_author(a, author, modern)
      })
      guard matching.length() <= 1 else {
        @failure.reject(
          "protected-content", "Ambiguous imported author identity",
        )
      }
      let id = if matching.get(0) is Some(known) {
        known.id
      } else {
        guard existing.length() < 4096 else {
          @failure.reject("limit-exceeded", "Comment authors exceed budget")
        }
        let id = if modern {
          let id = ids[cursor]
          cursor += 1
          id
        } else {
          guard sequence <= 4294967295L else {
            @failure.reject(
              "limit-exceeded", "Comment author identities exhausted",
            )
          }
          let id = sequence.to_string()
          sequence += 1L
          id
        }
        existing.push({ ..author, id, last_index: 0L, })
        indices[id] = 0L
        appended.push((author, id))
        id
      }
      authors_map[author.id] = id
    }
    let changed : Set[String] = Set([])
    for (slide, tree, entries) in imported {
      let changes : Array[@xml.SourceChange] = []
      let copied : Map[String, (String, String)] = Map([])
      for entry in entries {
        let author = authors_map[entry.author]
        changes.push(
          attribute_change({ tree, node: entry.node, }, "authorId", author),
        )
        let id = if modern {
          let id = ids[cursor]
          cursor += 1
          id
        } else {
          guard indices[author] < 4294967295L else {
            @failure.reject("limit-exceeded", "Comment indices exhausted")
          }
          indices[author] += 1L
          changed.add(author)
          indices[author].to_string()
        }
        copied[entry.id] = (author, id)
        changes.push(
          attribute_change(
            { tree, node: entry.node, },
            if modern {
              "id"
            } else {
              "idx"
            },
            id,
          ),
        )
        if modern &&
          entry.parent is None &&
          modern_comment_anchor(tree, entry.node) is Some(anchor) {
          changes.push({
            node: entry.node.id,
            offset: anchor.start - entry.node.start,
            length: anchor.end - anchor.start,
            xml: comment_anchor_markup(slide_ids[slide]),
          })
        }
        let uri = if modern { modern_comment_uri } else { presentation_uri }
        if tree.one(entry.node.id, "pos", uri~) is Some(pos) {
          for
            (key, scale) in [
              ("x", self.width / source.width),
              ("y", self.height / source.height),
            ] {
            let value = (number(
              pos.attribute(key).unwrap_or(""),
              -2147483648,
              2147483647,
            ) *
            scale).round()
            guard value >= -2147483648 && value <= 2147483647 else {
              @failure.reject(
                "invalid-size", "Imported comment position exceeds bounds",
              )
            }
            changes.push(
              attribute_change(
                { tree, node: pos, },
                key,
                value.to_int64().to_string(),
              ),
            )
          }
        }
      }
      for entry in entries {
        if entry.parent is Some(parent) && entry.parent_node is Some(node) {
          let (author, id) = copied[parent]
          changes.push(attribute_change({ tree, node, }, "authorId", author))
          changes.push(attribute_change({ tree, node, }, "idx", id))
        }
      }
      let name = remap[tree.part]
      let document = @xml.Document::parse(
        tree.document.edit_source(changes).0.bytes(),
        name,
        self.budget.xml_depth,
        self.budget.entry_bytes,
      )
      ignore(read_comment_entries(Tree::new(name, document)))
      parts[name] = document
      created[name] = document
    }
    let changes : Array[@xml.SourceChange] = []
    for author in read_comment_authors(target) {
      if changed.contains(author.id) {
        changes.push(
          attribute_change(
            { tree: target, node: author.node, },
            "lastIdx",
            indices[author.id].to_string(),
          ),
        )
      }
    }
    let markup = StringBuilder()
    for (author, id) in appended {
      let updates = [
        attribute_change({ tree: authors_tree, node: author.node, }, "id", id),
      ]
      if !modern {
        updates.push(
          attribute_change(
            { tree: authors_tree, node: author.node, },
            "lastIdx",
            indices[id].to_string(),
          ),
        )
      }
      let document = authors_tree.document.edit_source(updates).0
      markup.write_string(
        authors_tree.standalone_markup(document, author.node.id),
      )
    }
    if !appended.is_empty() {
      changes.push(insertion(target.document.nodes()[0], markup.to_string()))
    }
    if !changes.is_empty() {
      let (document, edit) = target.document.edit_source(changes)
      ignore(read_comment_authors(Tree::new(target.part, document)))
      parts[target.part] = document
      edits.push((target.part, edit))
    }
  }
}
