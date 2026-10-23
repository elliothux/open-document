///|
let modern_comment_uri = "http://schemas.microsoft.com/office/powerpoint/2018/8/main"

///|
let modern_comment_relationship = "http://schemas.microsoft.com/office/2018/10/relationships"

///|
fn modern_comment_id(value : String) -> Bool {
  guard value.length() == 38 && value[0] == 123 && value[37] == 125 else {
    return false
  }
  for i in 1..<37 {
    let c = value[i]
    if [9, 14, 19, 24].contains(i) {
      if c != 45 {
        return false
      }
    } else if !((c >= 48 && c <= 57) ||
      (c >= 65 && c <= 70) ||
      (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
fn modern_identity(
  node : @xml.Node,
  key : String,
) -> String raise @failure.Failure {
  let id = node.attribute(key).unwrap_or("")
  guard modern_comment_id(id) else {
    @failure.reject("protected-content", "Invalid modern comment identity")
  }
  id.to_upper()
}

///|
fn modern_comment_body(
  tree : Tree,
  body : @xml.Node,
) -> String raise @failure.Failure {
  let raw = tree.document.source()[body.start:body.end]
  guard !raw.contains("<!--") && !raw.contains("<?") else {
    @failure.reject("protected-content", "Annotated comment text is protected")
  }
  comment_markup(tree, body, [], [
    (drawing_uri, "bodyPr"),
    (drawing_uri, "lstStyle"),
    (drawing_uri, "p"),
  ])
  for name in ["bodyPr", "lstStyle"] {
    comment_markup(tree, tree.required(body.id, name), [], [])
  }
  let paragraphs = tree.all(body.id, "p")
  guard !paragraphs.is_empty() && paragraphs.length() <= 256 else {
    @failure.reject("limit-exceeded", "Comment paragraphs exceed budget")
  }
  let lines = paragraphs.map(p => {
    comment_markup(tree, p, [], [
      (drawing_uri, "r"),
      (drawing_uri, "endParaRPr"),
    ])
    if tree.one(p.id, "endParaRPr") is Some(style) {
      comment_markup(tree, style, ["lang", "sz", "b", "i", "dirty"], [])
    }
    let runs = tree.all(p.id, "r")
    guard runs.length() <= 1 else {
      @failure.reject(
        "protected-content", "Mixed comment text formatting requires editing support",
      )
    }
    guard runs.get(0) is Some(run) else { return "" }
    comment_markup(tree, run, [], [(drawing_uri, "rPr"), (drawing_uri, "t")])
    if tree.one(run.id, "rPr") is Some(style) {
      comment_markup(tree, style, ["lang", "sz", "b", "i", "dirty"], [])
    }
    let text = tree.required(run.id, "t")
    guard tree.children.get(text.id).unwrap_or([]).is_empty() &&
      text.attributes.all(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
      }) else {
      @failure.reject("protected-content", "Extended comment text is protected")
    }
    text.text
  })
  let value = lines.join("\n")
  guard value.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Comment text exceeds budget")
  }
  value
}

///|
fn read_modern_comments(
  tree : Tree,
) -> Array[CommentEntry] raise @failure.Failure {
  let root = tree.root("cmLst", uri=modern_comment_uri)
  comment_markup(tree, root, [], [(modern_comment_uri, "cm")])
  let entries : Array[CommentEntry] = []
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for node in tree.all(root.id, "cm", uri=modern_comment_uri) {
    let replies = tree.one(node.id, "replyLst", uri=modern_comment_uri)
    if replies is Some(list) {
      comment_markup(tree, list, [], [(modern_comment_uri, "reply")])
    }
    let nodes = [
      node,
      ..replies
      .map(list => tree.all(list.id, "reply", uri=modern_comment_uri))
      .unwrap_or([]),
    ]
    for item in nodes {
      let is_root = item.id == node.id
      comment_markup(
        tree,
        item,
        ["id", "authorId", "created", "status"],
        if is_root {
          [
            (modern_comment_uri, "txBody"),
            (modern_comment_uri, "pos"),
            (modern_comment_uri, "replyLst"),
            (comment_anchor_uri, "sldMkLst"),
          ]
        } else {
          [(modern_comment_uri, "txBody")]
        },
      )
      let status = item.attribute("status").unwrap_or("active")
      guard ["active", "resolved", "closed"].contains(status) else {
        @failure.reject(
          "protected-content", "Unknown modern comment status is protected",
        )
      }
      if is_root {
        ignore(modern_comment_anchor(tree, item))
      }
      let id = modern_identity(item, "id")
      guard !seen.contains(id) else {
        @failure.reject(
          "protected-content", "Duplicate modern comment identity",
        )
      }
      seen[id] = true
      let author = modern_identity(item, "authorId")
      let date = item.attribute("created").unwrap_or("")
      guard date.length() <= 64 else {
        @failure.reject("limit-exceeded", "Comment date exceeds budget")
      }
      if tree.one(item.id, "pos", uri=modern_comment_uri) is Some(pos) {
        comment_markup(tree, pos, ["x", "y"], [])
        ignore(
          number(pos.attribute("x").unwrap_or(""), -2147483648, 2147483647),
        )
        ignore(
          number(pos.attribute("y").unwrap_or(""), -2147483648, 2147483647),
        )
      }
      let text = tree.required(item.id, "txBody", uri=modern_comment_uri)
      let value = modern_comment_body(tree, text)
      units += value.length()
      guard entries.length() < 4096 && units <= 1048576 else {
        @failure.reject("limit-exceeded", "Modern comments exceed budget")
      }
      entries.push({
        node: item,
        id,
        author,
        text,
        value,
        status: Some(status),
        date,
        parent: if is_root {
          None
        } else {
          Some(modern_identity(node, "id"))
        },
        parent_node: None,
      })
    }
  }
  entries
}

///|
fn read_modern_authors(
  tree : Tree,
) -> Array[CommentAuthor] raise @failure.Failure {
  let root = tree.root("authorLst", uri=modern_comment_uri)
  comment_markup(tree, root, [], [(modern_comment_uri, "author")])
  let nodes = tree.all(root.id, "author", uri=modern_comment_uri)
  guard nodes.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Comment authors exceed budget")
  }
  let seen : Map[String, Bool] = Map([])
  nodes.map(node => {
    comment_markup(
      tree,
      node,
      ["id", "name", "initials", "userId", "providerId"],
      [],
    )
    let id = modern_identity(node, "id")
    guard !seen.contains(id) else {
      @failure.reject("protected-content", "Duplicate modern author identity")
    }
    seen[id] = true
    let name = node.attribute("name").unwrap_or("")
    let initials = node.attribute("initials").unwrap_or("")
    guard name.length() <= 255 &&
      initials.length() <= 32 &&
      node.attributes.all(a => a.value.length() <= 4096) else {
      @failure.reject("limit-exceeded", "Comment author text exceeds budget")
    }
    { node, id, name, initials, last_index: 0L, }
  })
}
