///|
/// Native cell thread operations; new messages require explicit author and UTC time.
pub(all) enum ThreadEdit {
  CreateThread(String, String, String, String)
  ReplyThread(String, String, String, String)
  UpdateThread(String, String)
  ResolveThread(String, Bool)
  DeleteThread(String)
}

///|
fn thread_text(value : String) -> String raise @failure.Failure {
  guard value.length() <= 32767 &&
    !value.trim().is_empty() &&
    @xml.valid_text(value) else {
    @failure.reject(
      "invalid-text", "Thread comments require nonempty valid text within 32767 UTF-16 units",
    )
  }
  value.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
fn Session::thread_ids(self : Session) -> Set[String] raise @failure.Failure {
  let used : Set[String] = Set([])
  for link in self.relationships() {
    if !link.external &&
      [
        thread_relationship_uri + "person",
        thread_relationship_uri + "threadedComment",
      ].contains(link.kind) {
      for node in self.part_xml(link.target).nodes() {
        if node.attribute("id") is Some(id) {
          used.add(thread_guid(id)) catch {
            @failure.Failure(..) => ()
          }
        }
      }
    }
  }
  used
}

///|
fn numbered_thread_id(i : Int) -> String {
  let digits = i.to_string()
  "{00000000-0000-4000-8000-" + "0".repeat(12 - digits.length()) + digits + "}"
}

///|
fn Session::thread_id(
  self : Session,
  reserved : Set[String],
) -> String raise @failure.Failure {
  let used = self.thread_ids()
  for id in reserved {
    used.add(id)
  }
  for i in 1..<=16384 {
    let id = numbered_thread_id(i)
    if !used.contains(id) {
      return id
    }
  }
  @failure.reject("limit-exceeded", "Thread comment identities exhausted")
}

///|
fn thread_message_source(
  id : String,
  parent : String?,
  person : String,
  cell : Address,
  text : String,
  date : String,
) -> String raise @failure.Failure {
  let reply = parent.map(id => " parentId=\"\{id}\"").unwrap_or("")
  "<od:threadedComment xmlns:od=\"\{thread_uri}\" id=\"\{id}\" personId=\"\{person}\" ref=\"\{cell.name()}\" dT=\"\{escaped_attribute(date)}\"\{reply}><od:text xml:space=\"preserve\">\{encode_text(text)}\n</od:text></od:threadedComment>"
}

///|
/// Commits a native thread edit and all required parts as one exact source history item.
pub fn Session::edit_thread(
  self : Session,
  revision : Int,
  sheet : String,
  change : ThreadEdit,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheets[self.sheet_index(sheet)]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let threads = self.read_sheet_threads(current)
  self.check_thread_fallbacks(current, threads)
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let changes : Array[@xml.SourceChange] = []
  let mut affected : Address? = None
  let addition = match change {
    CreateThread(cell, text, author, date) => {
      let requested = Address::parse(cell)
      let range = current.merge_target({
        top: requested.row,
        bottom: requested.row,
        left: requested.column,
        right: requested.column,
      })
      let address : Address = { row: range.top, column: range.left, }
      affected = Some(address)
      guard !threads.messages.any(m => m.address == address && m.parent is None) else {
        @failure.reject("invalid-operation", "A cell thread already exists")
      }
      Some((address, None, thread_text(text), author, date))
    }
    ReplyThread(id, text, author, date) => {
      let id = thread_guid(id)
      let root = threads.messages
        .iter()
        .find_first(m => m.id == id && m.parent is None)
        .unwrap_or_else(() => {
          @failure.reject("invalid-operation", "Thread root no longer exists")
        })
      guard !root.done else {
        @failure.reject(
          "invalid-operation", "Reopen the thread before replying",
        )
      }
      affected = Some(root.address)
      Some((root.address, Some(root.id), thread_text(text), author, date))
    }
    UpdateThread(id, text) => {
      let id = thread_guid(id)
      let message = threads.messages
        .iter()
        .find_first(m => m.id == id)
        .unwrap_or_else(() => {
          @failure.reject(
            "invalid-operation", "Thread message no longer exists",
          )
        })
      let text = thread_text(text)
      affected = Some(message.address)
      if message.text == text {
        return self.query()
      }
      let node = message.body
      let markup = encode_text(text) + "\n"
      changes.push(
        if node.empty {
          insertion(node, markup)
        } else {
          {
            node: node.id,
            offset: node.opening_end - node.start,
            length: node.closing_start - node.opening_end,
            xml: markup,
          }
        },
      )
      None
    }
    ResolveThread(id, done) => {
      let id = thread_guid(id)
      let message = threads.messages
        .iter()
        .find_first(m => m.id == id && m.parent is None)
        .unwrap_or_else(() => {
          @failure.reject("invalid-operation", "Thread root no longer exists")
        })
      if message.done == done {
        return self.query()
      }
      changes.append(
        metadata_changes(message.node, [("done", if done { "1" } else { "0" })]),
      )
      affected = Some(message.address)
      None
    }
    DeleteThread(id) => {
      let id = thread_guid(id)
      let message = threads.messages
        .iter()
        .find_first(m => m.id == id)
        .unwrap_or_else(() => {
          @failure.reject(
            "invalid-operation", "Thread message no longer exists",
          )
        })
      let tree = threads.tree.unwrap()
      affected = Some(message.address)
      for item in threads.messages {
        if item.id == id || (message.parent is None && item.parent == Some(id)) {
          changes.push(sheet_node_removal(tree, item.node))
        }
      }
      None
    }
  }
  let mut new_message : String? = None
  if addition is Some((cell, parent, text, author, date)) {
    check_note_author(author)
    check_thread_date(date)
    guard threads.messages.length() < 4096 &&
      threads.messages
      .iter()
      .fold(init=text.length(), (sum, m) => sum + m.text.length()) <=
      1048576 else {
      @failure.reject("limit-exceeded", "Thread comments exceed budget")
    }
    let reserved : Set[String] = Set([])
    let person = threads.people
      .iter()
      .find_first(p => p.name == author)
      .map(p => p.id)
      .unwrap_or_else(() => {
        guard threads.people.length() < 4096 else {
          @failure.reject("limit-exceeded", "Thread authors exceed budget")
        }
        let id = self.thread_id(reserved)
        reserved.add(id)
        let markup = "<od:person xmlns:od=\"\{thread_uri}\" id=\"\{id}\" displayName=\"\{escaped_attribute(author)}\"/>"
        if threads.people_tree is Some(tree) {
          let (document, edit) = tree.document.edit_source([
            insertion(tree.document.nodes()[0], markup),
          ])
          parts[threads.people_part.unwrap()] = document
          edits.push((threads.people_part.unwrap(), edit))
        } else {
          ignore(
            self.create_sheet_resource(
              self.main,
              "person",
              "<personList xmlns=\"\{thread_uri}\">\{markup}</personList>",
              parts,
              created,
              edits,
            ),
          )
        }
        id
      })
    let id = self.thread_id(reserved)
    new_message = Some(
      thread_message_source(id, parent, person, cell, text, date),
    )
  }
  if threads.tree is Some(tree) {
    if new_message is Some(markup) {
      changes.push(insertion(tree.document.nodes()[0], markup))
    }
    let (document, edit) = tree.document.edit_source(join_insertions(changes))
    parts[threads.part.unwrap()] = document
    edits.push((threads.part.unwrap(), edit))
  } else if new_message is Some(markup) {
    ignore(
      self.create_sheet_resource(
        sheet,
        "threadedComment",
        "<ThreadedComments xmlns=\"\{thread_uri}\">\{markup}</ThreadedComments>",
        parts,
        created,
        edits,
      ),
    )
  }
  let candidate = { ..self, parts: parts.copy(), }
  let next = candidate.read_sheet_threads(current)
  let document = candidate
    .prepare_thread_fallback(
      current,
      affected.unwrap(),
      threads,
      next,
      parts,
      created,
      edits,
    )
    .unwrap_or(current.document)
  let sheets = self.sheets.copy()
  sheets[self.sheet_index(sheet)] = Sheet::read(
    sheet,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let complete = { ..self, parts, }
  complete.check_thread_fallbacks(sheets[self.sheet_index(sheet)], next)
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
