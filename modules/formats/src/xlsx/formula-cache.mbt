///|
fn Session::cache_edits(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
  style_count~ : Int32 = self.styles.length(),
) -> Array[(String, @xml.Edit)] raise @failure.Failure {
  let updates : Map[Int32, Map[String, CellContent]] = Map([])
  for (index, address), value in calculation.values {
    let key = address.name()
    let cell = sheets[index].cells[key]
    if value == cell.value {
      continue
    }
    if !updates.contains(index) {
      updates[index] = Map([])
    }
    updates[index][key] = { value, formula: cell.formula, keep_shared: true, }
  }
  let edits : Array[(String, @xml.Edit)] = []
  for index, cells in updates {
    let sheet = sheets[index]
    let (document, edit) = sheet.prepare(cells)
    sheets[index] = Sheet::read(
      sheet.id,
      sheet.name,
      sheet.state,
      document,
      self.strings,
      style_count,
    )
    edits.push((sheet.id, edit))
  }
  edits
}

///|
fn Sheet::expand_shared_updates(
  self : Sheet,
  updates : Map[String, CellContent],
) -> Unit {
  let groups : Map[Int32, Bool] = Map([])
  for key in updates.keys() {
    if self.cells.get(key).bind(cell => cell.group) is Some(group) {
      groups[group] = true
    }
  }
  for key, cell in self.cells {
    if cell.group is Some(group) &&
      groups.contains(group) &&
      !updates.contains(key) {
      updates[key] = {
        value: cell.value,
        formula: cell.formula,
        keep_shared: false,
      }
    }
  }
}
