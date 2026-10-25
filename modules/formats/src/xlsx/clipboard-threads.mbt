///|
fn CopiedNotes::read_threads(
  self : CopiedNotes,
  budget~ : @archive.Budget = @archive.Budget::default(),
) -> SheetThreads raise @failure.Failure {
  match (self.threads, self.people) {
    (None, None) => read_thread_parts(None, None, None, None)
    (Some(comments), Some(people)) => {
      let tree = Tree::new(
        @xml.Document::parse(
          @utf8.encode(comments),
          "copied-threads",
          budget.xml_depth,
          budget.entry_bytes,
        ),
      )
      let roster = Tree::new(
        @xml.Document::parse(
          @utf8.encode(people),
          "copied-persons",
          budget.xml_depth,
          budget.entry_bytes,
        ),
      )
      let threads = read_thread_parts(
        Some("copied-threads"),
        Some(tree),
        Some("copied-persons"),
        Some(roster),
      )
      let used = Set::from_array(
        threads.messages.map(message => message.person),
      )
      guard !threads.messages.is_empty() &&
        used.length() == threads.people.length() else {
        @failure.reject(
          "invalid-operation", "Copied threads require exactly their referenced authors",
        )
      }
      threads
    }
    _ =>
      @failure.reject(
        "invalid-operation", "Copied native threads and people must be supplied together",
      )
  }
}

///|
fn copied_thread_source(
  source : SheetThreads,
  range : Range,
  units~ : Int64,
) -> (String?, String?) raise @failure.Failure {
  let messages = source.messages.filter(message => {
    range.contains(message.address)
  })
  if messages.is_empty() {
    return (None, None)
  }
  let used = Set::from_array(messages.map(message => message.person))
  let mut total = units
  let comments = StringBuilder()
  for message in messages {
    let markup = style_markup(source.tree.unwrap(), message.node)
    total += markup.length().to_int64()
    guard total <= 2097152L else {
      @failure.reject("limit-exceeded", "Copied thread source exceeds budget")
    }
    comments.write_string(markup)
  }
  let people = StringBuilder()
  let roster = source.people_tree.unwrap()
  for node in roster.document.nodes() {
    if node.uri == thread_uri &&
      node.name == "person" &&
      used.contains(thread_guid(node.attribute("id").unwrap())) {
      let markup = style_markup(roster, node)
      total += markup.length().to_int64()
      guard total <= 2097152L else {
        @failure.reject("limit-exceeded", "Copied thread source exceeds budget")
      }
      people.write_string(markup)
    }
  }
  (
    Some(
      "<ThreadedComments xmlns=\"\{thread_uri}\">\{comments.to_string()}</ThreadedComments>",
    ),
    Some(
      "<personList xmlns=\"\{thread_uri}\">\{people.to_string()}</personList>",
    ),
  )
}

///|
fn matching_thread_people(
  incoming : SheetThreads,
  previous : SheetThreads,
) -> Map[String, String] raise @failure.Failure {
  let existing : Map[(String, String?, String?), String] = Map([])
  for
    node in previous.people_tree
    .map(tree => tree.document.nodes())
    .unwrap_or([]) {
    if node.uri == thread_uri && node.name == "person" {
      let key = (
        node.attribute("displayName").unwrap(),
        node.attribute("userId"),
        node.attribute("providerId"),
      )
      if !existing.contains(key) {
        existing[key] = thread_guid(node.attribute("id").unwrap())
      }
    }
  }
  let matches : Map[String, String] = Map([])
  for
    node in incoming.people_tree
    .map(tree => tree.document.nodes())
    .unwrap_or([]) {
    if node.uri == thread_uri && node.name == "person" {
      let key = (
        node.attribute("displayName").unwrap(),
        node.attribute("userId"),
        node.attribute("providerId"),
      )
      if existing.get(key) is Some(id) {
        matches[thread_guid(node.attribute("id").unwrap())] = id
      }
    }
  }
  matches
}

///|
fn Session::prepare_thread_people(
  self : Session,
  incoming : SheetThreads,
  previous : SheetThreads,
  matches : Map[String, String],
  ids : Map[String, String],
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let added = incoming.people.filter(person => !matches.contains(person.id))
  guard previous.people.length() + added.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Copied thread authors exceed budget")
  }
  if added.is_empty() {
    return
  }
  let tree = incoming.people_tree.unwrap()
  let nodes : Map[String, @xml.Node] = Map([])
  for node in tree.document.nodes() {
    if node.uri == thread_uri && node.name == "person" {
      nodes[thread_guid(node.attribute("id").unwrap())] = node
    }
  }
  let xml = StringBuilder()
  let mut units = 0L
  for person in added {
    let node = nodes[person.id]
    matches[person.id] = ids[person.id]
    let markup = style_markup(
      tree,
      node,
      changes=metadata_changes(node, [("id", ids[person.id])]),
    )
    units += markup.length().to_int64()
    guard units <= 2097152L else {
      @failure.reject(
        "limit-exceeded", "Transferred thread authors exceed source budget",
      )
    }
    xml.write_string(markup)
  }
  if previous.people_tree is Some(tree) {
    let (next, edit) = tree.document.edit_source([
      insertion(tree.document.nodes()[0], xml.to_string()),
    ])
    parts[previous.people_part.unwrap()] = next
    edits.push((previous.people_part.unwrap(), edit))
  } else {
    ignore(
      self.create_sheet_resource(
        self.main,
        "person",
        "<personList xmlns=\"\{thread_uri}\">\{xml.to_string()}</personList>",
        parts,
        created,
        edits,
      ),
    )
  }
}

///|
fn copied_note_id_changes(
  document : @xml.Document,
  ids : Map[String, String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  for node in document.nodes() {
    if node.name == "author" &&
      thread_placeholder_id(decode_text(node.text)) is Some(id) &&
      ids.get(id) is Some(next) {
      changes.push({
        node: node.id,
        offset: node.opening_end - node.start,
        length: node.closing_start - node.opening_end,
        xml: encode_text("tc=" + next),
      })
    }
    if node.name == "comment" {
      for attr in node.attributes {
        if attr.uri ==
          "http://schemas.microsoft.com/office/spreadsheetml/2014/revision" &&
          attr.name == "uid" {
          changes.push({
            node: node.id,
            offset: attr.start - node.start,
            length: attr.end - attr.start,
            xml: ids[thread_guid(attr.value)],
          })
        }
      }
    }
  }
  changes
}

///|
fn remap_copied_notes(
  notes : SheetNotes,
  ids : Map[String, String],
) -> SheetNotes raise @failure.Failure {
  let changes = copied_note_id_changes(notes.tree.document, ids)
  if changes.is_empty() {
    return notes
  }
  let tree = Tree::new(notes.tree.document.edit_source(changes).0)
  let (authors, entries) = read_cell_notes(tree, threaded=true)
  { ..notes, tree, authors, entries, }
}

///|
fn remap_copied_threads(
  incoming : SheetThreads,
  ids : Map[String, String],
  people : Map[String, String],
  roster : SheetThreads,
) -> SheetThreads raise @failure.Failure {
  guard incoming.tree is Some(tree) else { return incoming }
  let changes : Array[@xml.SourceChange] = []
  for message in incoming.messages {
    let values = [("id", ids[message.id]), ("personId", people[message.person])]
    if message.parent is Some(parent) {
      values.push(("parentId", ids[parent]))
    }
    changes.append(metadata_changes(message.node, values))
  }
  read_thread_parts(
    incoming.part,
    Some(Tree::new(tree.document.edit_source(changes).0)),
    roster.people_part,
    roster.people_tree,
  )
}
