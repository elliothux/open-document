///|
fn Session::cache_edits(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
) -> Array[(String, @xml.Edit)] raise @failure.Failure {
  let updates : Map[Int, Map[String, CellContent]] = Map([])
  for key in calculation.values.keys() {
    let cell = sheets[key.0].cells[key.1]
    let value = calculation.values[key]
    if value == cell.value {
      continue
    }
    if !updates.contains(key.0) {
      updates[key.0] = Map([])
    }
    updates[key.0][key.1] = { value, formula: cell.formula, keep_shared: true, }
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
      self.style_count,
    )
    edits.push((sheet.id, edit))
  }
  edits
}
