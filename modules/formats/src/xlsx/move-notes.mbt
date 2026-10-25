///|
fn Session::move_notes(
  self : Session,
  sheet : Sheet,
  document : @xml.Document,
  source : Sheet,
  target : Sheet,
  relocation : CellMove,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let notes = self.read_sheet_notes(sheet, allow_threads=true)
  if notes is Some(notes) {
    let addresses : Map[String, Address?] = Map([])
    for note in notes.entries {
      if sheet.id == source.id && relocation.source.contains(note.address) {
        addresses[note.address.name()] = if source.id == target.id {
          Some(relocation.address(note.address))
        } else {
          None
        }
      } else if sheet.id == target.id &&
        relocation.target.contains(note.address) {
        addresses[note.address.name()] = None
      }
    }
    update_note_addresses(notes, addresses, parts, edits, threaded=true)
    update_thread_addresses(
      self.read_sheet_threads(sheet),
      addresses,
      parts,
      edits,
    )
  }
  if source.id == target.id || sheet.id != target.id {
    return document
  }
  guard self.read_sheet_notes(source, allow_threads=true) is Some(incoming) else {
    return document
  }
  let moved = incoming.entries.filter(note => {
    relocation.source.contains(note.address)
  })
  if moved.is_empty() {
    return document
  }
  let destinations = Map::from_array(
    moved.map(note => (note.address.name(), relocation.address(note.address))),
  )
  let document = self.insert_note_fragments(
    target,
    document,
    incoming,
    destinations,
    parts,
    edits,
    created,
    threaded=true,
  )
  self.insert_thread_fragments(
    { ..target, document, },
    self.read_sheet_threads(source),
    destinations,
    parts,
    edits,
    created,
  )
  document
}
