///|
fn pivot_plain_source(document : @xml.Document) -> Unit raise @failure.Failure {
  let root = document.nodes()[0]
  let source = document.source()[root.start:root.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Pivot source comments or processing instructions require preservation support",
    )
  }
}

///|
fn Session::pivot_settings(
  self : Session,
  pivot : PivotLocation,
  shared~ : Bool = false,
) -> (PivotSettings, String) raise @failure.Failure {
  let document = self.part_xml(pivot.part)
  pivot_plain_source(document)
  let tree = Tree::new(document)
  let root = tree.root("pivotTableDefinition")
  conditional_node(
    tree,
    root,
    [
      "name", "cacheId", "dataCaption", "rowGrandTotals", "colGrandTotals", "compact",
      "compactData", "outline", "outlineData", "gridDropZones", "createdVersion",
      "updatedVersion", "minRefreshableVersion", "pageWrap", "pageOverThenDown",
    ],
    [
      "location", "pivotFields", "rowFields", "rowItems", "colFields", "colItems",
      "dataFields", "pageFields",
    ],
  )
  if tree.one(root.id, "location") is Some(location) {
    conditional_node(
      tree,
      location,
      ["ref", "firstHeaderRow", "firstDataRow", "firstDataCol"],
      [],
    )
  }
  guard flag(root, "rowGrandTotals", fallback=true) &&
    !flag(root, "compact", fallback=true) &&
    !flag(root, "outline") &&
    pivot.sourceSheet is Some(source_sheet) &&
    pivot.source is Some(source) else {
    @failure.reject(
      "protected-content", "Pivot layout or source requires additional editing support",
    )
  }
  let native_rows = tree
    .one(root.id, "rowFields")
    .map(node => {
      tree
      .all(node.id, "field")
      .map(field => {
        conditional_node(tree, field, ["x"], [])
        natural(field.attribute("x").unwrap_or(""), 79)
      })
    })
    .unwrap_or([])
  let values = tree
    .one(root.id, "dataFields")
    .map(node => {
      tree
      .all(node.id, "dataField")
      .map(field => {
        let mode = pivot_read_value_mode(tree, field)
        PivotValue::{
          field: natural(field.attribute("fld").unwrap_or(""), 63),
          aggregate: field.attribute("subtotal").unwrap_or("sum"),
          showDataAs: mode,
          baseField: field
          .attribute("baseField")
          .map(value => natural(value, 63)),
          baseItem: pivot_read_base_item(
            field,
            Tree::new(self.part_xml(pivot.cache)),
          ),
          name: decode_text(field.attribute("name").unwrap_or("")),
        }
      })
    })
    .unwrap_or([])
  let column_nodes = tree
    .one(root.id, "colFields")
    .map(node => tree.all(node.id, "field"))
    .unwrap_or([])
  let native_columns = column_nodes
    .filter(node => node.attribute("x") != Some("-2"))
    .map(node => natural(node.attribute("x").unwrap_or(""), 79))
  let width = source.right - source.left + 1
  let filters = pivot_read_filters(tree, Tree::new(self.part_xml(pivot.cache))) +
    pivot_read_member_filters(
      tree,
      Tree::new(self.part_xml(pivot.cache)),
      width,
    )
  let (number_groups, date_groups, axes) = pivot_read_groups(
    Tree::new(self.part_xml(pivot.cache)),
    self.date1904,
    width,
    values.map(value => value.name),
  )
  let rows = pivot_source_axis(native_rows, axes, width)
  let columns = pivot_source_axis(native_columns, axes, width)
  let native_subtotals = tree
    .all(tree.one(root.id, "pivotFields").unwrap().id, "pivotField")
    .mapi((index, field) => {
      (index, flag(field, "defaultSubtotal", fallback=true))
    })
    .filter(field => field.1)
    .map(field => field.0)
  let subtotals : Array[Int] = []
  for field in native_subtotals {
    let base = if field < width {
      field
    } else {
      axes
      .iter()
      .find_first(pair => pair.1.contains(field))
      .map(pair => pair.0)
      .unwrap_or(-1)
    }
    guard base >= 0 else {
      @failure.reject(
        "protected-content", "Pivot subtotal field is unavailable",
      )
    }
    if !subtotals.contains(base) {
      subtotals.push(base)
    }
  }
  let settings : PivotSettings = {
    sourceSheet: source_sheet,
    source: source.name(),
    rows,
    columns,
    filters,
    subtotals,
    numberGroups: number_groups,
    dateGroups: date_groups,
    values,
  }
  ignore(settings.validate())
  let hidden = filters.filter(filter => {
    !filter.report && !(rows + columns).contains(filter.field)
  })
  if !hidden.is_empty() {
    let connected = self.affected_slicer_caches([pivot])
    guard hidden.all(filter => {
      connected.any(cache => cache.field == filter.field)
    }) else {
      @failure.reject(
        "protected-content", "Unused pivot member filters require a linked slicer",
      )
    }
  }
  let expanded = pivot_expand_settings(settings, axes)
  guard expanded.subtotals.length() == native_subtotals.length() &&
    expanded.subtotals.all(field => native_subtotals.contains(field)) else {
    @failure.reject(
      "protected-content", "Partial calendar subtotals require support",
    )
  }
  guard tree.one(root.id, "location") is Some(location) &&
    location.attribute("firstHeaderRow") ==
    Some(if columns.is_empty() { "0" } else { "1" }) &&
    location.attribute("firstDataRow") ==
    Some(expanded.header_rows().to_string()) &&
    location.attribute("firstDataCol") == Some(native_rows.length().to_string()) &&
    flag(root, "colGrandTotals", fallback=true) == !columns.is_empty() else {
    @failure.reject(
      "protected-content", "Extended pivot header layout requires support",
    )
  }
  let fields = tree
    .one(root.id, "pivotFields")
    .unwrap_or_error(
      @failure.Failure(
        code="malformed-xlsx",
        message="Missing pivot fields",
        part=pivot.part,
        offset=-1,
      ),
    )
  let field_nodes = tree.all(fields.id, "pivotField")
  guard field_nodes.length() ==
    width +
    date_groups.fold(init=0, (sum, group) => sum + group.units.length() - 1) else {
    @failure.reject(
      "protected-content", "Pivot field count disagrees with source",
    )
  }
  for index, field in field_nodes {
    conditional_node(
      tree,
      field,
      [
        "axis", "dataField", "defaultSubtotal", "showAll", "compact", "outline",
        "multipleItemSelectionAllowed", "subtotalTop",
      ],
      ["items"],
    )
    guard field.attribute("axis") ==
      (if native_rows.contains(index) {
        Some("axisRow")
      } else if native_columns.contains(index) {
        Some("axisCol")
      } else if settings.page_filters().any(filter => filter.field == index) {
        Some("axisPage")
      } else {
        None
      }) &&
      flag(field, "dataField") == values.any(value => value.field == index) &&
      (
        !native_subtotals.contains(index) ||
        !flag(field, "subtotalTop", fallback=true)
      ) &&
      !flag(field, "showAll", fallback=true) &&
      !flag(field, "compact", fallback=true) &&
      !flag(field, "outline", fallback=true) &&
      (
        settings.page_filters().any(filter => filter.field == index) ||
        !flag(field, "multipleItemSelectionAllowed")
      ) else {
      @failure.reject(
        "protected-content", "Pivot field grouping, visibility or subtotal requires support",
      )
    }
    if tree.one(field.id, "items") is Some(items) {
      conditional_node(tree, items, ["count"], ["item"])
      let entries = tree.all(items.id, "item")
      for at, item in entries {
        if item.attribute("t") == Some("default") &&
          native_subtotals.contains(index) &&
          at == entries.length() - 1 {
          conditional_node(tree, item, ["t"], [])
          continue
        }
        conditional_node(tree, item, ["x", "h"], [])
        guard item.attribute("x") == Some(at.to_string()) else {
          @failure.reject(
            "protected-content", "Manual pivot item order requires refresh support",
          )
        }
      }
    }
  }
  for name in ["rowFields", "rowItems", "colFields", "colItems", "dataFields"] {
    if tree.one(root.id, name) is Some(node) {
      conditional_node(
        tree,
        node,
        ["count"],
        if name == "rowFields" || name == "colFields" {
          ["field"]
        } else if name == "dataFields" {
          ["dataField"]
        } else {
          ["i"]
        },
      )
      if name == "rowItems" || name == "colItems" {
        for item in tree.all(node.id, "i") {
          conditional_node(tree, item, ["t", "r", "i"], ["x"])
          if item.attribute("t") == Some("default") {
            let axis = if name == "rowItems" {
              native_rows
            } else {
              native_columns
            }
            guard axis.length() > 1 else {
              @failure.reject(
                "protected-content", "Pivot subtotal axis is unavailable",
              )
            }
            let depth = natural(
              item.attribute("r").unwrap_or(""),
              axis.length() - 2,
            )
            guard native_subtotals.contains(axis[depth]) &&
              tree.all(item.id, "x").length() == 1 else {
              @failure.reject(
                "protected-content", "Pivot subtotal field is inconsistent",
              )
            }
          } else {
            guard [None, Some("data"), Some("grand")].contains(
              item.attribute("t"),
            ) else {
              @failure.reject(
                "protected-content", "Pivot subtotals require layout support",
              )
            }
          }
          for x in tree.all(item.id, "x") {
            conditional_node(tree, x, ["v"], [])
          }
        }
      }
    }
  }
  let expected_columns = native_columns.map(field => field.to_string()) +
    (if values.length() > 1 { ["-2"] } else { [] })
  guard column_nodes.map(node => node.attribute("x").unwrap_or("")) ==
    expected_columns else {
    @failure.reject(
      "protected-content", "Pivot value axis order requires layout support",
    )
  }
  for field in column_nodes {
    conditional_node(tree, field, ["x"], [])
  }
  let links = self.relationships()
  let owners = links.filter(link => {
    link.kind == relationship_uri + "pivotCacheDefinition" &&
    link.owner != self.main &&
    link.target == pivot.cache
  })
  let known = self.pivot_locations()
  guard !owners.is_empty() &&
    (shared || owners.length() == 1) &&
    owners.all(owner => {
      !owner.external &&
      known.any(other => other.part == owner.owner && other.cache == pivot.cache)
    }) &&
    links.filter(link => {
      link.owner == pivot.cache &&
      link.kind == relationship_uri + "pivotCacheRecords"
    })
    is [records] &&
    !records.external else {
    @failure.reject(
      "protected-content", "Shared or external pivot caches require coordinated refresh",
    )
  }
  let cache = self.part_xml(pivot.cache)
  pivot_plain_source(cache)
  let cache_tree = Tree::new(cache)
  let cache_root = cache_tree.root("pivotCacheDefinition")
  guard cache_root.attribute(
      "id",
      uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
    ) ==
    Some(records.id) else {
    @failure.reject(
      "malformed-xlsx", "Pivot record relationship disagrees with cache",
    )
  }
  for node in cache.nodes() {
    let children = match node.name {
      "pivotCacheDefinition" => ["cacheSource", "cacheFields"]
      "cacheSource" => ["worksheetSource"]
      "cacheFields" => ["cacheField"]
      "cacheField" => ["sharedItems", "fieldGroup"]
      "fieldGroup" => ["rangePr", "groupItems"]
      "groupItems" => ["s"]
      "sharedItems" => ["n", "s", "b", "e", "m", "d"]
      _ => []
    }
    if node.id != 0 {
      let attributes = match node.name {
        "cacheSource" => ["type"]
        "worksheetSource" => ["ref", "sheet"]
        "cacheFields" => ["count"]
        "cacheField" => ["name", "databaseField"]
        "fieldGroup" => ["base", "par"]
        "rangePr" =>
          [
            "autoStart", "autoEnd", "groupBy", "startNum", "endNum", "groupInterval",
            "startDate", "endDate",
          ]
        "groupItems" => ["count"]
        "sharedItems" =>
          [
            "count", "containsNumber", "containsString", "containsBlank", "containsNonDate",
            "containsDate", "containsSemiMixedTypes", "containsMixedTypes", "containsInteger",
            "longText",
          ]
        "n" | "s" | "b" | "e" | "d" => ["v"]
        _ => []
      }
      conditional_node(cache_tree, node, attributes, children)
    }
  }
  guard cache_root.attributes.all(attribute => {
      (
        attribute.uri ==
        relationship_uri[:relationship_uri.length() - 1].to_owned() &&
        attribute.name == "id"
      ) ||
      (
        attribute.uri.is_empty() &&
        [
          "recordCount", "saveData", "refreshOnLoad", "enableRefresh", "invalid",
          "createdVersion", "refreshedVersion", "minRefreshableVersion",
        ].contains(attribute.name)
      )
    }) &&
    cache_tree.children
    .get(cache_root.id)
    .unwrap_or([])
    .all(node => {
      node.uri == spreadsheet_uri &&
      ["cacheSource", "cacheFields"].contains(node.name)
    }) &&
    flag(cache_root, "enableRefresh", fallback=true) &&
    flag(cache_root, "saveData", fallback=true) else {
    @failure.reject(
      "protected-content", "Extended pivot cache metadata requires support",
    )
  }
  let data = self.part_xml(records.target)
  pivot_plain_source(data)
  let data_tree = Tree::new(data)
  let data_root = data_tree.root("pivotCacheRecords")
  let cache_fields = cache_tree
    .one(cache_root.id, "cacheFields")
    .map(node => cache_tree.all(node.id, "cacheField"))
    .unwrap_or([])
  guard cache_fields.length() == field_nodes.length() &&
    cache_tree
    .one(cache_root.id, "cacheSource")
    .map(node => node.attribute("type") == Some("worksheet"))
    .unwrap_or(false) else {
    @failure.reject(
      "malformed-xlsx", "Pivot cache source or field count is invalid",
    )
  }
  let counts = cache_fields.map(field => {
    cache_tree
    .one(field.id, "sharedItems")
    .map(node => cache_tree.children.get(node.id).unwrap_or([]).length())
    .unwrap_or(0)
  })
  for index, field in cache_fields {
    if cache_tree.one(field.id, "sharedItems") is Some(items) {
      for node in cache_tree.children.get(items.id).unwrap_or([]) {
        if node.name == "d" {
          guard date_groups.any(group => group.field == index) else {
            @failure.reject(
              "protected-content", "Ungrouped native date cache requires support",
            )
          }
          ignore(pivot_date_cache_value(node, self.date1904))
        }
      }
    }
  }
  let cache_rows = data_tree.all(data_root.id, "r")
  guard natural(data_root.attribute("count").unwrap_or("0"), 65536) ==
    cache_rows.length() &&
    natural(cache_root.attribute("recordCount").unwrap_or("0"), 65536) ==
    cache_rows.length() else {
    @failure.reject(
      "malformed-xlsx", "Pivot cache record count is inconsistent",
    )
  }
  for row in cache_rows {
    let values = data_tree.children.get(row.id).unwrap_or([])
    guard values.length() == width else {
      @failure.reject(
        "malformed-xlsx", "Pivot cache record width is inconsistent",
      )
    }
    for field, item in values {
      if item.name == "x" {
        guard counts[field] > 0 &&
          natural(item.attribute("v").unwrap_or(""), 65535) < counts[field] else {
          @failure.reject(
            "malformed-xlsx", "Pivot cache record index is invalid",
          )
        }
      }
    }
  }
  for node in data.nodes() {
    conditional_node(
      data_tree,
      node,
      if node.name == "pivotCacheRecords" {
        ["count"]
      } else if node.name == "r" || node.name == "m" {
        []
      } else {
        ["v"]
      },
      if node.name == "pivotCacheRecords" {
        ["r"]
      } else if node.name == "r" {
        ["x", "n", "s", "b", "e", "m"]
      } else {
        []
      },
    )
  }
  (settings, records.target)
}

///|
/// Refreshes a supported native row pivot atomically; expansion never overwrites existing content.
pub fn Session::refresh_pivot(
  self : Session,
  revision : Int,
  sheet : String,
  part : String,
) -> Json raise @failure.Failure {
  self.write_pivot(revision, sheet, part, None)
}

///|
/// Replaces the supported source and row/value fields using the same atomic refresh transaction.
pub fn Session::update_pivot(
  self : Session,
  revision : Int,
  sheet : String,
  part : String,
  settings : PivotSettings,
) -> Json raise @failure.Failure {
  self.write_pivot(revision, sheet, part, Some(settings))
}

///|
fn Session::write_pivot(
  self : Session,
  revision : Int,
  sheet : String,
  part : String,
  replacement : PivotSettings?,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.protect_slicer_cache(sheet, part)
  if replacement is Some(settings) {
    guard !settings.filters.any(filter => {
      !filter.report &&
      filter.values is Some(_) &&
      !(settings.rows + settings.columns).contains(filter.field)
    }) else {
      @failure.reject(
        "protected-content", "Unused pivot member filters require a linked slicer",
      )
    }
  }
  if self.prepare_pivot(revision, sheet, part, replacement)
    is Some((plan, range)) {
    self.commit(
      plan.sheets,
      self.workbook,
      plan.calculation,
      plan.edits,
      (sheet, range),
      parts=plan.parts,
      created_parts=plan.created_parts,
      pivot_edits=[part],
    )
  }
  self.pivots(self.revision, sheet)
}

///|
fn Session::prepare_pivot(
  self : Session,
  revision : Int,
  sheet : String,
  part : String,
  replacement : PivotSettings?,
  cached~ : PivotCache? = None,
) -> (CellEditPlan, Range)? raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard !current.locked && current.state == "visible" else {
    @failure.reject(
      "protected-content", "Pivot destination is protected or hidden",
    )
  }
  let pivots = self.pivot_locations()
  guard pivots
    .iter()
    .find_first(pivot => pivot.sheet == sheet && pivot.part == part)
    is Some(pivot) else {
    @failure.reject(
      "invalid-operation", "Pivot is outside the selected worksheet",
    )
  }
  guard (pivot.range.bottom - pivot.range.top + 1).to_int64() *
    (pivot.range.right - pivot.range.left + 1).to_int64() <=
    32768 else {
    @failure.reject(
      "limit-exceeded", "Pivot refresh location exceeds output budget",
    )
  }
  let (original_settings, records) = self.pivot_settings(
    pivot,
    shared=cached is Some(_),
  )
  let settings = replacement.unwrap_or(original_settings)
  let cache = match cached {
    Some(cache) => cache
    None => self.pivot_cache(settings)
  }
  let layout = cache.layout(settings)
  let range = layout.bounds({ row: pivot.range.top, column: pivot.range.left, })
  guard !(settings.sourceSheet == sheet &&
    (
      settings.validate().intersects(range) ||
      settings.validate().intersects(pivot.range)
    )) &&
    !current.merges.any(merge => merge.intersects(range)) &&
    !pivots.any(other => {
      other.part != part &&
      other.sheet == sheet &&
      other.range.intersects(range)
    }) &&
    !self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .any(table => table.sheet == sheet && table.range.intersects(range)) else {
    @failure.reject(
      "protected-content", "Pivot expansion overlaps source or a structured range",
    )
  }
  let tree = Tree::new(self.part_xml(pivot.cache))
  let original_fields = tree
    .one(0, "cacheFields")
    .map(node => {
      tree
      .all(node.id, "cacheField")
      .map(node => decode_text(node.attribute("name").unwrap_or("")))
    })
    .unwrap_or([])
  guard replacement is Some(_) || original_fields == cache.headers else {
    @failure.reject(
      "protected-content", "Pivot source headers changed; field remapping is required",
    )
  }
  for cell in current.cells.values() {
    if range.contains(cell.address) && !pivot.range.contains(cell.address) {
      guard cell.value == Blank &&
        cell.formula is None &&
        cell.read_only.is_empty() else {
        @failure.reject(
          "protected-content", "Pivot expansion requires empty cells",
        )
      }
    }
  }
  let notes = self.read_sheet_notes(current)
  guard !notes
    .map(notes => {
      notes.entries.any(note => {
        range.contains(note.address) && !pivot.range.contains(note.address)
      })
    })
    .unwrap_or(false) else {
    @failure.reject("protected-content", "Pivot expansion contains notes")
  }
  for link in hyperlink_nodes(Tree::new(current.document)) {
    let bounds = Range::parse(link.attribute("ref").unwrap_or(""))
    guard !bounds.intersects(range) ||
      (
        bounds.left.max(range.left) >= pivot.range.left &&
        bounds.right.min(range.right) <= pivot.range.right &&
        bounds.top.max(range.top) >= pivot.range.top &&
        bounds.bottom.min(range.bottom) <= pivot.range.bottom
      ) else {
      @failure.reject(
        "protected-content", "Pivot expansion contains hyperlinks",
      )
    }
  }
  let links = self.relationships()
  let record_link = links
    .iter()
    .find_first(link => link.owner == pivot.cache && link.target == records)
    .unwrap().id
  let pivot_root = self.part_xml(part).nodes()[0]
  let cache_id = natural(
    pivot_root.attribute("cacheId").unwrap_or(""),
    2147483647,
  )
  let sources = [
    (
      part,
      layout.definition(
        pivot.name,
        cache_id,
        range,
        data_caption=pivot_root.attribute("dataCaption").unwrap_or("Values"),
      ),
    ),
  ]
  if cached is None {
    sources.append([
      (
        pivot.cache,
        cache.definition(
          self.sheets[self.sheet_index(settings.sourceSheet)].name,
          settings.validate().name(),
          record_link,
        ),
      ),
      (records, cache.record_markup()),
    ])
  }
  let (updates, styles) = layout.cells(
    range,
    self.styles,
    self.date1904,
    data_caption=pivot_root.attribute("dataCaption").unwrap_or("Values"),
  )
  for row in pivot.range.top..<=pivot.range.bottom {
    for column in pivot.range.left..<=pivot.range.right {
      let address : Address = { row, column, }
      if !range.contains(address) {
        updates[address.name()] = {
          value: Blank,
          formula: None,
          keep_shared: false,
        }
      }
    }
  }
  for key in styles.keys().to_array() {
    if pivot.range.contains(Address::parse(key)) {
      ignore(styles.remove(key))
    }
  }
  let unchanged = sources.all(pair => self.part_xml(pair.0).source() == pair.1) &&
    updates
    .iter()
    .all(pair => {
      current.cells
      .get(pair.0)
      .map(cell => cell.value == pair.1.value && cell.formula is None)
      .unwrap_or(pair.1.value == Blank)
    })
  if unchanged {
    return None
  }
  let old_tree = Tree::new(self.part_xml(part))
  let location = old_tree.one(0, "location").unwrap()
  let old_body = Range::parse(location.attribute("ref").unwrap())
  let formatting = self.pivot_formats(
    layout,
    range,
    current,
    styles,
    previous=Some(
      (
        pivot.range,
        old_body.top +
        natural(location.attribute("firstDataRow").unwrap(), 32768),
        old_body.left + natural(location.attribute("firstDataCol").unwrap(), 64),
        original_settings.values,
      ),
    ),
  )
  let plan = self.prepare_cells(
    Map([(index, updates)]),
    styles=Map([(index, styles)]),
    formatting~,
  )
  let parts = plan.parts
  let edits = plan.edits
  for (path, markup) in sources {
    let original = self.part_xml(path)
    if original.source() != markup {
      let (document, edit) = pivot_root_edit(original, markup)
      parts[path] = document
      edits.push((path, edit))
    }
  }
  Some((plan, range))
}
