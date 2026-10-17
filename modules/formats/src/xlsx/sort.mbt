///|
pub(all) struct SortKey {
  index : Int
  descending : Bool
}

///|
pub(all) struct SortSettings {
  rows : Bool
  header : Bool
  case_sensitive : Bool
  keys : Array[SortKey]
}

///|
fn sort_value(
  value : Value,
  sensitive : Bool,
  work : FormulaWork,
) -> Value raise @failure.Failure {
  work.spend(amount=value.display().length() + 1)
  let text = match value {
    Number(_) | Blank => return value
    Text("") => return Blank
    Text(text) => {
      let number = try @string.parse_double(text.trim()) catch {
        _ => None
      } noraise {
        value => Some(value)
      }
      if number is Some(n) && !n.is_nan() && !n.is_inf() {
        return Number(n)
      }
      text
    }
    _ => value.display()
  }
  if sensitive {
    Text(text)
  } else {
    let value = formula_case(text, true, work)
    guard value is Text(_) else {
      @failure.reject(
        "limit-exceeded", "Normalized sort key exceeds text budget",
      )
    }
    value
  }
}

///|
fn sort_compare(a : Value, b : Value, descending : Bool) -> Int {
  let result = match (a, b) {
    (Blank, Blank) => 0
    (Blank, _) => return 1
    (_, Blank) => return -1
    (Number(a), Number(b)) => a.compare(b)
    (Number(_), _) => -1
    (_, Number(_)) => 1
    // shortcut: Use fixed UTF-16 order until the core owns locale collation.
    (Text(a), Text(b)) => a[:].lexical_compare(b[:])
    _ => abort("Invalid sort key value")
  }
  if descending {
    -result
  } else {
    result
  }
}

///|
fn Session::sort_cells(
  self : Session,
  sheet : String,
  range : String,
  settings : SortSettings,
) -> Json raise @failure.Failure {
  let target = Range::parse(range)
  guard (target.bottom - target.top + 1).to_int64() *
    (target.right - target.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Sorting exceeds 4096 cells")
  }
  guard !settings.keys.is_empty() && settings.keys.length() <= 16 else {
    @failure.reject("invalid-operation", "Sorting requires 1 to 16 keys")
  }
  let (low, high, first, last) = if settings.rows {
    (target.left, target.right, target.top, target.bottom)
  } else {
    (target.top, target.bottom, target.left, target.right)
  }
  let seen : Map[Int, Bool] = Map([])
  for key in settings.keys {
    guard key.index >= low && key.index <= high && !seen.contains(key.index) else {
      @failure.reject(
        "invalid-operation", "Sort keys must identify distinct axes within the selected range",
      )
    }
    seen[key.index] = true
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard self.read_only.is_empty() && !current.locked else {
    @failure.reject(
      "protected-content",
      if current.locked {
        "Worksheet is protected"
      } else {
        self.read_only
      },
    )
  }
  guard !current.merges.any(merge => merge.intersects(target)) else {
    @failure.reject(
      "protected-content", "Merged cells require sorting geometry support",
    )
  }
  self.sort_resources(current, target)
  for cell in current.cells.values() {
    if target.contains(cell.address) {
      guard cell.read_only.is_empty() ||
        cell.read_only == "Rich text cell is read-only" else {
        @failure.reject("protected-content", cell.read_only)
      }
    }
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let positions : Array[Int] = []
  let keys : Map[Int, Array[Value]] = Map([])
  let start = first + (if settings.header { 1 } else { 0 })
  for position in start..<=last {
    if (if settings.rows {
        current.dimensions.rows
      } else {
        current.dimensions.columns
      }).size(position) ==
      0 {
      continue
    }
    positions.push(position)
    keys[position] = settings.keys.map(key => {
      let address : Address = if settings.rows {
        { row: position, column: key.index, }
      } else {
        { row: key.index, column: position, }
      }
      let name = address.name()
      let cell = current.cells.get(name)
      let value = if cell.bind(c => c.formula) is Some(_) {
        self.calculation
        .bind(c => c.values.get((index, name)))
        .unwrap_or_error(
          @failure.Failure(
            code="unsupported-formula",
            part=sheet,
            offset=-1,
            message="Sort keys require current formula results",
          ),
        )
      } else {
        cell.map(c => c.value).unwrap_or(Blank)
      }
      sort_value(value, settings.case_sensitive, work)
    })
  }
  let order = positions.copy()
  order.sort_by((a, b) => {
    for i, key in settings.keys {
      let comparison = sort_compare(keys[a][i], keys[b][i], key.descending)
      if comparison != 0 {
        return comparison
      }
    }
    a.compare(b)
  })
  if order == positions {
    return self.query()
  }
  let tree = Tree::new(current.document)
  let updates : Map[String, CellContent] = Map([])
  let styles : Map[String, Int] = Map([])
  let fragments : Map[String, String] = Map([])
  let moved : Map[Int, Int] = Map([])
  let mut units = 0L
  for i, destination in positions {
    let source = order[i]
    moved[source] = destination
    if source == destination {
      continue
    }
    for axis in low..<=high {
      let from : Address = if settings.rows {
        { row: source, column: axis, }
      } else {
        { row: axis, column: source, }
      }
      let to : Address = if settings.rows {
        { row: destination, column: axis, }
      } else {
        { row: axis, column: destination, }
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
  let edits = [(sheet, edit)]
  let tree = Tree::new(document)
  let links : Array[@xml.SourceChange] = []
  if tree.one(tree.root("worksheet").id, "hyperlinks") is Some(list) {
    for node in tree.all(list.id, "hyperlink") {
      let range = Range::parse(node.attribute("ref").unwrap_or(""))
      if range.top == range.bottom &&
        range.left == range.right &&
        range.intersects(target) {
        let source = if settings.rows { range.top } else { range.left }
        if moved.get(source) is Some(destination) && destination != source {
          let address : Address = if settings.rows {
            { row: destination, column: range.left, }
          } else {
            { row: range.top, column: destination, }
          }
          links.append(metadata_changes(node, [("ref", address.name())]))
        }
      }
    }
  }
  let document = if links.is_empty() {
    document
  } else {
    let (next, edit) = document.edit_source(links)
    edits.push((sheet, edit))
    next
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
  let calculation = Calculation::build(
    sheets,
    self.calculation,
    [(index, target)],
    self.date1904,
    self.workbook,
  )
  self.validate_inputs(
    sheets,
    calculation,
    Map([(index, updates.keys().to_array())]),
    false,
  )
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(sheets, self.workbook, calculation, edits, (sheet, target))
  self.query()
}
