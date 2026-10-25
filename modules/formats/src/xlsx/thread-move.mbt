///|
fn Session::insert_thread_fragments(
  self : Session,
  target : Sheet,
  incoming : SheetThreads,
  destinations : Map[String, Address],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  created : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  let moved = incoming.messages.filter(message => {
    destinations.contains(message.address.name())
  })
  if moved.is_empty() {
    return
  }
  let candidate = { ..self, parts: parts.copy(), }
  let previous = candidate.read_sheet_threads(target)
  guard previous.messages.length() + moved.length() <= 4096 &&
    previous.messages.fold(init=0L, (sum, message) => {
      sum + message.text.length().to_int64()
    }) +
    moved.fold(init=0L, (sum, message) => sum + message.text.length().to_int64()) <=
    1048576L else {
    @failure.reject(
      "limit-exceeded", "Transferred native threads exceed budget",
    )
  }
  let ids = Set::from_array(previous.messages.map(message => message.id))
  let xml = StringBuilder()
  let mut units = 0L
  for message in moved {
    guard !ids.contains(message.id) else {
      @failure.reject(
        "protected-content", "Transferred thread identities collide",
      )
    }
    ids.add(message.id)
    let address = destinations[message.address.name()]
    // A reply without ref continues to inherit its root's destination.
    let changes = if message.node.attribute("ref") is Some(_) {
      metadata_changes(message.node, [("ref", address.name())])
    } else {
      []
    }
    let markup = style_markup(incoming.tree.unwrap(), message.node, changes~)
    units += markup.length().to_int64()
    guard units <= 2097152L else {
      @failure.reject(
        "limit-exceeded", "Transferred thread source exceeds budget",
      )
    }
    xml.write_string(markup)
  }
  if previous.tree is Some(tree) {
    let (next, edit) = tree.document.edit_source([
      insertion(tree.document.nodes()[0], xml.to_string()),
    ])
    parts[previous.part.unwrap()] = next
    edits.push((previous.part.unwrap(), edit))
  } else {
    ignore(
      self.create_sheet_resource(
        target.id,
        "threadedComment",
        "<ThreadedComments xmlns=\"\{thread_uri}\">\{xml.to_string()}</ThreadedComments>",
        parts,
        created,
        edits,
      ),
    )
  }
}
