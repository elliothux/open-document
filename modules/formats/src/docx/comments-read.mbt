///|
priv struct DocComment {
  key : String
  node : Int
  author : String
  initials : String
  date : String
  text : String
  para : String
  parent : String?
  done : Bool
}

///|
priv struct CommentsSource {
  part : String
  document : @xml.Document
  tree : WordTree
  entries : Array[DocComment]
  extended : (String, @xml.Document)?
}

///|
fn comment_markup(
  tree : WordTree,
  id : Int,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  let node = tree.nodes[id]
  guard node.uri == word_uri &&
    node.attributes.all(a => a.uri == word_uri && attributes.contains(a.name)) &&
    tree.children[id].all(child => {
      tree.nodes[child].uri == word_uri &&
      children.contains(tree.nodes[child].name)
    }) &&
    node.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown comment body markup")
  }
}

///|
fn read_doc_comments(
  document : @xml.Document,
) -> Array[DocComment] raise @failure.Failure {
  let tree = WordTree::new(document)
  guard tree.nodes[0].name == "comments" else {
    @failure.reject("protected-content", "Invalid comments part")
  }
  comment_markup(tree, 0, [], ["comment"])
  let entries : Array[DocComment] = []
  let used : Map[String, Bool] = Map([])
  let para_ids : Map[String, Bool] = Map([])
  let mut units = 0
  for id in tree.children[0] {
    let node = tree.nodes[id]
    guard node.empty ||
      (
        !document.source()[node.opening_end:node.closing_start].contains("<!--") &&
        !document.source()[node.opening_end:node.closing_start].contains("<?")
      ) else {
      @failure.reject("protected-content", "Opaque comment body is protected")
    }
    comment_markup(tree, id, ["id", "author", "initials", "date"], ["p"])
    let key = comment_key(node.attribute("id", uri=word_uri).unwrap_or(""))
    guard !used.contains(key) && entries.length() < 4096 else {
      @failure.reject("protected-content", "Duplicate or excessive comments")
    }
    used[key] = true
    let author = node.attribute("author", uri=word_uri).unwrap_or("")
    let initials = node.attribute("initials", uri=word_uri).unwrap_or("")
    let date = node.attribute("date", uri=word_uri).unwrap_or("")
    guard author.length() <= 255 &&
      initials.length() <= 32 &&
      date.length() <= 128 else {
      @failure.reject("protected-content", "Comment metadata exceeds budget")
    }
    let paragraphs : Array[String] = []
    let mut para = ""
    for p in tree.children[id] {
      let paragraph = tree.nodes[p]
      para = paragraph
        .attribute("paraId", uri=comment_para_uri)
        .map(comment_para_id)
        .unwrap_or("")
      if !para.is_empty() {
        guard !para_ids.contains(para) else {
          @failure.reject(
            "protected-content", "Duplicate comment paragraph identity",
          )
        }
        para_ids[para] = true
      }
      guard paragraph.attributes.all(a => {
          (
            a.uri == word_uri &&
            ["rsidR", "rsidRDefault", "rsidP"].contains(a.name)
          ) ||
          (
            a.uri == "http://schemas.microsoft.com/office/word/2010/wordml" &&
            ["paraId", "textId"].contains(a.name)
          )
        }) &&
        paragraph.text.trim().is_empty() &&
        tree.children[p].all(child => {
          tree.nodes[child].uri == word_uri &&
          ["pPr", "r"].contains(tree.nodes[child].name)
        }) else {
        @failure.reject("protected-content", "Unknown comment paragraph")
      }
      let text = StringBuilder()
      for r in tree.children[p] {
        if tree.nodes[r].name == "pPr" {
          tree.check_structure_properties(r)
          continue
        }
        comment_markup(tree, r, ["rsidR", "rsidRPr"], [
          "rPr", "t", "br", "cr", "tab",
        ])
        for child in tree.children[r] {
          let value = tree.nodes[child]
          if value.name == "rPr" {
            tree.check_structure_properties(child)
            continue
          }
          guard tree.children[child].is_empty() &&
            value.attributes.all(a => {
              (
                value.name == "t" &&
                a.uri == "http://www.w3.org/XML/1998/namespace" &&
                a.name == "space"
              ) ||
              (
                value.name == "br" &&
                a.uri == word_uri &&
                a.name == "type" &&
                a.value == "textWrapping"
              )
            }) else {
            @failure.reject("protected-content", "Unknown comment text")
          }
          if value.name == "t" {
            text.write_string(value.text)
          } else {
            guard value.text.trim().is_empty() else {
              @failure.reject(
                "protected-content", "Comment control contains text",
              )
            }
            text.write_string(if value.name == "tab" { "\t" } else { "\n" })
          }
        }
      }
      paragraphs.push(text.to_string())
    }
    let text = paragraphs.join("\n")
    units += text.length()
    guard text.length() <= 32767 && units <= 1048576 else {
      @failure.reject("limit-exceeded", "Comments exceed text budget")
    }
    entries.push({
      key,
      node: id,
      author,
      initials,
      date,
      text,
      para,
      parent: None,
      done: false,
    })
  }
  entries
}

///|
fn Session::comment_source(
  self : Session,
) -> CommentsSource? raise @failure.Failure {
  let links = self.relationships()
  let kind = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"
  let candidates = links.filter(l => l.kind == kind && l.owner == self.main)
  let extensions = links.filter(l => l.kind == comment_extended_kind)
  guard candidates.length() <= 1 &&
    extensions.length() <= 1 &&
    extensions.all(l => l.owner == self.main) &&
    !links.any(l => {
      l.kind.to_lower().contains("comment") &&
      l.kind != kind &&
      l.kind != comment_extended_kind
    }) else {
    @failure.reject("protected-content", "Unsupported comment extension")
  }
  guard candidates.get(0) is Some(link) else {
    guard extensions.is_empty() else {
      @failure.reject(
        "protected-content", "Comment threads have no comments part",
      )
    }
    return None
  }
  guard !link.external &&
    links.filter(l => !l.external && l.target == link.target).length() == 1 &&
    !links.any(l => l.owner == link.target) else {
    @failure.reject(
      "protected-content", "Shared external or resource-backed comments are protected",
    )
  }
  let document = self.part_xml(link.target)
  let entries = read_doc_comments(document)
  let extended = if extensions.get(0) is Some(extension) {
    guard !extension.external &&
      links.filter(l => !l.external && l.target == extension.target).length() ==
      1 &&
      !links.any(l => l.owner == extension.target) else {
      @failure.reject(
        "protected-content", "Shared external or resource-backed comment threads are protected",
      )
    }
    Some((extension.target, self.part_xml(extension.target)))
  } else {
    None
  }
  Some({
    part: link.target,
    document,
    tree: WordTree::new(document),
    entries: extended
    .map(e => read_comment_threads(entries, e.1))
    .unwrap_or(entries),
    extended,
  })
}

///|
/// Lists local classic comments and their logical body anchors without changing history.
pub fn Session::comments(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  try {
    let source = self.comment_source()
    let anchors = WordTree::new(self.document()).comment_anchors()
    let entries = source.map(s => s.entries).unwrap_or([])
    guard anchors.length() <= 4096 &&
      anchors.all(a => entries.any(e => e.key == a.key)) else {
      @failure.reject("protected-content", "Comment body or anchor is missing")
    }
    {
      "revision": revision,
      "reason": "",
      "items": entries.map(fn(e) -> Json {
        let root = entries
          .iter()
          .find_first(r => r.key == e.parent.unwrap_or(e.key))
          .unwrap()
        let anchor = anchors.iter().find_first(a => a.key == root.key)
        {
          "id": e.key,
          "author": e.author,
          "initials": e.initials,
          "date": e.date,
          "text": e.text,
          "parent": e.parent.map(p => Json(p)).unwrap_or(Json::null()),
          "done": root.done,
          "selection": anchor
          .bind(a => a.selection)
          .map(s => s.to_json())
          .unwrap_or(Json::null()),
          "reason": anchor
          .map(a => a.reason)
          .unwrap_or("Comment has no editable body anchor"),
        }
      }),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "revision": revision, "reason": message, "items": [] }
  }
}
