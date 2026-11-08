///|
/// Refreshes a supported native row pivot atomically; expansion never overwrites existing content.
pub fn Session::refresh_pivot(
  self : Session,
  revision : Int32,
  sheet : String,
  part : String,
) -> Json raise @failure.Failure {
  if self.refresh_shared_pivot(revision, sheet, part) {
    return self.pivots(self.revision, sheet)
  }
  self.write_pivot(revision, sheet, part, None)
}

///|
/// Replaces the supported source and row/value fields using the same atomic refresh transaction.
pub fn Session::update_pivot(
  self : Session,
  revision : Int32,
  sheet : String,
  part : String,
  settings : PivotSettings,
) -> Json raise @failure.Failure {
  if self.refresh_shared_pivot(
      revision,
      sheet,
      part,
      replacement=Some(settings),
    ) {
    return self.pivots(self.revision, sheet)
  }
  self.write_pivot(revision, sheet, part, Some(settings))
}

///|
fn Session::write_pivot(
  self : Session,
  revision : Int32,
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
      if self.sheets[self.sheet_index(sheet)].state == "visible" {
        (sheet, range)
      } else {
        self.selection
      },
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
  revision : Int32,
  sheet : String,
  part : String,
  replacement : PivotSettings?,
  cached~ : PivotCache? = None,
) -> (CellEditPlan, Range)? raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  guard !current.locked else {
    @failure.reject("protected-content", "Pivot destination is protected")
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
    source_sheet=if cached is Some(_) {
      Some(pivot.sheet)
    } else {
      replacement.map(settings => settings.sourceSheet)
    },
    native=cached is None,
  )
  let settings = replacement.unwrap_or(original_settings)
  let pivot_source = self.part_xml(part)
  let pivot_root = pivot_source.nodes()[0]
  let native = flag(pivot_root, "outline") && flag(pivot_root, "outlineData")
  guard !native || settings.native_single_row() else {
    @failure.reject(
      "protected-content", "Native pivot layout requires one row field and one value",
    )
  }
  let cache = match cached {
    Some(cache) => cache
    None => self.pivot_cache(settings)
  }
  let layout = cache.layout(settings)
  let range = layout.bounds({ row: pivot.range.top, column: pivot.range.left, })
  guard !(settings.sourceSheet == sheet &&
    (
      self.pivot_source(settings).0.intersects(range) ||
      self.pivot_source(settings).0.intersects(pivot.range)
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
  guard replacement is Some(_) ||
    original_fields == cache.headers ||
    self.pivot_headers_match(
      [pivot],
      [settings],
      original_fields,
      cache.headers,
    ) else {
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
  let cache_id = natural(
    pivot_root.attribute("cacheId").unwrap_or(""),
    2147483647,
  )
  let definition = layout.definition(
    pivot.name,
    cache_id,
    range,
    data_caption=pivot_root.attribute("dataCaption").unwrap_or("Values"),
    native_header=native,
  )
  let sources = [
    (
      part,
      if native {
        retain_native_pivot_source(pivot_source, definition, [], [
          "pivotTableStyleInfo", "extLst",
        ])
      } else {
        definition
      },
    ),
  ]
  if cached is None {
    self.check_pivot_record_owner(pivot.cache, records)
    let definition = cache.definition(
      self.sheets[self.sheet_index(settings.sourceSheet)].name,
      self.pivot_source(settings).0.name(),
      record_link,
    )
    let record_markup = cache.record_markup()
    let count = cache.records.length().to_string()
    sources.append([
      (
        pivot.cache,
        if native {
          retain_native_pivot_source(
            self.part_xml(pivot.cache),
            definition,
            [("recordCount", count), ("invalid", "0")],
            ["extLst"],
          )
        } else {
          definition
        },
      ),
      (
        records,
        if native {
          retain_native_pivot_source(
            self.part_xml(records),
            record_markup,
            [("count", count)],
            [],
          )
        } else {
          record_markup
        },
      ),
    ])
  }
  let (updates, styles) = layout.cells(
    range,
    self.styles,
    self.date1904,
    data_caption=pivot_root.attribute("dataCaption").unwrap_or("Values"),
  )
  if native && flag(pivot_root, "compact", fallback=true) {
    let label = Address::{ row: range.top, column: range.left, }.name()
    let value = match current.cells.get(label) {
      Some({ value: Text(caption), .. }) => Text(caption)
      _ => Text("Row Labels")
    }
    updates[label] = { ..updates[label], value, }
  }
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
  if native {
    for key in updates.keys().to_array() {
      if current.cells.get(key) is Some(cell) &&
        pivot.range.contains(cell.address) &&
        cell.value == updates[key].value &&
        cell.formula is None {
        ignore(updates.remove(key))
      }
    }
  }
  let sources = sources.filter(pair => {
    let document = self.part_xml(pair.0)
    let root = document.nodes()[0]
    document.source()[root.start:root.end] != pair.1
  })
  let unchanged = sources.is_empty() &&
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
    let (document, edit) = pivot_root_edit(self.part_xml(path), markup)
    parts[path] = document
    edits.push((path, edit))
  }
  Some((plan, range))
}

///|
fn Session::check_pivot_record_owner(
  self : Session,
  cache : String,
  records : String,
) -> Unit raise @failure.Failure {
  let links = self.relationships()
  guard links.filter(link => !link.external && link.target == records)
    is [owner] &&
    owner.owner == cache &&
    owner.kind == relationship_uri + "pivotCacheRecords" &&
    !links.any(link => link.owner == records) else {
    @failure.reject(
      "protected-content", "Refreshing records shared by independent cache definitions requires coordinated cache support",
    )
  }
}
