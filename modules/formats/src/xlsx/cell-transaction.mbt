///|
priv struct CellEditPlan {
  sheets : Array[Sheet]
  calculation : Calculation
  styles : Array[CellStyle]
  parts : Map[String, @xml.Document]
  created_parts : Map[String, @xml.Document]
  edits : Array[(String, @xml.Edit)]
}

///|
fn Session::prepare_cells(
  self : Session,
  updates : Map[Int, Map[String, CellContent]],
  styles~ : Map[Int, Map[String, Int]] = Map([]),
  merges~ : Map[Int, Array[Range]] = Map([]),
  accept_warnings~ : Bool = false,
  formatting~ : StyleEdit? = None,
  preserve_values~ : Bool = false,
  validate_values~ : Bool = true,
) -> CellEditPlan raise @failure.Failure {
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  let candidate = self.sheets.copy()
  let edits = formatting.map(plan => plan.edits.copy()).unwrap_or([])
  let cell_styles = formatting.map(plan => plan.styles).unwrap_or(self.styles)
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
      preserve_values~,
    )
    edits.push((current.id, edit))
    let document = if merges.get(index) is Some(ranges) &&
      ranges != current.merges {
      let (next, edit) = fill_merge_changes(document, ranges)
      edits.push((current.id, edit))
      next
    } else {
      document
    }
    candidate[index] = Sheet::read(
      current.id,
      current.name,
      current.state,
      document,
      self.strings,
      cell_styles.length(),
    )
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
  let calculation = self.calculate(
    candidate,
    self.calculation,
    changed,
    self.workbook,
  )
  if validate_values {
    self.validate_inputs(candidate, calculation, targets, accept_warnings)
  }
  edits.append(
    self.cache_edits(candidate, calculation, style_count=cell_styles.length()),
  )
  {
    sheets: candidate,
    calculation,
    edits,
    styles: cell_styles,
    parts: formatting.map(plan => plan.parts).unwrap_or(self.parts),
    created_parts: formatting.map(plan => plan.created_parts).unwrap_or(Map([])),
  }
}

///|
fn Session::commit_cells(
  self : Session,
  updates : Map[Int, Map[String, CellContent]],
  selection : (String, Range),
  styles~ : Map[Int, Map[String, Int]] = Map([]),
  merges~ : Map[Int, Array[Range]] = Map([]),
  accept_warnings~ : Bool = false,
) -> Json raise @failure.Failure {
  guard self.read_only.is_empty() else {
    @failure.reject("protected-content", self.read_only)
  }
  if updates.is_empty() {
    return self.query()
  }
  let plan = self.prepare_cells(updates, styles~, merges~, accept_warnings~)
  self.commit(
    plan.sheets,
    self.workbook,
    plan.calculation,
    plan.edits,
    selection,
    parts=plan.parts,
    created_parts=plan.created_parts,
  )
  self.query()
}
