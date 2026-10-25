///|
fn thread_placeholder_id(author : String) -> String? {
  if !author.has_prefix("tc=") {
    return None
  }
  Some(thread_guid(author[3:].to_owned())) catch {
    @failure.Failure(..) => None
  }
}

///|
fn Session::check_thread_fallbacks(
  self : Session,
  sheet : Sheet,
  threads : SheetThreads,
) -> Unit raise @failure.Failure {
  let notes = self.read_sheet_notes(sheet, allow_threads=true)
  let roots : Map[String, String] = Map([])
  for message in threads.messages {
    if message.parent is None {
      roots[message.address.name()] = message.id
    }
  }
  if !roots.is_empty() {
    guard notes.bind(n => n.vml) is Some(_) else {
      @failure.reject(
        "protected-content", "Thread comment placeholders require VML anchors",
      )
    }
  }
  let found : Set[String] = Set([])
  for note in notes.map(n => n.entries).unwrap_or([]) {
    if thread_placeholder_id(note.author) is Some(id) {
      guard roots.get(note.address.name()) == Some(id) else {
        @failure.reject(
          "protected-content", "Thread placeholder and native root do not match",
        )
      }
      found.add(note.address.name())
    }
  }
  guard found.length() == roots.length() else {
    @failure.reject(
      "protected-content", "Thread comment placeholder is missing",
    )
  }
}

///|
fn Session::prepare_thread_fallback(
  self : Session,
  sheet : Sheet,
  address : Address,
  before : SheetThreads,
  after : SheetThreads,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> @xml.Document? raise @failure.Failure {
  let previous = before.messages
    .iter()
    .find_first(m => m.parent is None && m.address == address)
  let root = after.messages
    .iter()
    .find_first(m => m.parent is None && m.address == address)
  let note = self
    .read_sheet_notes(sheet, allow_threads=true)
    .bind(notes => notes.entries.iter().find_first(n => n.address == address))
  if note is Some(note) {
    guard thread_placeholder_id(note.author) is Some(id) &&
      previous.map(m => m.id) == Some(id) else {
      @failure.reject(
        "protected-content", "An ordinary note or unknown placeholder already owns this cell",
      )
    }
  }
  // The placeholder links the native root; replies and status remain in their native part.
  self.prepare_note(
    sheet,
    address,
    root.map(m => m.text),
    root.map(m => "tc=" + m.id).unwrap_or(""),
    parts,
    created,
    edits,
    allow_threads=true,
  )
}
