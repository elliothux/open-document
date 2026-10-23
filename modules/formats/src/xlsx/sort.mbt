///|
pub(all) struct SortKey {
  index : Int
  descending : Bool
  custom_list : Array[String]
  sort_by : String
  color : String
  icon_set : String
  icon_id : Int
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
  let selected = Range::parse(range)
  let table = self.sorting_table(
    sheet,
    selected,
    settings.rows,
    sparklines=true,
  )
  let target = table
    .map(table => Range::{
      ..table.range,
      top: table.range.top + table.headers,
      bottom: table.range.bottom - table.totals,
    })
    .unwrap_or(selected)
  let settings = if table is Some(_) {
    { ..settings, header: false, }
  } else {
    settings
  }
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
  let seen : Map[String, Bool] = Map([])
  for key in settings.keys {
    ignore(key.sort_format())
    let identity = "\{key.index}:\{key.sort_by}:" +
      (if key.sort_by == "icon" {
        "\{key.icon_set}:\{key.icon_id}"
      } else {
        key.color.to_upper()
      })
    guard key.index >= low && key.index <= high && !seen.contains(identity) else {
      @failure.reject(
        "invalid-operation", "Sort conditions must be distinct and stay within the selected range",
      )
    }
    seen[identity] = true
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  self.check_reorder_cells(
    current,
    target,
    filter=true,
    tables=self.formula_names().tables.any(table => table.sheet == sheet),
    sparklines=true,
  )
  let filter = if table is Some(_) {
    None
  } else {
    self.sheet_filters(current, self.parts).get(sheet)
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let positions : Array[Int] = []
  let rules = if settings.keys.any(key => key.sort_by != "value") {
    Some(self.filter_rules(index, work))
  } else {
    None
  }
  let lists = settings.keys.map(key => SortList::new(key.custom_list, work))
  let keys : Map[Int, Array[SortValue]] = Map([])
  let start = first + (if settings.header { 1 } else { 0 })
  let rich = self.rich_text_colors(
    index,
    current.cells
    .values()
    .filter(cell => {
      let position = if settings.rows {
        cell.address.row
      } else {
        cell.address.column
      }
      let key_index = if settings.rows {
        cell.address.column
      } else {
        cell.address.row
      }
      target.contains(cell.address) &&
      position >= start &&
      (if settings.rows {
        current.dimensions.rows
      } else {
        current.dimensions.columns
      }).size(position) !=
      0 &&
      settings.keys.any(key => {
        key.sort_by == "fontColor" && key.index == key_index
      })
    })
    .map(cell => cell.address)
    .to_array(),
    work,
  )
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
    keys[position] = settings.keys.mapi((at, key) => {
      let address : Address = if settings.rows {
        { row: position, column: key.index, }
      } else {
        { row: key.index, column: position, }
      }
      let name = address.name()
      let cell = current.cells.get(name)
      if key.sort_by == "icon" {
        return self.icon_sort_key(index, address, key, rules.unwrap(), work)
      }
      if key.sort_by != "value" {
        return self.color_sort_key(
          index,
          address,
          key,
          rules.unwrap(),
          rich,
          work,
        )
      }
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
      lists[at].value(value, settings.case_sensitive, work)
    })
  }
  let order = positions.copy()
  order.sort_by((a, b) => {
    for i, key in settings.keys {
      let comparison = sort_list_compare(keys[a][i], keys[b][i], key.descending)
      if comparison != 0 {
        return comparison
      }
    }
    a.compare(b)
  })
  if order == positions {
    return self.query()
  }
  let formatting = self.derive_conditional_styles(
    settings.keys.map(key => key.sort_format()),
  )
  self.reorder_cells(
    sheet,
    target,
    settings.rows,
    positions,
    order.map(i => Some(i)),
    filter~,
    sort=Some(stored_sort(target, settings, formatting.indices)),
    formatting=Some(formatting),
    table~,
  )
}
