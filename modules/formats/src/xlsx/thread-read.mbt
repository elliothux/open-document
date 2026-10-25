///|
let thread_uri = "http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments"

///|
let thread_relationship_uri = "http://schemas.microsoft.com/office/2017/10/relationships/"

///|
priv struct ThreadPerson {
  id : String
  name : String
}

///|
priv struct ThreadMessage {
  node : @xml.Node
  body : @xml.Node
  id : String
  parent : String?
  person : String
  address : Address
  date : String
  text : String
  done : Bool
}

///|
priv struct SheetThreads {
  part : String?
  tree : Tree?
  people_part : String?
  people_tree : Tree?
  people : Array[ThreadPerson]
  messages : Array[ThreadMessage]
}

///|
fn thread_guid(value : String) -> String raise @failure.Failure {
  let raw = if value.length() == 38 &&
    value.has_prefix("{") &&
    value.has_suffix("}") {
    value[1:37].to_owned()
  } else {
    value
  }
  guard raw.length() == 36 else {
    @failure.reject("protected-content", "Invalid thread or person identity")
  }
  for i in 0..<36 {
    guard (if [8, 13, 18, 23].contains(i) {
      raw[i] == '-'
    } else {
      (raw[i] >= '0' && raw[i] <= '9') ||
      (raw[i] >= 'a' && raw[i] <= 'f') ||
      (raw[i] >= 'A' && raw[i] <= 'F')
    }) else {
      @failure.reject("protected-content", "Invalid thread or person identity")
    }
  }
  "{" + raw.to_upper() + "}"
}

///|
fn check_thread_date(value : String) -> Unit raise @failure.Failure {
  guard (value.length() == 20 || value.length() == 24) &&
    value[4:5] == "-" &&
    value[7:8] == "-" &&
    value[10:11] == "T" &&
    value[13:14] == ":" &&
    value[16:17] == ":" &&
    value[value.length() - 1:] == "Z" &&
    (value.length() == 20 || value[19:20] == ".") else {
    @failure.reject(
      "invalid-operation", "Thread comments require an explicit UTC date",
    )
  }
  for i in 0..<value.length() {
    if [4, 7, 10, 13, 16, value.length() - 1].contains(i) ||
      (value.length() == 24 && i == 19) {
      continue
    }
    guard value[i] >= '0' && value[i] <= '9' else {
      @failure.reject("invalid-operation", "Invalid thread comment date")
    }
  }
  ignore(filter_current_date(value[:10].to_owned()))
  ignore(natural(value[11:13].to_owned(), 23))
  ignore(natural(value[14:16].to_owned(), 59))
  ignore(natural(value[17:19].to_owned(), 59))
}

///|
fn thread_markup(
  tree : Tree,
  node : @xml.Node,
  attributes : Array[String],
  children : Array[String],
) -> Unit raise @failure.Failure {
  guard node.uri == thread_uri &&
    node.attributes.all(a => a.uri.is_empty() && attributes.contains(a.name)) &&
    node.text.trim().is_empty() &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => n.uri == thread_uri && children.contains(n.name)) else {
    @failure.reject(
      "protected-content", "Unknown thread comment source is protected",
    )
  }
}

///|
fn thread_root(
  tree : Tree,
  name : String,
  children : Array[String],
) -> @xml.Node raise @failure.Failure {
  let root = tree.document.nodes()[0]
  let source = tree.document.source()[root.start:root.end]
  guard root.name == name && !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Opaque thread comment source is protected",
    )
  }
  thread_markup(tree, root, [], children)
  root
}

///|
fn Session::thread_part(
  self : Session,
  owner : String,
  kind : String,
) -> String? raise @failure.Failure {
  let links = self.relationships()
  let matches = links.filter(l => {
    l.owner == owner && l.kind == thread_relationship_uri + kind
  })
  guard matches.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate thread comment resource")
  }
  matches
  .get(0)
  .map(link => {
    guard !link.external &&
      links.filter(l => !l.external && l.target == link.target).length() == 1 else {
      @failure.reject(
        "protected-content", "Shared or external thread comment resource",
      )
    }
    link.target
  })
}

///|
fn Session::read_sheet_threads(
  self : Session,
  sheet : Sheet,
) -> SheetThreads raise @failure.Failure {
  let people_part = self.thread_part(self.main, "person")
  let people_tree = people_part.map(part => Tree::new(self.part_xml(part)))
  let people : Array[ThreadPerson] = []
  let seen : Set[String] = Set([])
  if people_tree is Some(tree) {
    let root = thread_root(tree, "personList", ["person"])
    let entries = tree.children.get(root.id).unwrap_or([])
    guard entries.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Thread authors exceed budget")
    }
    for node in entries {
      thread_markup(tree, node, ["id", "displayName", "userId", "providerId"], [])
      let id = thread_guid(node.attribute("id").unwrap_or(""))
      let name = node.attribute("displayName").unwrap_or("")
      check_note_author(name)
      guard !seen.contains(id) &&
        node.attributes.all(a => {
          a.value.length() <= 1024 && @xml.valid_text(a.value)
        }) else {
        @failure.reject(
          "protected-content", "Invalid or duplicate thread author",
        )
      }
      seen.add(id)
      people.push({ id, name, })
    }
  }
  let part = self.thread_part(sheet.id, "threadedComment")
  let tree = part.map(part => Tree::new(self.part_xml(part)))
  let messages : Array[ThreadMessage] = []
  if tree is Some(tree) {
    let root = thread_root(tree, "ThreadedComments", ["threadedComment"])
    let nodes = tree.children.get(root.id).unwrap_or([])
    guard nodes.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Thread comments exceed budget")
    }
    let roots : Map[String, Address] = Map([])
    let addresses : Set[String] = Set([])
    let ids : Set[String] = Set([])
    for node in nodes {
      thread_markup(
        tree,
        node,
        ["id", "parentId", "personId", "ref", "dT", "done"],
        ["text"],
      )
      let id = thread_guid(node.attribute("id").unwrap_or(""))
      guard !ids.contains(id) && !seen.contains(id) else {
        @failure.reject(
          "protected-content", "Duplicate thread comment identity",
        )
      }
      ids.add(id)
      if node.attribute("parentId") is None {
        let address = Address::parse(node.attribute("ref").unwrap_or(""))
        guard !addresses.contains(address.name()) else {
          @failure.reject("protected-content", "Duplicate cell comment thread")
        }
        addresses.add(address.name())
        roots[id] = address
      }
    }
    let mut units = 0
    for node in nodes {
      let id = thread_guid(node.attribute("id").unwrap())
      let parent = node.attribute("parentId").map(thread_guid)
      let address = roots
        .get(parent.unwrap_or(id))
        .unwrap_or_else(() => {
          @failure.reject(
            "protected-content", "Thread reply requires a direct root in the same sheet",
          )
        })
      guard node.attribute("ref").map(Address::parse).unwrap_or(address) ==
        address else {
        @failure.reject(
          "protected-content", "Thread reply address differs from its root",
        )
      }
      let person = thread_guid(node.attribute("personId").unwrap_or(""))
      guard people.any(p => p.id == person) else {
        @failure.reject("protected-content", "Thread comment author is missing")
      }
      let date = node.attribute("dT").unwrap_or("")
      check_thread_date(date)
      let bodies = tree.children.get(node.id).unwrap_or([])
      guard bodies is [body] &&
        body.name == "text" &&
        body.attributes.all(a => {
          a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
        }) &&
        tree.children.get(body.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "protected-content", "Thread comment requires ordinary text",
        )
      }
      let raw = decode_text(body.text)
      // Excel and ONLYOFFICE persist one final newline outside the comment text.
      let text = if raw.has_suffix("\n") {
        let value = raw[:raw.length() - 1].to_owned()
        if value.has_suffix("\r") {
          value[:value.length() - 1].to_owned()
        } else {
          value
        }
      } else {
        raw
      }
      guard text.length() <= 32767 && @xml.valid_text(text) else {
        @failure.reject("limit-exceeded", "Thread comment text exceeds budget")
      }
      units += text.length()
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Thread comments exceed text budget")
      }
      let done = node.attribute("done").unwrap_or("0")
      guard ["0", "1", "false", "true"].contains(done) else {
        @failure.reject("protected-content", "Unknown thread resolution state")
      }
      messages.push({
        node,
        body,
        id,
        parent,
        person,
        address,
        date,
        text,
        done: done == "1" || done == "true",
      })
    }
  }
  { part, tree, people_part, people_tree, people, messages, }
}

///|
/// Lists native messages for the cell or merged-cell owner without changing selection.
pub fn Session::threads(
  self : Session,
  revision : Int,
  sheet : String,
  cell : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let sheet = self.sheets[self.sheet_index(sheet)]
  let requested = Address::parse(cell)
  let range = sheet.merge_target({
    top: requested.row,
    bottom: requested.row,
    left: requested.column,
    right: requested.column,
  })
  let address : Address = { row: range.top, column: range.left, }
  let mut reason = self.dimension_reason(sheet)
  let items : Array[Json] = try {
    let threads = self.read_sheet_threads(sheet)
    self.check_thread_fallbacks(sheet, threads)
    let note = self
      .read_sheet_notes(sheet, allow_threads=true)
      .bind(notes => notes.entries.iter().find_first(n => n.address == address))
    if note is Some(note) && thread_placeholder_id(note.author) is None {
      reason = "An ordinary note already owns this cell"
    }
    let messages = threads.messages.filter(m => m.address == address)
    let ordered = messages.filter(m => m.parent is None)
    ordered.append(messages.filter(m => m.parent is Some(_)))
    ordered.map(fn(m) -> Json {
      {
        "id": m.id,
        "parentId": m.parent.map(p => Json(p)).unwrap_or(Json::null()),
        "personId": m.person,
        "author": threads.people
        .iter()
        .find_first(p => p.id == m.person)
        .unwrap().name,
        "date": m.date,
        "text": m.text,
        "resolved": m.done,
      }
    })
  } catch {
    @failure.Failure(message~, ..) => {
      reason = message
      []
    }
  }
  {
    "revision": revision,
    "sheet": sheet.id,
    "cell": address.name(),
    "reason": reason,
    "items": items,
  }
}
