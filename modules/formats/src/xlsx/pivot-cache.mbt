///|
pub(all) struct PivotValue {
  field : Int
  aggregate : String
  name : String
} derive(ToJson)

///|
pub extend PivotValue with ToJson::{to_json}

///|
pub(all) struct PivotSettings {
  sourceSheet : String
  source : String
  rows : Array[Int]
  columns : Array[Int]
  filters : Array[PivotFilter]
  values : Array[PivotValue]
} derive(ToJson)

///|
pub extend PivotSettings with ToJson::{to_json}

///|
priv struct PivotCache {
  headers : Array[String]
  items : Array[Array[Value]]
  styles : Array[Array[Int]]
  records : Array[Array[Int]]
}

///|
let pivot_aggregates : ReadOnlyArray[String] = [
  "sum", "count", "countNums", "average", "min", "max", "product", "stdDev", "stdDevp",
  "var", "varp",
]

///|
fn PivotSettings::validate(
  self : PivotSettings,
) -> Range raise @failure.Failure {
  let source = Range::parse(self.source)
  let width = source.right - source.left + 1
  guard source.bottom > source.top &&
    width <= 64 &&
    (source.bottom - source.top).to_int64() * width.to_int64() <= 65536 &&
    self.rows.length() > 0 &&
    self.rows.length() <= 8 &&
    self.columns.length() <= 8 &&
    self.filters.length() <= 8 &&
    self.values.length() > 0 &&
    self.values.length() <= 8 else {
    @failure.reject(
      "limit-exceeded", "Pivot source or field count exceeds budget",
    )
  }
  let seen : Map[Int, Bool] = Map([])
  for
    field in self.rows + self.columns + self.filters.map(filter => filter.field) {
    guard field >= 0 && field < width && !seen.contains(field) else {
      @failure.reject(
        "invalid-operation", "Invalid or duplicate pivot axis field",
      )
    }
    seen[field] = true
  }
  let captions : Map[String, Bool] = Map([])
  let mut units = 0
  for filter in self.filters {
    if filter.values is Some(values) {
      guard !values.is_empty() && values.length() <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Pivot report selection exceeds budget",
        )
      }
      let seen : Map[String, Bool] = Map([])
      for value in values {
        pivot_filter_value(value)
        let key = pivot_item_key(value)
        units += key.length()
        guard units <= 1048576 && !seen.contains(key) else {
          @failure.reject(
            "invalid-operation", "Duplicate or excessive pivot report values",
          )
        }
        seen[key] = true
      }
    }
  }
  for value in self.values {
    guard value.field >= 0 &&
      value.field < width &&
      pivot_aggregates.contains(value.aggregate) &&
      !value.name.trim().is_empty() &&
      value.name.length() <= 255 &&
      @xml.valid_text(value.name) &&
      !captions.contains(value.name.to_lower()) else {
      @failure.reject(
        "invalid-operation", "Invalid pivot value field or caption",
      )
    }
    captions[value.name.to_lower()] = true
  }
  source
}

///|
fn pivot_item_key(value : Value) -> String {
  (match value {
    Text(text) => Text(text.to_lower())
    Number(number) if number == 0 => Number(0)
    value => value
  })
  .to_json()
  .stringify()
}

///|
fn Session::pivot_cache(
  self : Session,
  settings : PivotSettings,
) -> PivotCache raise @failure.Failure {
  let range = settings.validate()
  let index = self.sheet_index(settings.sourceSheet)
  let sheet = self.sheets[index]
  guard self.read_only.is_empty() && !sheet.merges.any(r => r.intersects(range)) else {
    @failure.reject(
      "protected-content", "Pivot source contains protected calculation or merged cells",
    )
  }
  let calculation = self.calculation.unwrap()
  let headers : Array[String] = []
  let items : Array[Array[Value]] = []
  let styles : Array[Array[Int]] = []
  let maps : Array[Map[String, Int]] = []
  let records : Array[Array[Int]] = []
  let mut units = 0
  for row in range.top..<=range.bottom {
    let record : Array[Int] = []
    for column in range.left..<=range.right {
      let offset = column - range.left
      let key = Address::{ row, column, }.name()
      let cell = sheet.cells.get(key)
      guard cell
        .map(cell => {
          cell.calculation_supported &&
          (
            cell.formula is None ||
            calculation.expressions.contains((index, key))
          )
        })
        .unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Pivot source requires current supported formula values",
        )
      }
      let value = match
        calculation.values
        .get((index, key))
        .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank)) {
        Text("") => Blank
        value => value
      }
      if row == range.top {
        let label = formatted(
          value,
          self.styles[sheet.style_at({ row, column, })].format,
          self.date1904,
        )
        guard !label.trim().is_empty() &&
          label.length() <= 255 &&
          @xml.valid_text(label) &&
          !(value is Error(_)) else {
          @failure.reject(
            "invalid-operation", "Pivot fields require nonempty source headers",
          )
        }
        let mut name = label
        let mut suffix = 2
        while headers.contains(name) {
          name = label + suffix.to_string()
          suffix += 1
        }
        guard name.length() <= 255 else {
          @failure.reject("limit-exceeded", "Pivot field name exceeds budget")
        }
        headers.push(name)
        items.push([])
        styles.push([])
        maps.push(Map([]))
        continue
      }
      let identity = pivot_item_key(value)
      let item = match maps[offset].get(identity) {
        Some(item) => item
        None => {
          units += identity.length()
          guard units <= 1048576 else {
            @failure.reject(
              "limit-exceeded", "Pivot shared item text exceeds budget",
            )
          }
          let item = items[offset].length()
          items[offset].push(value)
          styles[offset].push(sheet.style_at({ row, column, }))
          maps[offset][identity] = item
          item
        }
      }
      record.push(item)
    }
    if row != range.top {
      records.push(record)
    }
  }
  let empty = fn(record : Array[Int]) {
    record
    .mapi((index, item) => items[index][item] == Blank)
    .all(value => value)
  }
  while records.length() > 1 &&
        empty(records[records.length() - 1]) &&
        empty(records[records.length() - 2]) {
    ignore(records.pop())
  }
  guard !settings.values.any(value => {
    headers.any(header => header.to_lower() == value.name.to_lower())
  }) else {
    @failure.reject(
      "invalid-operation", "Pivot value captions must differ from source field names",
    )
  }
  for filter in settings.filters {
    if filter.values is Some(values) {
      for value in values {
        let key = pivot_item_key(value)
        if !maps[filter.field].contains(key) {
          units += key.length()
          guard units <= 1048576 else {
            @failure.reject(
              "limit-exceeded", "Pivot shared item text exceeds budget",
            )
          }
          maps[filter.field][key] = items[filter.field].length()
          items[filter.field].push(value)
          styles[filter.field].push(0)
        }
      }
    }
    guard items[filter.field].length() <= 4096 else {
      @failure.reject("limit-exceeded", "Pivot report items exceed budget")
    }
  }
  { headers, items, styles, records, }
}

///|
priv struct PivotStatistic {
  mut count : Int
  mut numbers : Int
  mut sum : Double
  mut product : Double
  mut mean : Double
  mut squared : Double
  mut minimum : Double
  mut maximum : Double
  mut error : String?
}

///|
fn PivotStatistic::new() -> PivotStatistic {
  {
    count: 0,
    numbers: 0,
    sum: 0,
    product: 1,
    mean: 0,
    squared: 0,
    minimum: 0,
    maximum: 0,
    error: None,
  }
}

///|
fn PivotStatistic::add(self : PivotStatistic, value : Value) -> Unit {
  match value {
    Blank => ()
    Number(number) => {
      self.count += 1
      self.numbers += 1
      self.sum += number
      self.product *= number
      let delta = number - self.mean
      self.mean += delta / self.numbers.to_double()
      self.squared += delta * (number - self.mean)
      self.minimum = if self.numbers == 1 {
        number
      } else {
        self.minimum.min(number)
      }
      self.maximum = if self.numbers == 1 {
        number
      } else {
        self.maximum.max(number)
      }
    }
    Error(error) => {
      self.count += 1
      self.error = Some(error)
    }
    _ => self.count += 1
  }
}

///|
fn PivotStatistic::value(self : PivotStatistic, aggregate : String) -> Value {
  if self.count == 0 {
    return Blank
  }
  if aggregate == "count" {
    return Number(self.count.to_double())
  }
  if aggregate == "countNums" {
    return Number(self.numbers.to_double())
  }
  if self.error is Some(error) {
    return Error(error)
  }
  let sample = aggregate == "var" || aggregate == "stdDev"
  if (aggregate == "average" && self.numbers == 0) ||
    (
      ["var", "varp", "stdDev", "stdDevp"].contains(aggregate) &&
      self.numbers < (if sample { 2 } else { 1 })
    ) {
    return Error("#DIV/0!")
  }
  let value = match aggregate {
    "sum" => self.sum
    "average" => self.mean
    "min" => self.minimum
    "max" => self.maximum
    "product" => if self.numbers == 0 { 0 } else { self.product }
    _ => {
      let variance = self.squared.max(0) /
        (self.numbers - (if sample { 1 } else { 0 })).to_double()
      if aggregate == "stdDev" || aggregate == "stdDevp" {
        variance.sqrt()
      } else {
        variance
      }
    }
  }
  finite_result(value)
}

///|
/// Returns typed grouped values without changing cells, source or history.
pub fn Session::pivot_preview(
  self : Session,
  revision : Int,
  settings : PivotSettings,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let layout = self.pivot_cache(settings).layout(settings)
  let preview : Json = {
    "revision": revision,
    "settings": settings,
    "fields": layout.cache.headers,
    "recordCount": layout.cache.records.length(),
    "filteredCount": layout.filtered_count,
    "filterItems": settings.filters.map(filter => {
      layout.cache.items[filter.field].mapi((at, value) => {
        let item : Json = {
          "value": value,
          "label": if value == Blank {
            "(blank)"
          } else {
            formatted(
              value,
              self.styles[layout.cache.styles[filter.field][at]].format,
              self.date1904,
            )
          },
        }
        item
      })
    }),
    "groups": layout.members.length(),
    "truncated": layout.members.length() > 20,
    "columnMembers": (if settings.columns.is_empty() {
      []
    } else {
      layout.columns
    }).map(members => {
      let column : Json = {
        "members": members.mapi((at, item) => {
          layout.cache.items[settings.columns[at]][item]
        }),
        "formats": members.mapi((at, item) => {
          self.styles[layout.cache.styles[settings.columns[at]][item]].format
        }),
      }
      column
    }),
    "columnTotals": layout.column_totals,
    "rows": layout.members[:layout.members.length().min(20)]
    .to_owned()
    .mapi((index, members) => {
      let row : Json = {
        "members": members.mapi((at, item) => {
          layout.cache.items[settings.rows[at]][item]
        }),
        "formats": members.mapi((at, item) => {
          self.styles[layout.cache.styles[settings.rows[at]][item]].format
        }),
        "values": layout.values[index],
        "total": layout.row_totals[index],
      }
      row
    }),
    "total": layout.total,
  }
  guard preview.stringify().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Pivot preview exceeds text budget")
  }
  preview
}
