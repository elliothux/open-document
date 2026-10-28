///|
fn filter_date_parts(group : String) -> Array[Int32] raise @failure.Failure {
  let count = match group.length() {
    4 => 1
    7 => 2
    10 => 3
    13 => 4
    16 => 5
    19 => 6
    _ =>
      @failure.reject(
        "invalid-operation", "Invalid date filter group precision",
      )
  }
  let offsets = [0, 5, 8, 11, 14, 17]
  let separators = ["-", "-", "T", ":", ":"]
  let parts : Array[Int32] = []
  for i in 0..<count {
    let start = offsets[i]
    let length = if i == 0 { 4 } else { 2 }
    let text = group[start:start + length].to_owned()
    let number = natural(text, 9999)
    guard padded(number, length) == text &&
      (i == 0 || group[start - 1:start] == separators[i - 1]) else {
      @failure.reject(
        "invalid-operation", "Date filter groups require canonical calendar prefixes",
      )
    }
    parts.push(number)
  }
  guard parts[0] >= 1 &&
    (count < 2 || (parts[1] >= 1 && parts[1] <= 12)) &&
    (
      count < 3 ||
      (
        parts[2] >= 1 &&
        parts[2] <=
        (if parts[0] == 1900 && parts[1] == 2 {
          29
        } else {
          calendar_months(parts[0])[parts[1] - 1]
        })
      )
    ) &&
    (count < 4 || parts[3] <= 23) &&
    (count < 5 || parts[4] <= 59) &&
    (count < 6 || parts[5] <= 59) else {
    @failure.reject(
      "invalid-operation", "Invalid date filter calendar components",
    )
  }
  parts
}

///|
fn filter_date_interval(
  group : String,
  date1904 : Bool,
) -> (Double, Double) raise @failure.Failure {
  let p = filter_date_parts(group)
  let year = p[0]
  let month = p.get(1).unwrap_or(1)
  let day = p.get(2).unwrap_or(1)
  let serial = date_serial(year, month, day, date1904).to_double()
  if p.length() == 1 {
    return (serial, date_serial(year + 1, 1, 1, date1904).to_double())
  }
  if p.length() == 2 {
    return (serial, date_serial(year, month + 1, 1, date1904).to_double())
  }
  if p.length() == 3 {
    return (serial, serial + 1)
  }
  let seconds = p[3] * 3600 + p.get(4).unwrap_or(0) * 60 + p.get(5).unwrap_or(0)
  let width = if p.length() == 4 {
    3600
  } else if p.length() == 5 {
    60
  } else {
    1
  }
  (
    serial + seconds.to_double() / 86400,
    serial + (seconds + width).to_double() / 86400,
  )
}

///|
fn filter_date_markup(group : String) -> String raise @failure.Failure {
  let p = filter_date_parts(group)
  let fields = ["year", "month", "day", "hour", "minute", "second"]
  let attributes = p.mapi((i, value) => " \{fields[i]}=\"\{value}\"").join("")
  "<od:dateGroupItem dateTimeGrouping=\"\{fields[p.length() - 1]}\"\{attributes}/>"
}

///|
fn read_filter_date(
  tree : Tree,
  node : @xml.Node,
) -> String raise @failure.Failure {
  try {
    let fields = ["year", "month", "day", "hour", "minute", "second"]
    let grouping = node.attribute("dateTimeGrouping").unwrap_or("")
    let mut count = 0
    for i, field in fields {
      if field == grouping {
        count = i + 1
      }
    }
    guard count > 0 && tree.children.get(node.id).unwrap_or([]).is_empty() else {
      @failure.reject("protected-content", "Unknown date filter group")
    }
    let names = fields[:count].to_owned()
    filter_attributes(node, ["dateTimeGrouping", ..names])
    let values = names.mapi((i, name) => {
      padded(
        natural(node.attribute(name).unwrap_or(""), 9999),
        if i == 0 {
          4
        } else {
          2
        },
      )
    })
    let out = StringBuilder()
    for i, value in values {
      if i > 0 {
        out.write_string(["-", "-", "T", ":", ":"][i - 1])
      }
      out.write_string(value)
    }
    let group = out.to_string()
    ignore(filter_date_parts(group))
    group
  } catch {
    @failure.Failure(message~, ..) =>
      @failure.reject("protected-content", message)
  }
}

///|
fn prepare_date_filter(
  groups : Array[String],
  labels : Array[String],
  blank : Bool,
  work : FormulaWork,
) -> PreparedFilter raise @failure.Failure {
  work.spend(amount=groups.length() * 13)
  let ordered = groups.map(group => filter_date_interval(group, work.date1904))
  ordered.sort_by((a, b) => {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let intervals : Array[(Double, Double)] = []
  for interval in ordered {
    if intervals.last() is Some(previous) && previous.1 >= interval.0 {
      intervals[intervals.length() - 1] = (
        previous.0,
        previous.1.max(interval.1),
      )
    } else {
      intervals.push(interval)
    }
  }
  let values : Map[String, Bool] = Map([])
  for label in labels {
    values[filter_normalized(label, work)] = true
  }
  DateLabels(intervals, values, blank~)
}

///|
fn filter_date_matches(
  intervals : Array[(Double, Double)],
  value : Double,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  if value < 0 || value >= (if work.date1904 { 2957004 } else { 2958466 }) {
    return false
  }
  let mut start = 0
  let mut end = intervals.length()
  while start < end {
    work.spend(amount=1)
    let middle = start + (end - start) / 2
    let interval = intervals[middle]
    if value < interval.0 {
      end = middle
    } else if value >= interval.1 {
      start = middle + 1
    } else {
      return true
    }
  }
  false
}
