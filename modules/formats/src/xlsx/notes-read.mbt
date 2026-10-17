///|
priv struct CellNote {
  node : @xml.Node
  address : Address
  author : String
  text : String
  body : @xml.Node
}

///|
priv struct SheetNotes {
  part : String
  tree : Tree
  authors : Array[String]
  entries : Array[CellNote]
  vml : (String, Tree, Map[String, @xml.Node])?
}

///|
fn note_markup(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    node.text.trim().is_empty() &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => n.uri == spreadsheet_uri && children.contains(n.name)) else {
    @failure.reject(
      "protected-content", "Unknown cell note source is protected",
    )
  }
}

///|
fn read_cell_notes(
  tree : Tree,
) -> (Array[String], Array[CellNote]) raise @failure.Failure {
  let root = tree.root("comments")
  note_markup(tree, root, [], ["authors", "commentList"])
  let authors = tree
    .one(root.id, "authors")
    .unwrap_or_else(() => {
      @failure.reject("protected-content", "Cell note authors are missing")
    })
  note_markup(tree, authors, [], ["author"])
  let author_nodes = tree.all(authors.id, "author")
  guard author_nodes.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Cell note authors exceed budget")
  }
  let names = author_nodes.map(n => {
    guard n.attributes.is_empty() &&
      tree.children.get(n.id).unwrap_or([]).is_empty() &&
      n.text.length() <= 255 else {
      @failure.reject(
        "protected-content", "Unknown or excessive cell note author",
      )
    }
    let name = decode_text(n.text)
    guard @xml.valid_text(name) else {
      @failure.reject("protected-content", "Unsupported cell note author text")
    }
    name
  })
  let list = tree
    .one(root.id, "commentList")
    .unwrap_or_else(() => {
      @failure.reject("protected-content", "Cell note list is missing")
    })
  note_markup(tree, list, [], ["comment"])
  let nodes = tree.all(list.id, "comment")
  guard names.length() <= 4096 && nodes.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Cell notes exceed entry budget")
  }
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  let entries = nodes.map(node => {
    note_markup(tree, node, ["ref", "authorId", "guid", "shapeId"], ["text"])
    let address = Address::parse(node.attribute("ref").unwrap_or(""))
    guard !seen.contains(address.name()) else {
      @failure.reject("protected-content", "Duplicate cell note address")
    }
    seen[address.name()] = true
    let author = natural(node.attribute("authorId").unwrap_or(""), 4095)
    guard names.get(author) is Some(author) else {
      @failure.reject("protected-content", "Cell note author is missing")
    }
    let body = tree
      .one(node.id, "text")
      .unwrap_or_else(() => {
        @failure.reject("protected-content", "Cell note text is missing")
      })
    note_markup(tree, body, [], ["t", "r"])
    let raw = tree.document.source()[body.start:body.end]
    guard !raw.contains("<!--") && !raw.contains("<?") else {
      @failure.reject("protected-content", "Opaque cell note text is protected")
    }
    let children = tree.children.get(body.id).unwrap_or([])
    guard children.all(n => n.name == "r") ||
      (children.length() <= 1 && children.all(n => n.name == "t")) else {
      @failure.reject("protected-content", "Mixed cell note text is protected")
    }
    let text_nodes : Array[@xml.Node] = []
    for child in children {
      if child.name == "r" {
        note_markup(tree, child, [], ["rPr", "t"])
        if tree.one(child.id, "t") is Some(text) {
          text_nodes.push(text)
        }
        if tree.one(child.id, "rPr") is Some(properties) {
          note_markup(tree, properties, [], [
            "rFont", "charset", "family", "b", "i", "strike", "outline", "shadow",
            "condense", "extend", "color", "sz", "u", "vertAlign", "scheme",
          ])
          for property in tree.children.get(properties.id).unwrap_or([]) {
            note_markup(
              tree,
              property,
              ["val", "rgb", "indexed", "auto", "theme", "tint"],
              [],
            )
          }
        }
      } else {
        text_nodes.push(child)
      }
    }
    for child in text_nodes {
      if child.name == "t" {
        let raw = tree.document.source()[child.start:child.end]
        guard child.attributes.all(a => {
            a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
          }) &&
          tree.children.get(child.id).unwrap_or([]).is_empty() &&
          !raw.contains("<!--") &&
          !raw.contains("<?") else {
          @failure.reject(
            "protected-content", "Opaque cell note text is protected",
          )
        }
      }
    }
    let text = tree.text(body.id).0
    guard @xml.valid_text(text) else {
      @failure.reject("protected-content", "Unsupported escaped cell note text")
    }
    units += text.length()
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Cell notes exceed text budget")
    }
    { node, address, author, text, body, }
  })
  (names, entries)
}

///|
fn Session::read_sheet_notes(
  self : Session,
  sheet : Sheet,
) -> SheetNotes? raise @failure.Failure {
  let links = self.relationships()
  guard !links.any(l => {
    l.owner == sheet.id &&
    l.kind.to_lower().contains("comment") &&
    l.kind != relationship_uri + "comments"
  }) else {
    @failure.reject(
      "protected-content", "Threaded or unknown cell comments require editing support",
    )
  }
  let owned = links.filter(l => {
    l.owner == sheet.id && l.kind == relationship_uri + "comments"
  })
  guard owned.length() <= 1 else {
    @failure.reject(
      "protected-content", "Multiple cell note owners are protected",
    )
  }
  let vml = self.read_note_vml(sheet)
  guard owned.get(0) is Some(link) else {
    guard vml is None else {
      @failure.reject(
        "protected-content", "VML notes have no comment text part",
      )
    }
    return None
  }
  guard !link.external &&
    links.filter(l => !l.external && l.target == link.target).length() == 1 else {
    @failure.reject(
      "protected-content", "Shared or external cell notes are protected",
    )
  }
  let tree = Tree::new(self.part_xml(link.target))
  let (authors, entries) = read_cell_notes(tree)
  if vml is Some((_, _, shapes)) {
    guard shapes.length() == entries.length() &&
      entries.all(e => shapes.contains(e.address.name())) else {
      @failure.reject(
        "protected-content", "Cell notes and VML anchors do not match",
      )
    }
  }
  Some({ part: link.target, tree, authors, entries, vml, })
}

///|
fn Session::note_query(
  self : Session,
  sheet : Sheet,
  requested : Range,
) -> Json {
  try {
    let notes = self.read_sheet_notes(sheet)
    let range = sheet.merge_target(requested)
    let reason = self.dimension_reason(sheet)
    let one = (range.top == range.bottom && range.left == range.right) ||
      sheet.merges.contains(range)
    let note = notes.bind(n => {
      n.entries
      .iter()
      .find_first(e => {
        e.address.row == range.top && e.address.column == range.left
      })
    })
    let address : Address = { row: range.top, column: range.left, }
    {
      "address": address.name(),
      "text": note.map(n => n.text).unwrap_or(""),
      "author": note.map(n => n.author).unwrap_or(""),
      "exists": note is Some(_),
      "reason": if !reason.is_empty() {
        reason
      } else if !one {
        "Select one cell or merged cell for a note"
      } else {
        ""
      },
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "address": "",
        "text": "",
        "author": "",
        "exists": false,
        "reason": message,
      }
  }
}
