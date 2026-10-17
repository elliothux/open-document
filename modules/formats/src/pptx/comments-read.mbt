///|
let comment_thread_uri = "http://schemas.microsoft.com/office/powerpoint/2012/main"

///|
priv struct CommentEntry {
  node : @xml.Node
  id : String
  author : String
  text : @xml.Node
  date : String
  parent : String?
  parent_node : @xml.Node?
}

///|
priv struct CommentAuthor {
  node : @xml.Node
  id : String
  name : String
  initials : String
  last_index : Int64
}

///|
fn comment_uint(value : String) -> String raise @failure.Failure {
  guard !value.is_empty() && value.iter().all(c => c >= '0' && c <= '9') else {
    @failure.reject("protected-content", "Invalid comment identity")
  }
  number(value, 0, 4294967295).to_int64().to_string()
}

///|
fn comment_markup(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[(String, String)],
) -> Unit raise @failure.Failure {
  guard node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    node.text.trim().is_empty() &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => children.contains((n.uri, n.name))) else {
    @failure.reject("protected-content", "Unknown comment source is protected")
  }
}

///|
fn read_comment_entries(
  tree : Tree,
) -> Array[CommentEntry] raise @failure.Failure {
  let root = tree.root("cmLst")
  comment_markup(tree, root, [], [(presentation_uri, "cm")])
  let nodes = tree.all(root.id, "cm", uri=presentation_uri)
  guard nodes.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Slide comments exceed entry budget")
  }
  let entries : Array[CommentEntry] = []
  let ids : Map[String, String?] = Map([])
  let mut units = 0
  for node in nodes {
    comment_markup(tree, node, ["authorId", "dt", "idx"], [
      (presentation_uri, "pos"),
      (presentation_uri, "text"),
      (presentation_uri, "extLst"),
    ])
    let author = comment_uint(node.attribute("authorId").unwrap_or(""))
    let id = author + ":" + comment_uint(node.attribute("idx").unwrap_or(""))
    guard !ids.contains(id) else {
      @failure.reject("protected-content", "Duplicate comment identity")
    }
    let pos = tree.required(node.id, "pos", uri=presentation_uri)
    comment_markup(tree, pos, ["x", "y"], [])
    ignore(number(pos.attribute("x").unwrap_or(""), -2147483648, 2147483647))
    ignore(number(pos.attribute("y").unwrap_or(""), -2147483648, 2147483647))
    let text = tree.required(node.id, "text", uri=presentation_uri)
    let raw = tree.document.source()[text.start:text.end]
    guard tree.children.get(text.id).unwrap_or([]).is_empty() &&
      text.attributes.all(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
      }) &&
      !raw.contains("<!--") &&
      !raw.contains("<?") &&
      text.text.length() <= 32767 else {
      @failure.reject("protected-content", "Opaque comment text is protected")
    }
    units += text.text.length()
    let date = node.attribute("dt").unwrap_or("")
    guard units <= 1048576 && date.length() <= 64 else {
      @failure.reject("limit-exceeded", "Slide comments exceed text budget")
    }
    let mut parent = None
    let mut parent_node = None
    if tree.one(node.id, "extLst", uri=presentation_uri) is Some(list) {
      comment_markup(tree, list, [], [(presentation_uri, "ext")])
      let seen : Map[String, Bool] = Map([])
      for ext in tree.all(list.id, "ext", uri=presentation_uri) {
        comment_markup(tree, ext, ["uri"], [
          (comment_thread_uri, "threadingInfo"),
          (comment_thread_uri, "presenceInfo"),
        ])
        let uri = ext.attribute("uri").unwrap_or("").to_upper()
        guard !seen.contains(uri) &&
          tree.children.get(ext.id).unwrap_or([]).length() == 1 else {
          @failure.reject(
            "protected-content", "Ambiguous comment extensions are protected",
          )
        }
        seen[uri] = true
        match uri {
          "{C676402C-5697-4E1C-873F-D02D1690AC5C}" => {
            let info = tree.required(
              ext.id,
              "threadingInfo",
              uri=comment_thread_uri,
            )
            comment_markup(tree, info, ["timeZoneBias"], [
              (comment_thread_uri, "parentCm"),
            ])
            if info.attribute("timeZoneBias") is Some(value) {
              ignore(number(value, -1440, 1440))
            }
            if tree.one(info.id, "parentCm", uri=comment_thread_uri)
              is Some(reference) {
              comment_markup(tree, reference, ["authorId", "idx"], [])
              parent = Some(
                comment_uint(reference.attribute("authorId").unwrap_or("")) +
                ":" +
                comment_uint(reference.attribute("idx").unwrap_or("")),
              )
              parent_node = Some(reference)
            }
          }
          "{19B8F6BF-5375-455C-9EA6-DF929625EA0E}" => {
            let info = tree.required(
              ext.id,
              "presenceInfo",
              uri=comment_thread_uri,
            )
            comment_markup(tree, info, ["userId", "providerId"], [])
          }
          _ =>
            @failure.reject(
              "protected-content", "Unknown comment extension is protected",
            )
        }
      }
    }
    ids[id] = parent
    entries.push({ node, id, author, text, date, parent, parent_node, })
  }
  for entry in entries {
    if entry.parent is Some(parent) {
      guard ids.get(parent) is Some(None) else {
        @failure.reject(
          "protected-content", "Dangling or nested comment replies are protected",
        )
      }
    }
  }
  entries
}

///|
fn read_comment_authors(
  tree : Tree,
) -> Array[CommentAuthor] raise @failure.Failure {
  let root = tree.root("cmAuthorLst")
  comment_markup(tree, root, [], [(presentation_uri, "cmAuthor")])
  let nodes = tree.all(root.id, "cmAuthor", uri=presentation_uri)
  guard nodes.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Comment authors exceed budget")
  }
  let seen : Map[String, Bool] = Map([])
  nodes.map(node => {
    comment_markup(
      tree,
      node,
      ["id", "name", "initials", "lastIdx", "clrIdx"],
      [],
    )
    let id = comment_uint(node.attribute("id").unwrap_or(""))
    guard !seen.contains(id) else {
      @failure.reject("protected-content", "Duplicate comment author identity")
    }
    seen[id] = true
    let name = node.attribute("name").unwrap_or("")
    let initials = node.attribute("initials").unwrap_or("")
    guard name.length() <= 255 && initials.length() <= 32 else {
      @failure.reject("limit-exceeded", "Comment author text exceeds budget")
    }
    if node.attribute("clrIdx") is Some(value) {
      ignore(comment_uint(value))
    }
    {
      node,
      id,
      name,
      initials,
      last_index: number(
        comment_uint(node.attribute("lastIdx").unwrap_or("0")),
        0,
        4294967295,
      ).to_int64(),
    }
  })
}

///|
fn Session::comment_part(
  self : Session,
  owner : String,
  kind : String,
  links : ReadOnlyArray[@opc.Relationship],
) -> Tree? raise @failure.Failure {
  guard !links.any(l => {
    l.owner == owner &&
    l.kind.to_lower().contains("comment") &&
    l.kind != relationship_uri + "/comments" &&
    l.kind != relationship_uri + "/commentAuthors"
  }) else {
    @failure.reject(
      "protected-content", "Modern or unknown comments require editing support",
    )
  }
  let owned = links.filter(l => {
    l.owner == owner && l.kind == relationship_uri + "/" + kind
  })
  guard owned.length() <= 1 else {
    @failure.reject(
      "protected-content", "Multiple comment owners are protected",
    )
  }
  guard owned.get(0) is Some(link) else { return None }
  guard !link.external &&
    links.filter(l => !l.external && l.target == link.target).length() == 1 else {
    @failure.reject(
      "protected-content", "Shared or external comment parts are protected",
    )
  }
  Some(Tree::new(link.target, self.part_document(link.target)))
}

///|
fn Session::comments_query(
  self : Session,
  slide : String,
  links : ReadOnlyArray[@opc.Relationship],
) -> Json {
  try {
    let tree = self.comment_part(slide, "comments", links)
    let authors_tree = self.comment_part(
      self.main.part,
      "commentAuthors",
      links,
    )
    let authors = authors_tree.map(read_comment_authors).unwrap_or([])
    let names : Map[String, CommentAuthor] = Map([])
    for author in authors {
      names[author.id] = author
    }
    let entries = tree.map(read_comment_entries).unwrap_or([])
    let items = entries.map(fn(entry) -> Json raise @failure.Failure {
      guard names.get(entry.author) is Some(author) else {
        @failure.reject("protected-content", "Comment author is missing")
      }
      {
        "id": entry.id,
        "author": author.name,
        "initials": author.initials,
        "date": entry.date,
        "text": entry.text.text,
        "parent": entry.parent.map(value => Json(value)).unwrap_or(Json::null()),
      }
    })
    { "items": items, "reason": self.slide_visibility_reason() }
  } catch {
    @failure.Failure(message~, ..) => { "items": [], "reason": message }
  }
}
