///|
priv struct PivotLocation {
  sheet : String
  part : String
  name : String
  range : Range
  cache : String
  sourceSheet : String?
  source : Range?
  sourceTable : String?
}

///|
fn Session::pivot_locations(
  self : Session,
) -> Array[PivotLocation] raise @failure.Failure {
  let result : Array[PivotLocation] = []
  let relations = self.relationships()
  for sheet in self.sheets {
    for
      rel in relations.filter(rel => {
        rel.owner == sheet.id && rel.kind == relationship_uri + "pivotTable"
      }) {
      guard result.length() < 64 else {
        @failure.reject("limit-exceeded", "Pivot count exceeds budget")
      }
      guard !rel.external else {
        @failure.reject("malformed-xlsx", "Invalid pivot table relationship")
      }
      let pivot = Tree::new(self.part_xml(rel.target))
      let root = pivot.root("pivotTableDefinition")
      guard pivot.one(root.id, "location") is Some(location) else {
        @failure.reject(
          "protected-content", "Pivot output location is unavailable",
        )
      }
      let body = Range::parse(location.attribute("ref").unwrap_or(""))
      let pages = pivot
        .one(root.id, "pageFields")
        .map(node => pivot.all(node.id, "pageField").length())
        .unwrap_or(0)
      guard pages <= 8 &&
        (
          pages == 0 ||
          (
            root.attribute("pageWrap").unwrap_or("0") == "0" &&
            !flag(root, "pageOverThenDown")
          )
        ) &&
        body.top > (if pages > 0 { pages + 1 } else { 0 }) else {
        @failure.reject(
          "protected-content", "Pivot report field positions require layout support",
        )
      }
      let range : Range = {
        ..body,
        top: body.top - (if pages > 0 { pages + 1 } else { 0 }),
      }
      guard relations.filter(link => {
          link.owner == rel.target &&
          link.kind == relationship_uri + "pivotCacheDefinition"
        })
        is [cache] &&
        !cache.external else {
        @failure.reject("malformed-xlsx", "Invalid pivot cache relationship")
      }
      let source = Tree::new(self.part_xml(cache.target))
      let workbook = Tree::new(self.workbook)
      let cache_entries = workbook
        .one(workbook.root("workbook").id, "pivotCaches")
        .map(node => workbook.all(node.id, "pivotCache"))
        .unwrap_or([])
      let identity = natural(
        root.attribute("cacheId").unwrap_or(""),
        2147483647,
      )
      guard cache_entries.filter(entry => {
          natural(entry.attribute("cacheId").unwrap_or(""), 2147483647) ==
          identity
        })
        is [entry] &&
        relations.any(link => {
          link.owner == self.main &&
          link.kind == relationship_uri + "pivotCacheDefinition" &&
          link.target == cache.target &&
          Some(link.id) ==
          entry.attribute(
            "id",
            uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
          )
        }) else {
        @failure.reject(
          "malformed-xlsx", "Workbook and pivot cache references disagree",
        )
      }
      let worksheet = source
        .one(source.root("pivotCacheDefinition").id, "cacheSource")
        .bind(node => source.one(node.id, "worksheetSource"))
      let (source_sheet, bounds, source_table) = worksheet
        .map(node => self.worksheet_pivot_source(node))
        .unwrap_or((None, None, None))
      result.push({
        sheet: sheet.id,
        part: rel.target,
        name: root.attribute("name").unwrap_or(""),
        range,
        cache: cache.target,
        sourceSheet: source_sheet,
        source: bounds,
        sourceTable: source_table,
      })
    }
  }
  result
}

///|
/// Reads native locations and refresh state without treating cached output as a new pivot.
pub fn Session::pivots(
  self : Session,
  revision : Int32,
  sheet : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  ignore(self.sheet_index(sheet))
  let items : Array[Json] = self
    .pivot_locations()
    .filter(pivot => pivot.sheet == sheet)
    .map(pivot => {
      let (settings, reason) = try {
        let (settings, _) = self.pivot_settings(pivot, shared=true)
        (Some(settings), "")
      } catch {
        @failure.Failure(message~, ..) => (None, message)
      }
      let item : Json = {
        "part": pivot.part,
        "name": pivot.name,
        "range": pivot.range.name(),
        "sourceSheet": pivot.sourceSheet
        .map(value => Json(value))
        .unwrap_or(Json::null()),
        "source": pivot.source
        .map(range => Json(pivot.sourceTable.unwrap_or(range.name())))
        .unwrap_or(Json::null()),
        "stale": flag(self.part_xml(pivot.cache).nodes()[0], "invalid"),
        "settings": settings.map(value => Json(value)).unwrap_or(Json::null()),
        "reason": reason,
      }
      if settings is None &&
        pivot.sourceSheet is None &&
        pivot.source is Some(_) {
        let recovery = Json(
          self.pivot_settings(pivot, shared=true, source_sheet=Some(sheet)).0,
        ) catch {
          @failure.Failure(..) => Json::null()
        }
        if (item, recovery) is (Object(fields), Object(recovery)) {
          recovery.remove("sourceSheet") |> ignore
          fields["recovery"] = Json(recovery)
        }
      }
      item
    })
  { "revision": revision, "items": items }
}

///|
/// Creates real worksheet-backed cache, records, pivot definition and output in one history entry.
pub fn Session::create_pivot(
  self : Session,
  revision : Int32,
  sheet : String,
  name : String,
  destination : String,
  settings : PivotSettings,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard !settings.filters.any(filter => {
    !filter.report &&
    filter.values is Some(_) &&
    !(settings.rows + settings.columns).contains(filter.field)
  }) else {
    @failure.reject(
      "protected-content", "Unused pivot member filters require a linked slicer",
    )
  }
  let reason = self.sheet_rename_reason(
    structure=false,
    tables=true,
    pivots=true,
  )
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  validate_defined_name(name)
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let existing = self.pivot_locations()
  guard existing.length() < 16 &&
    !existing.any(pivot => pivot.name.to_lower() == name.to_lower()) &&
    !current.locked &&
    current.state == "visible" else {
    @failure.reject(
      "protected-content", "Pivot name, count or destination worksheet is unavailable",
    )
  }
  let cache = self.pivot_cache(settings)
  let layout = cache.layout(settings)
  let range = layout.bounds(Address::parse(destination))
  let source = self.pivot_source(settings).0
  guard !(settings.sourceSheet == sheet && source.intersects(range)) &&
    !current.merges.any(merge => merge.intersects(range)) &&
    !self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .any(table => table.sheet == sheet && table.range.intersects(range)) &&
    !existing.any(pivot => pivot.sheet == sheet && pivot.range.intersects(range)) else {
    @failure.reject(
      "invalid-operation", "Pivot output overlaps source or a structured range",
    )
  }
  for cell in current.cells.values() {
    guard !range.contains(cell.address) ||
      (cell.value == Blank && cell.formula is None && cell.read_only.is_empty()) else {
      @failure.reject("protected-content", "Pivot output requires empty cells")
    }
  }
  guard !self
    .read_sheet_notes(current)
    .map(notes => notes.entries.any(note => range.contains(note.address)))
    .unwrap_or(false) else {
    @failure.reject("protected-content", "Pivot output contains cell resources")
  }
  let source_tree = Tree::new(current.document)
  if source_tree.one(source_tree.root("worksheet").id, "hyperlinks")
    is Some(links) {
    for link in source_tree.all(links.id, "hyperlink") {
      guard !Range::parse(link.attribute("ref").unwrap_or("")).intersects(range) else {
        @failure.reject("protected-content", "Pivot output contains hyperlinks")
      }
    }
  }
  let (updates, styles) = layout.cells(range, self.styles, self.date1904)
  let formatting = self.pivot_formats(layout, range, current, styles)
  let plan = self.prepare_cells(
    Map([(index, updates)]),
    styles=Map([(index, styles)]),
    formatting~,
  )
  let parts = plan.parts
  let created = plan.created_parts
  let edits = plan.edits
  let sheets = plan.sheets
  let (cache_part, cache_link) = self.create_sheet_resource(
    self.main,
    "pivotCacheDefinition",
    "<pivotCacheDefinition xmlns=\"\{spreadsheet_uri}\"/>",
    parts,
    created,
    edits,
  )
  let (_, record_link) = self.create_sheet_resource(
    cache_part,
    "pivotCacheRecords",
    cache.record_markup(),
    parts,
    created,
    edits,
  )
  let (cache_document, edit) = pivot_root_edit(
    parts[cache_part],
    cache.definition(
      self.sheets[self.sheet_index(settings.sourceSheet)].name,
      source.name(),
      record_link,
    ),
  )
  parts[cache_part] = cache_document
  edits.push((cache_part, edit))
  let workbook_tree = Tree::new(self.workbook)
  let workbook_root = workbook_tree.root("workbook")
  let caches = workbook_tree.one(workbook_root.id, "pivotCaches")
  let used_cache_ids = caches
    .map(node => {
      workbook_tree
      .all(node.id, "pivotCache")
      .map(node => natural(node.attribute("cacheId").unwrap_or(""), 2147483647))
    })
    .unwrap_or([])
  let cache_id = for id in 1..<=257 {
    if !used_cache_ids.contains(id) {
      break id
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Pivot cache identities exhausted")
  }
  let (pivot_part, _) = self.create_sheet_resource(
    sheet,
    "pivotTable",
    layout.definition(name, cache_id, range),
    parts,
    created,
    edits,
  )
  let relations = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"cache\" Type=\"\{relationship_uri}pivotCacheDefinition\" Target=\"/\{escaped_attribute(cache_part)}\"/></Relationships>"
  let path = workbook_relations(pivot_part)
  let document = @xml.Document::parse(
    @utf8.encode(relations),
    path,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[path] = document
  created[path] = document
  let entry = "<od:pivotCache xmlns:od=\"\{spreadsheet_uri}\" xmlns:r=\"\{relationship_uri[:relationship_uri.length() - 1]}\" cacheId=\"\{cache_id}\" r:id=\"\{cache_link}\"/>"
  let markup = if caches is Some(_) {
    entry
  } else {
    "<od:pivotCaches xmlns:od=\"\{spreadsheet_uri}\">\{entry}</od:pivotCaches>"
  }
  let change = if caches is Some(node) {
    insertion(node, markup)
  } else {
    let before = workbook_tree.children
      .get(workbook_root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        [
          "smartTagPr", "smartTagTypes", "webPublishing", "fileRecoveryPr", "webPublishObjects",
          "extLst",
        ].contains(node.name)
      })
    match before {
      Some(node) =>
        {
          node: workbook_root.id,
          offset: node.start - workbook_root.start,
          length: 0,
          xml: markup,
        }
      None => insertion(workbook_root, markup)
    }
  }
  let (workbook, edit) = self.workbook.edit_source([change])
  edits.push((self.main, edit))
  let calculation = self.calculate(sheets, None, [], workbook, parts~)
  edits.append(self.cache_edits(sheets, calculation))
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    (sheet, range),
    parts~,
    created_parts=created,
  )
  self.pivots(self.revision, sheet)
}
