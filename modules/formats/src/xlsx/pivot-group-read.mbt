///|
fn pivot_date_field_name(unit : String, names : Array[String]) -> String {
  let base = match unit {
    "years" => "Years"
    "quarters" => "Quarters"
    "months" => "Months"
    _ => "Days"
  }
  pivot_field_name(base, names)
}

///|
fn pivot_field_name(base : String, names : Array[String]) -> String {
  let mut name = base
  let mut suffix = 2
  while names.any(item => item.to_lower() == name.to_lower()) {
    name = base + suffix.to_string()
    suffix += 1
  }
  names.push(name)
  name
}

///|
fn pivot_read_groups(
  cache : Tree,
  date1904 : Bool,
  width : Int32,
  captions : Array[String],
) -> (Array[PivotNumberGroup], Array[PivotDateGroup], Map[Int32, Array[Int32]]) raise @failure.Failure {
  let fields = cache.all(cache.one(0, "cacheFields").unwrap().id, "cacheField")
  guard fields.length() >= width && fields.length() <= 80 else {
    @failure.reject(
      "protected-content", "Pivot cache field dimensions require support",
    )
  }
  let numbers : Array[PivotNumberGroup] = []
  let components : Map[Int32, Array[(String, Int32)]] = Map([])
  let mut count = 0
  for index, field in fields {
    let derived = index >= width
    guard flag(field, "databaseField", fallback=true) != derived else {
      @failure.reject(
        "protected-content", "Pivot derived field ownership is inconsistent",
      )
    }
    let group = cache.one(field.id, "fieldGroup")
    guard !derived ||
      (group is Some(_) && cache.one(field.id, "sharedItems") is None) else {
      @failure.reject(
        "protected-content", "Pivot derived fields require calendar groups",
      )
    }
    if group is Some(node) {
      count += 1
      guard count <= 16 else {
        @failure.reject("limit-exceeded", "Pivot group fields exceed budget")
      }
      conditional_node(cache, node, ["base", "par"], ["rangePr", "groupItems"])
      let base = natural(node.attribute("base").unwrap_or(""), width - 1)
      guard (derived || base == index) &&
        cache.one(node.id, "rangePr") is Some(range) &&
        cache.one(node.id, "groupItems") is Some(items) &&
        cache.one(fields[base].id, "sharedItems") is Some(shared) else {
        @failure.reject("protected-content", "Pivot group base is unavailable")
      }
      conditional_node(cache, items, ["count"], ["s"])
      let unit = range.attribute("groupBy").unwrap_or("range")
      let expected = if unit == "range" {
        guard !derived && node.attribute("par") is None else {
          @failure.reject(
            "protected-content", "Derived numeric pivot groups require support",
          )
        }
        conditional_node(
          cache,
          range,
          [
            "autoStart", "autoEnd", "groupBy", "startNum", "endNum", "groupInterval",
          ],
          [],
        )
        let start = number(range.attribute("startNum").unwrap_or(""))
        let end = number(range.attribute("endNum").unwrap_or(""))
        let group : PivotNumberGroup = {
          field: base,
          start: if flag(range, "autoStart", fallback=true) {
            None
          } else {
            Some(start)
          },
          end: if flag(range, "autoEnd", fallback=true) {
            None
          } else {
            Some(end)
          },
          interval: number(range.attribute("groupInterval").unwrap_or("1")),
        }
        let built = group.build(
          cache.children.get(shared.id).unwrap_or([]).map(pivot_cache_value),
        )
        guard built.settings is Numeric(_, start=actual_start, end=actual_end) &&
          pivot_group_compare(start, actual_start) == 0 &&
          pivot_group_compare(end, actual_end) == 0 else {
          @failure.reject(
            "protected-content", "Pivot automatic numeric bounds disagree with source cache",
          )
        }
        numbers.push(group)
        built
      } else {
        guard !derived || node.attribute("par") is None else {
          @failure.reject(
            "protected-content", "Chained derived pivot fields require support",
          )
        }
        conditional_node(
          cache,
          range,
          [
            "autoStart", "autoEnd", "groupBy", "startDate", "endDate", "groupInterval",
          ],
          [],
        )
        let group : PivotDateGroup = { field: base, units: [unit], }
        let built = group.build(
          cache.children
          .get(shared.id)
          .unwrap_or([])
          .map(node => pivot_date_cache_value(node, date1904)),
          date1904,
        )
        guard flag(range, "autoStart", fallback=true) &&
          flag(range, "autoEnd", fallback=true) &&
          range.attribute("groupInterval").unwrap_or("1") == "1" &&
          built.settings is DateBuckets(_, start~, end~, ..) &&
          pivot_group_compare(
            pivot_date_parse(
              range.attribute("startDate").unwrap_or(""),
              date1904,
            ),
            start,
          ) ==
          0 &&
          pivot_group_compare(
            pivot_date_parse(range.attribute("endDate").unwrap_or(""), date1904),
            end,
          ) ==
          0 else {
          @failure.reject(
            "protected-content", "Pivot calendar bounds require support",
          )
        }
        let entries = components.get_or_init(base, () => [])
        guard !entries.any(entry => entry.0 == unit) else {
          @failure.reject(
            "protected-content", "Duplicate pivot calendar components",
          )
        }
        entries.push((unit, index))
        built
      }
      guard cache.children.get(items.id).unwrap_or([]).map(pivot_cache_value) ==
        expected.items &&
        natural(items.attribute("count").unwrap_or(""), 4096) ==
        expected.items.length() else {
        @failure.reject(
          "protected-content", "Manual pivot group labels require support",
        )
      }
    }
  }
  let dates : Array[PivotDateGroup] = []
  let axes : Map[Int32, Array[Int32]] = Map([])
  let names = fields[:width].map(field => {
      decode_text(field.attribute("name").unwrap_or(""))
    }) +
    captions
  let mut next = width
  for base in 0..<width {
    if components.get(base) is Some(entries) {
      entries.sort_by((a, b) => {
        pivot_date_units
        .search_by(unit => unit == a.0)
        .unwrap()
        .compare(pivot_date_units.search_by(unit => unit == b.0).unwrap())
      })
      guard entries[entries.length() - 1].1 == base else {
        @failure.reject(
          "protected-content", "Pivot finest calendar field must retain its source identity",
        )
      }
      for offset in 0..<(entries.length() - 1) {
        let entry = entries[entries.length() - 2 - offset]
        guard entry.1 == next &&
          decode_text(fields[next].attribute("name").unwrap_or("")) ==
          pivot_date_field_name(entry.0, names) else {
          @failure.reject(
            "protected-content", "Pivot derived field order or caption requires support",
          )
        }
        next += 1
      }
      let parent = if entries.length() > 1 {
        Some(entries[0].1.to_string())
      } else {
        None
      }
      guard cache.one(fields[base].id, "fieldGroup").unwrap().attribute("par") ==
        parent else {
        @failure.reject(
          "protected-content", "Pivot calendar parent is inconsistent",
        )
      }
      dates.push({ field: base, units: entries.map(entry => entry.0), })
      axes[base] = entries.map(entry => entry.1)
    }
  }
  guard next == fields.length() else {
    @failure.reject("protected-content", "Unowned pivot derived fields")
  }
  (numbers, dates, axes)
}
