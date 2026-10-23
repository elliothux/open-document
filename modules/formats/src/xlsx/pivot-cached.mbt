///|
// Filtering keeps native cache indices and pending source edits until explicit refresh.
fn Session::cached_pivot(
  self : Session,
  pivot : PivotLocation,
  settings : PivotSettings,
  records : String,
) -> PivotCache raise @failure.Failure {
  let range = settings.validate()
  let width = range.right - range.left + 1
  let tree = Tree::new(self.part_xml(pivot.cache))
  let fields = tree.all(tree.one(0, "cacheFields").unwrap().id, "cacheField")
  let headers = fields.map(field => {
    decode_text(field.attribute("name").unwrap_or(""))
  })
  let items : Array[Array[Value]] = []
  let styles : Array[Array[Int]] = []
  let maps : Array[Map[String, Int]] = []
  let source = self.sheets[self.sheet_index(settings.sourceSheet)]
  let mut units = 0
  for index, field in fields {
    let entries = tree
      .one(field.id, "sharedItems")
      .map(node => tree.children.get(node.id).unwrap_or([]))
      .unwrap_or([])
    guard entries.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Pivot cached members exceed budget")
    }
    let values = entries.map(node => {
      if node.name == "d" {
        pivot_date_cache_value(node, self.date1904)
      } else {
        pivot_cache_value(node)
      }
    })
    let lookup : Map[String, Int] = Map([])
    for offset, value in values {
      let key = pivot_item_key(value)
      units += key.length()
      guard units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Pivot cached member text exceeds budget",
        )
      }
      guard !lookup.contains(key) else {
        @failure.reject(
          "protected-content", "Pivot cached members are ambiguous or exceed budget",
        )
      }
      lookup[key] = offset
    }
    let formats = values.map(_ => 0)
    let formatted : Map[Int, Bool] = Map([])
    if index < width {
      for row in (range.top + 1)..<=range.bottom {
        let address : Address = { row, column: range.left + index, }
        if source.cells.get(address.name()) is Some(cell) &&
          lookup.get(pivot_item_key(cell.value)) is Some(at) &&
          !formatted.contains(at) {
          formats[at] = source.style_at(address)
          formatted[at] = true
        }
      }
    }
    items.push(values)
    styles.push(formats)
    maps.push(lookup)
  }
  let data = Tree::new(self.part_xml(records))
  let rows = data.all(0, "r")
  guard rows.length().to_int64() * width.to_int64() <= 65536 else {
    @failure.reject("limit-exceeded", "Pivot cached records exceed budget")
  }
  let records = rows.map(row => {
    data.children
    .get(row.id)
    .unwrap_or([])
    .mapi((field, node) => {
      if node.name == "x" {
        natural(node.attribute("v").unwrap_or(""), items[field].length() - 1)
      } else {
        let value = pivot_cache_value(node)
        let key = pivot_item_key(value)
        match maps[field].get(key) {
          Some(at) => at
          None => {
            units += key.length()
            guard items[field].length() < 4096 && units <= 1048576 else {
              @failure.reject(
                "limit-exceeded", "Pivot cached records exceed member budget",
              )
            }
            let at = items[field].length()
            items[field].push(value)
            styles[field].push(0)
            maps[field][key] = at
            at
          }
        }
      }
    })
  })
  let (_, _, axes) = pivot_read_groups(
    tree,
    self.date1904,
    width,
    settings.values.map(value => value.name),
  )
  let groups : Map[Int, PivotGroupItems] = Map([])
  for group in settings.numberGroups {
    groups[group.field] = group.build(items[group.field])
  }
  for group in settings.dateGroups {
    let indices = axes[group.field]
    for offset, unit in group.units {
      groups[indices[offset]] = group.build(
        items[group.field],
        self.date1904,
        unit~,
      )
    }
  }
  {
    headers,
    items,
    styles,
    records,
    groups,
    axes,
    source_width: width,
    date1904: self.date1904,
  }
}
