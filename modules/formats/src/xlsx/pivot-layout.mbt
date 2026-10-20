///|
priv struct PivotLayout {
  cache : PivotCache
  members : Array[Array[Int]]
  columns : Array[Array[Int]]
  values : Array[Array[Value]]
  row_totals : Array[Array[Value]]
  column_totals : Array[Array[Value]]
  total : Array[Value]
  filtered_count : Int
}

///|
fn PivotSettings::header_rows(self : PivotSettings) -> Int {
  if self.columns.is_empty() {
    1
  } else {
    1 + self.columns.length() + (if self.values.length() > 1 { 1 } else { 0 })
  }
}

///|
fn PivotSettings::data_width(self : PivotSettings, columns : Int) -> Int {
  if self.columns.is_empty() {
    self.values.length()
  } else {
    ((columns + 1) * self.values.length()).max(
      self.columns.length() + (if self.values.length() > 1 { 1 } else { 0 }),
    )
  }
}

///|
fn pivot_member_order(a : Array[Int], b : Array[Int]) -> Int {
  for index in 0..<a.length() {
    let order = a[index].compare(b[index])
    if order != 0 {
      return order
    }
  }
  0
}

///|
fn PivotCache::layout(
  self : PivotCache,
  settings : PivotSettings,
) -> PivotLayout raise @failure.Failure {
  let rows : Map[String, (Array[Int], Array[PivotStatistic])] = Map([])
  let columns : Map[String, (Array[Int], Array[PivotStatistic])] = Map([])
  let cells : Map[String, Array[PivotStatistic]] = Map([])
  let total = settings.values.map(_ => PivotStatistic::new())
  let filters = settings.filters.map(filter => {
    (
      filter.field,
      filter.values.map(values => {
        let keys : Map[String, Bool] = Map([])
        for value in values {
          keys[pivot_item_key(value)] = true
        }
        let selected : Map[Int, Bool] = Map([])
        for at, value in self.items[filter.field] {
          if keys.contains(pivot_item_key(value)) {
            selected[at] = true
          }
        }
        selected
      }),
    )
  })
  let mut filtered_count = 0
  let mut units = 0
  for record in self.records {
    if filters.any(filter => {
        filter.1.map(keys => !keys.contains(record[filter.0])).unwrap_or(false)
      }) {
      continue
    }
    filtered_count += 1
    let row = settings.rows.map(field => record[field])
    let column = settings.columns.map(field => record[field])
    let row_key = Json(row).stringify()
    let column_key = Json(column).stringify()
    for
      (groups, key, members, fields) in [
        (rows, row_key, row, settings.rows),
        (columns, column_key, column, settings.columns),
      ] {
      if !groups.contains(key) {
        guard groups.length() < 4096 else {
          @failure.reject("limit-exceeded", "Pivot axis exceeds group budget")
        }
        for at, item in members {
          units += self.items[fields[at]][item].display().length()
        }
        guard units <= 1048576 else {
          @failure.reject("limit-exceeded", "Pivot axis text exceeds budget")
        }
        groups[key] = (members, settings.values.map(_ => PivotStatistic::new()))
      }
    }
    guard (rows.length() + settings.page_rows() + settings.header_rows() + 1).to_int64() *
      (settings.rows.length() + settings.data_width(columns.length())).to_int64() <=
      32768 else {
      @failure.reject("limit-exceeded", "Pivot output exceeds budget")
    }
    let key = Json((row, column)).stringify()
    let statistics = match cells.get(key) {
      Some(value) => value
      None => {
        let value = settings.values.map(_ => PivotStatistic::new())
        cells[key] = value
        value
      }
    }
    for at, field in settings.values {
      let value = self.items[field.field][record[field.field]]
      statistics[at].add(value)
      rows[row_key].1[at].add(value)
      columns[column_key].1[at].add(value)
      total[at].add(value)
    }
  }
  if columns.is_empty() && settings.columns.is_empty() {
    columns["[]"] = ([], settings.values.map(_ => PivotStatistic::new()))
  }
  let row_groups = rows.values().to_array()
  let column_groups = columns.values().to_array()
  row_groups.sort_by((a, b) => pivot_member_order(a.0, b.0))
  column_groups.sort_by((a, b) => pivot_member_order(a.0, b.0))
  let values = fn(statistics : Array[PivotStatistic]) {
    statistics.mapi((at, value) => value.value(settings.values[at].aggregate))
  }
  {
    cache: self,
    members: row_groups.map(group => group.0),
    columns: column_groups.map(group => group.0),
    values: row_groups.map(row => {
      let result : Array[Value] = []
      for column in column_groups {
        match cells.get(Json((row.0, column.0)).stringify()) {
          Some(statistics) => result.append(values(statistics))
          None => result.append(settings.values.map(_ => Blank))
        }
      }
      result
    }),
    row_totals: row_groups.map(group => values(group.1)),
    column_totals: column_groups.map(group => values(group.1)),
    total: values(total),
    filtered_count,
  }
}

///|
fn PivotLayout::bounds(
  self : PivotLayout,
  settings : PivotSettings,
  address : Address,
) -> Range raise @failure.Failure {
  let range : Range = {
    top: address.row,
    left: address.column,
    bottom: address.row +
    settings.page_rows() +
    settings.header_rows() +
    self.members.length(),
    right: address.column +
    settings.rows.length() +
    settings.data_width(self.columns.length()) -
    1,
  }
  ignore(Range::parse(range.name()))
  range
}

///|
fn PivotLayout::caption(
  self : PivotLayout,
  settings : PivotSettings,
  original : String,
) -> String {
  let names = self.cache.headers.map(name => name.to_lower()) +
    settings.values.map(value => value.name.to_lower())
  let base = if original.is_empty() { "Values" } else { original }
  let mut name = base
  let mut suffix = 2
  while names.contains(name.to_lower()) {
    name = base + suffix.to_string()
    suffix += 1
  }
  name
}

///|
fn PivotLayout::cells(
  self : PivotLayout,
  settings : PivotSettings,
  range : Range,
  data_caption~ : String = "",
) -> (Map[String, CellContent], Map[String, Int]) raise @failure.Failure {
  let updates : Map[String, CellContent] = Map([])
  let styles : Map[String, Int] = Map([])
  let header = settings.header_rows()
  let body = settings.body(range)
  let values = settings.values.length()
  let width = self.columns.length() * values
  let has_columns = !settings.columns.is_empty()
  let caption = self.caption(settings, data_caption)
  let mut units = 0
  for row in range.top..<=range.bottom {
    for column in range.left..<=range.right {
      let offset = column - range.left
      let data = row - body.top - header
      let value_column = offset - settings.rows.length()
      let key = Address::{ row, column, }.name()
      let mut style : Int? = None
      let value = if row < body.top {
        let at = row - range.top
        if at < settings.filters.length() {
          let filter = settings.filters[at]
          if offset == 0 {
            Text(self.cache.headers[filter.field])
          } else if offset == 1 {
            if filter.values is Some([value]) {
              style = self.cache.items[filter.field]
                .search_by(item => pivot_item_key(item) == pivot_item_key(value))
                .map(index => self.cache.styles[filter.field][index])
            }
            self.cache.filter_caption(filter)
          } else {
            Blank
          }
        } else {
          Blank
        }
      } else if data < 0 {
        let level = row - body.top
        if offset < settings.rows.length() {
          if level == header - 1 {
            Text(self.cache.headers[settings.rows[offset]])
          } else if level == 0 && offset == 0 && values == 1 {
            Text(settings.values[0].name)
          } else {
            Blank
          }
        } else if !has_columns {
          Text(settings.values[value_column].name)
        } else if level == 0 {
          if value_column < settings.columns.length() {
            Text(self.cache.headers[settings.columns[value_column]])
          } else if values > 1 && value_column == settings.columns.length() {
            Text(caption)
          } else {
            Blank
          }
        } else if level <= settings.columns.length() && value_column < width {
          let field = settings.columns[level - 1]
          let item = self.columns[value_column / values][level - 1]
          style = Some(self.cache.styles[field][item])
          match self.cache.items[field][item] {
            Blank => Text("(blank)")
            value => value
          }
        } else if level == 1 && value_column == width {
          Text("Grand Total")
        } else if values > 1 &&
          level == header - 1 &&
          value_column < width + values {
          Text(settings.values[value_column % values].name)
        } else {
          Blank
        }
      } else if offset < settings.rows.length() {
        if row == range.bottom {
          if offset == 0 {
            Text("Grand Total")
          } else {
            Blank
          }
        } else {
          let field = settings.rows[offset]
          let item = self.members[data][offset]
          style = Some(self.cache.styles[field][item])
          match self.cache.items[field][item] {
            Blank => Text("(blank)")
            value => value
          }
        }
      } else if value_column < width {
        if row == range.bottom {
          self.column_totals[value_column / values][value_column % values]
        } else {
          self.values[data][value_column]
        }
      } else if has_columns && value_column < width + values {
        if row == range.bottom {
          self.total[value_column - width]
        } else {
          self.row_totals[data][value_column - width]
        }
      } else {
        Blank
      }
      units += value.display().length()
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Pivot output text exceeds budget")
      }
      updates[key] = { value, formula: None, keep_shared: false, }
      if style is Some(style) {
        styles[key] = style
      }
    }
  }
  (updates, styles)
}
