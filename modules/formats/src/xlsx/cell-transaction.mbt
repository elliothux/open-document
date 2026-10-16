///|
fn Session::commit_cells(
  self : Session,
  updates : Map[Int, Map[String, CellContent]],
  selection : (String, Range),
  styles~ : Map[Int, Map[String, Int]] = Map([]),
  accept_warnings~ : Bool = false,
) -> Json raise @failure.Failure {
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  if updates.is_empty() {
    return self.query()
  }
  let candidate = self.sheets.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let changed : Array[(Int, Range)] = []
  let indices = updates.keys().to_array()
  let targets : Map[Int, Array[String]] = Map([])
  indices.sort()
  for index in indices {
    let current = self.sheets[index]
    let values = updates[index]
    targets[index] = values.keys().to_array()
    current.expand_shared_updates(values)
    let (document, edit) = current.prepare(
      values,
      styles=styles.get(index).unwrap_or(Map([])),
    )
    candidate[index] = Sheet::read(
      current.id,
      current.name,
      current.state,
      document,
      self.strings,
      self.styles.length(),
    )
    edits.push((current.id, edit))
    for key in values.keys() {
      let address = Address::parse(key)
      changed.push(
        (
          index,
          {
            top: address.row,
            bottom: address.row,
            left: address.column,
            right: address.column,
          },
        ),
      )
    }
  }
  let calculation = Calculation::build(
    candidate,
    self.calculation,
    changed,
    self.date1904,
  )
  self.validate_inputs(candidate, calculation, targets, accept_warnings)
  edits.append(self.cache_edits(candidate, calculation))
  self.commit(candidate, self.workbook, calculation, edits, selection)
  self.query()
}
