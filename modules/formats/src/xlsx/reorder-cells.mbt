///|
fn Session::reorder_cells(
  self : Session,
  sheet : String,
  target : Range,
  rows : Bool,
  positions : Array[Int],
  order : Array[Int?],
  filter~ : AutoFilterState? = None,
  sort~ : StoredSort? = None,
  formatting~ : ConditionalStyleEdit? = None,
  table~ : StructuredTable? = None,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let table_filters = if self.formula_names().tables.any(table => {
      table.sheet == sheet
    }) {
    self.sheet_filters(current, self.parts)
  } else {
    Map([])
  }
  let notes = self.read_sheet_notes(current)
  let (low, high) = if rows {
    (target.left, target.right)
  } else {
    (target.top, target.bottom)
  }
  let tree = Tree::new(current.document)
  let updates : Map[String, CellContent] = Map([])
  let styles : Map[String, Int] = Map([])
  let fragments : Map[String, String] = Map([])
  let moved : Map[Int, Int] = Map([])
  for i, destination in positions {
    if order[i] is Some(source) {
      moved[source] = destination
    }
  }
  let removed = Map::from_array(
    positions
    .filter(source => !moved.contains(source))
    .map(source => (source, true)),
  )
  let mut units = 0L
  for i, destination in positions {
    let source = order[i]
    if source == Some(destination) {
      continue
    }
    for axis in low..<=high {
      let to : Address = if rows {
        { row: destination, column: axis, }
      } else {
        { row: axis, column: destination, }
      }
      guard source is Some(source) else {
        updates[to.name()] = {
          value: Blank,
          formula: None,
          keep_shared: false,
        }
        fragments[to.name()] = ""
        continue
      }
      let from : Address = if rows {
        { row: source, column: axis, }
      } else {
        { row: axis, column: source, }
      }
      let cell = current.cells.get(from.name())
      let formula = cell
        .bind(c => c.formula)
        .map(f => {
          parse_formula(f).source(
            rows=to.row - from.row,
            columns=to.column - from.column,
            invalid_ref=true,
          )
        })
      let value : CellContent = {
        value: cell.map(c => c.value).unwrap_or(Blank),
        formula,
        keep_shared: false,
      }
      let name = to.name()
      let markup = current.sorted_cell(tree, from, to, value)
      units += markup.length().to_int64()
      guard units <= 1048576L else {
        @failure.reject("limit-exceeded", "Sorted cell source exceeds budget")
      }
      updates[name] = value
      styles[name] = current.style_at(from)
      fragments[name] = markup
    }
  }
  current.expand_shared_updates(updates)
  let (document, edit) = current.prepare(updates, styles~, fragments~)
  let edits = formatting.map(plan => plan.edits.copy()).unwrap_or([])
  edits.push((sheet, edit))
  let parts = formatting
    .map(plan => plan.parts.copy())
    .unwrap_or(self.parts.copy())
  if notes is Some(notes) {
    let addresses : Map[String, Address?] = Map([])
    for note in notes.entries {
      if target.contains(note.address) {
        let source = if rows { note.address.row } else { note.address.column }
        if moved.get(source) is Some(destination) {
          addresses[note.address.name()] = Some(
            if rows {
              { ..note.address, row: destination, }
            } else {
              { ..note.address, column: destination, }
            },
          )
        } else if removed.contains(source) {
          addresses[note.address.name()] = None
        }
      }
    }
    update_note_addresses(notes, addresses, parts, edits)
  }
  let tree = Tree::new(document)
  let links : Array[@xml.SourceChange] = []
  if tree.one(tree.root("worksheet").id, "hyperlinks") is Some(list) {
    let changes : Array[@xml.SourceChange] = []
    let mut deleted = 0
    for node in tree.all(list.id, "hyperlink") {
      let range = Range::parse(node.attribute("ref").unwrap_or(""))
      if rows &&
        range.top == range.bottom &&
        target.covers(range) &&
        removed.contains(range.top) {
        changes.push(sheet_node_removal(tree, node))
        deleted += 1
        continue
      }
      if range.top == range.bottom &&
        range.left == range.right &&
        range.intersects(target) {
        let source = if rows { range.top } else { range.left }
        if moved.get(source) is Some(destination) && destination != source {
          let address : Address = if rows {
            { row: destination, column: range.left, }
          } else {
            { row: range.top, column: destination, }
          }
          changes.append(metadata_changes(node, [("ref", address.name())]))
        }
      }
    }
    if deleted > 0 &&
      deleted == tree.children.get(list.id).unwrap_or([]).length() {
      links.push(sheet_node_removal(tree, list))
    } else {
      links.append(changes)
    }
  }
  let document = if links.is_empty() {
    document
  } else {
    let (next, edit) = document.edit_source(links)
    edits.push((sheet, edit))
    next
  }
  let nested = filter
    .map(state => {
      sort.map(sort => state.bounds.covers(sort.bounds)).unwrap_or(false)
    })
    .unwrap_or(false)
  let filter = if nested {
    filter.map(state => { ..state, sort, })
  } else {
    filter
  }
  if filter is Some(state) && table_filters.get(sheet) is Some(previous) {
    table_filters[sheet] = { ..previous, sort: state.sort, }
  }
  if table is Some(table) && sort is Some(sort) {
    self.write_table_sort(table, sort, parts, edits)
    if table_filters.get(table.part) is Some(state) {
      table_filters[table.part] = { ..state, sort: None, }
    }
  }
  let document = if sort is Some(sort) && !nested && table is None {
    let (document, edit) = write_sort_state(document, sort)
    edits.push((sheet, edit))
    document
  } else {
    document
  }
  if edits.all(entry => entry.1.payload_bytes() == 0) {
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let mut calculation = self.calculate(
    sheets,
    self.calculation,
    [(index, target)],
    self.workbook,
    parts~,
  )
  if table is Some(_) || !table_filters.is_empty() {
    let targets = table_filters
      .keys()
      .filter(part => {
        table.map(table => part == table.part).unwrap_or(false) ||
        part == sheet ||
        !table_filters[part].settings.columns.is_empty()
      })
      .to_array()
    if !targets.is_empty() {
      calculation = self.reapply_candidate_filters(
        index,
        table_filters,
        targets,
        sheets,
        self.workbook,
        calculation,
        parts,
        edits,
      )
    }
  } else if filter is Some(state) {
    calculation = self.reapply_candidate_filters(
      index,
      Map([(sheet, state)]),
      [sheet],
      sheets,
      self.workbook,
      calculation,
      parts,
      edits,
    )
  }
  self.validate_inputs(
    sheets,
    calculation,
    Map([(index, updates.keys().to_array())]),
    false,
  )
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(
    sheets,
    self.workbook,
    calculation,
    edits,
    (sheet, target),
    parts~,
    table_edits=table.map(table => [table.part]).unwrap_or([]),
    created_parts=formatting.map(plan => plan.created_parts).unwrap_or(Map([])),
  )
  self.query()
}
