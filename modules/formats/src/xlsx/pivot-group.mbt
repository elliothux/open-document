///|
pub(all) struct PivotNumberGroup {
  field : Int
  start : Double
  end : Double
  interval : Double
} derive(ToJson)

///|
pub extend PivotNumberGroup with ToJson::{to_json}

///|
priv struct PivotGroupItems {
  settings : PivotGrouping
  items : Array[Value]
  indices : Array[Int]
}

///|
priv enum PivotGrouping {
  Numeric(PivotNumberGroup)
  DateBuckets(PivotDateGroup, unit~ : String, start~ : Double, end~ : Double)
}

///|
fn PivotGroupItems::base(self : PivotGroupItems) -> Int {
  match self.settings {
    Numeric(group) => group.field
    DateBuckets(group, ..) => group.field
  }
}

///|
fn pivot_expand_axis(
  axis : Array[Int],
  fields : Map[Int, Array[Int]],
) -> Array[Int] {
  let result : Array[Int] = []
  for field in axis {
    result.append(fields.get(field).unwrap_or([field]))
  }
  result
}

///|
fn pivot_expand_settings(
  settings : PivotSettings,
  fields : Map[Int, Array[Int]],
) -> PivotSettings {
  let rows = pivot_expand_axis(settings.rows, fields)
  let columns = pivot_expand_axis(settings.columns, fields)
  let subtotal_fields = pivot_expand_axis(settings.subtotals, fields)
  {
    ..settings,
    rows,
    columns,
    subtotals: subtotal_fields.filter(field => {
      rows[:(rows.length() - 1).max(0)].contains(field) ||
      columns[:(columns.length() - 1).max(0)].contains(field)
    }),
  }
}

///|
fn pivot_source_axis(
  axis : Array[Int],
  fields : Map[Int, Array[Int]],
  width : Int,
) -> Array[Int] raise @failure.Failure {
  let result : Array[Int] = []
  let mut at = 0
  while at < axis.length() {
    let native = axis[at]
    let base = if native < width {
      native
    } else {
      fields
      .iter()
      .find_first(pair => pair.1.contains(native))
      .map(pair => pair.0)
      .unwrap_or(-1)
    }
    let expected = fields.get(base).unwrap_or([base])
    guard base >= 0 &&
      at + expected.length() <= axis.length() &&
      axis[at:at + expected.length()].to_owned() == expected &&
      !result.contains(base) else {
      @failure.reject(
        "protected-content", "Pivot derived calendar axis order requires support",
      )
    }
    result.push(base)
    at += expected.length()
  }
  result
}

///|
fn pivot_group_compare(left : Double, right : Double) -> Int {
  if general_number(left) == general_number(right) {
    0
  } else {
    left.compare(right)
  }
}

///|
fn PivotNumberGroup::validate(
  self : PivotNumberGroup,
) -> Unit raise @failure.Failure {
  guard [self.start, self.end, self.interval].all(value => {
      !value.is_nan() && !value.is_inf()
    }) &&
    self.start < self.end &&
    self.interval > 0 &&
    !(self.end - self.start).is_inf() &&
    ((self.end - self.start) / self.interval).ceil() <= 4094 &&
    !(self.start + self.interval).is_inf() &&
    pivot_group_compare(self.start + self.interval, self.start) > 0 else {
    @failure.reject(
      "invalid-operation", "Invalid or excessive pivot numeric groups",
    )
  }
}

///|
fn PivotNumberGroup::build(
  self : PivotNumberGroup,
  values : Array[Value],
) -> PivotGroupItems raise @failure.Failure {
  self.validate()
  guard values.all(value => value is Number(_) || value == Blank) else {
    @failure.reject(
      "protected-content", "Numeric pivot grouping requires numbers or blanks",
    )
  }
  let integer = [self.start, self.end, self.interval].all(value => {
      value.trunc() == value
    }) &&
    values.all(value => {
      (value is Number(number) && number.trunc() == number) || value == Blank
    })
  let edges = [self.start]
  let items : Array[Value] = [
    Text(
      "<" +
      general_number(self.start) +
      (if values.contains(Blank) { " or (blank)" } else { "" }),
    ),
  ]
  let mut current = self.start
  for ;; {
    let next = current + self.interval
    guard !next.is_inf() &&
      pivot_group_compare(next, current) > 0 &&
      items.length() < 4095 else {
      @failure.reject(
        "limit-exceeded", "Pivot numeric group boundaries exceed budget or precision",
      )
    }
    let last = pivot_group_compare(next, self.end) >= 0
    let correction = if integer && pivot_group_compare(next, self.end) != 0 {
      -1.0
    } else {
      0.0
    }
    items.push(
      Text(general_number(current) + "-" + general_number(next + correction)),
    )
    edges.push(next)
    if last {
      break
    }
    current = next
  }
  items.push(Text(">" + general_number(edges[edges.length() - 1])))
  let indices = values.map(value => {
    guard value is Number(value) else { return 0 }
    if pivot_group_compare(value, self.end) > 0 {
      return items.length() - 1
    }
    let mut low = 0
    let mut high = edges.length()
    while low < high {
      let middle = (low + high) / 2
      if pivot_group_compare(edges[middle], value) <= 0 {
        low = middle + 1
      } else {
        high = middle
      }
    }
    low.min(items.length() - 2)
  })
  { settings: Numeric(self), items, indices, }
}

///|
fn PivotCache::axis_items(self : PivotCache, field : Int) -> Array[Value] {
  self.groups.get(field).map(group => group.items).unwrap_or(self.items[field])
}

///|
fn PivotCache::axis_style(self : PivotCache, field : Int, item : Int) -> Int {
  if self.groups.contains(field) {
    0
  } else {
    self.styles[field][item]
  }
}

///|
fn PivotGroupItems::markup(
  self : PivotGroupItems,
  date1904 : Bool,
  parent? : Int,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  match self.settings {
    Numeric(group) =>
      out <+
        "<fieldGroup base=\"\{group.field}\"><rangePr autoStart=\"0\" autoEnd=\"0\" groupBy=\"range\" startNum=\"\{group.start}\" endNum=\"\{group.end}\" groupInterval=\"\{group.interval}\"/>"
    DateBuckets(group, unit~, start~, end~) =>
      out <+
        "<fieldGroup base=\"\{group.field}\"\{parent.map(value=>" par=\""+value.to_string()+"\"").unwrap_or("")}><rangePr autoStart=\"1\" autoEnd=\"1\" groupBy=\"\{unit}\" startDate=\"\{pivot_date_text(start,date1904)}\" endDate=\"\{pivot_date_text(end,date1904)}\" groupInterval=\"1\"/>"
  }
  out <+ "<groupItems count=\"\{self.items.length()}\">"
  for value in self.items {
    out.write_string(pivot_item_markup(value))
  }
  out <+ "</groupItems></fieldGroup>"
  out.to_string()
}
