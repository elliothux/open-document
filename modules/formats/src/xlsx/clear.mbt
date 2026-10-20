///|
/// Clears contents, formats, or all supported cell data in one history entry.
pub fn Session::clear(
  self : Session,
  revision : Int,
  mode~ : String = "contents",
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["contents", "formats", "all"].contains(mode) else {
    @failure.reject("invalid-operation", "Unknown cell clearing mode")
  }
  if mode == "contents" {
    return self.clear_contents(revision)
  }
  let (id, selected) = self.selection
  let index = self.sheet_index(id)
  let current = self.sheets[index]
  let target = current.merge_target(selected)
  let reason = self.format_reason(current, target)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let reason = sparkline_reason(current, self.sheets)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let (normal, styles, style_edits) = self.normal_style()
  guard styles[normal].diagnostic.is_empty() else {
    @failure.reject("protected-content", styles[normal].diagnostic)
  }
  let all = mode == "all"
  let updates : Map[String, CellContent] = Map([])
  let indices : Map[String, Int] = Map([])
  let changed : Array[(Int, Range)] = []
  for row in target.top..<=target.bottom {
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let key = address.name()
      let content = current.cells
        .get(key)
        .map(cell => cell.value != Blank || cell.formula is Some(_))
        .unwrap_or(false)
      if current.style_at(address) != normal || (all && content) {
        updates[key] = { value: Blank, formula: None, keep_shared: false, }
        indices[key] = normal
        if all && content {
          changed.push(
            (index, { top: row, bottom: row, left: column, right: column, }),
          )
        }
      }
    }
  }
  let mut document = current.document
  let edits : Array[(String, @xml.Edit)] = []
  if !updates.is_empty() {
    if all {
      current.expand_shared_updates(updates)
    }
    let (next, edit) = current.prepare(
      updates,
      styles=indices,
      preserve_values=!all,
    )
    document = next
    edits.push((id, edit))
  }
  let rules = clear_rules(document, target, all, sparklines=true)
  if !rules.is_empty() {
    let (next, edit) = document.edit_source(rules)
    document = next
    edits.push((id, edit))
  }
  if all && current.sparklines.items.any(item => target.contains(item.cell)) {
    let candidate = Sheet::read(
      id,
      current.name,
      current.state,
      document,
      self.strings,
      styles.length(),
    )
    let changes = candidate.sparkline_changes(
      candidate.sparklines.items.filter(item => !target.contains(item.cell)),
    )
    let (next, edit) = document.edit_source(changes)
    document = next
    edits.push((id, edit))
  }
  let parts = self.parts.copy()
  if all && self.read_sheet_notes(current) is Some(notes) {
    let addresses : Map[String, Address?] = Map([])
    for note in notes.entries {
      if target.contains(note.address) {
        addresses[note.address.name()] = None
      }
    }
    update_note_addresses(notes, addresses, parts, edits)
  }
  if edits.is_empty() {
    return self.query()
  }
  for (path, document, edit) in style_edits {
    parts[path] = document
    edits.push((path, edit))
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    id,
    current.name,
    current.state,
    document,
    self.strings,
    styles.length(),
  )
  let calculation = if changed.is_empty() {
    self.calculation.unwrap()
  } else {
    self.calculate(sheets, self.calculation, changed, self.workbook)
  }
  if !changed.is_empty() {
    edits.append(
      self.cache_edits(sheets, calculation, style_count=styles.length()),
    )
  }
  self.commit(sheets, self.workbook, calculation, edits, (id, target), parts~)
  self.query()
}
