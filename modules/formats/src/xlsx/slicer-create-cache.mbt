///|
fn Session::slicer_creation_cache(
  self : Session,
  pivot : PivotLocation,
  field : Int,
  settings : PivotSettings,
  data : PivotCache,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> (SlicerCache, @xml.Document) raise @failure.Failure {
  let paths = self.slicer_parts(
    self.main,
    self.workbook,
    slicer_cache_extension,
    "slicerCaches",
    "slicerCache",
    "slicerCache",
  )
  let names : Map[String, Bool] = Map([])
  let uids : Map[String, Bool] = Map([])
  let matches : Array[SlicerCache] = []
  let tab = self.slicer_sheet_id(pivot.sheet)
  for path in paths {
    let tree = Tree::new(self.part_xml(path))
    let root = tree.document.nodes()[0]
    names[slicer_text(root, "name").to_upper()] = true
    if root.attribute(
        "uid",
        uri="http://schemas.microsoft.com/office/spreadsheetml/2016/revision10",
      )
      is Some(uid) {
      guard !uids.contains(uid.to_upper()) else {
        @failure.reject("protected-content", "Duplicate slicer cache UID")
      }
      uids[uid.to_upper()] = true
    }
    if root.attribute("sourceName").map(decode_text) ==
      Some(data.headers[field]) &&
      tree
      .slicer_children(root.id, "pivotTables")
      .any(list => {
        tree
        .slicer_children(list.id, "pivotTable")
        .any(node => {
          node.attribute("name").map(decode_text) == Some(pivot.name) &&
          node.attribute("tabId").map(value => natural(value, 2147483647)) ==
          Some(natural(tab, 2147483647))
        })
      }) {
      matches.push(self.read_slicer_cache(path, self.pivot_locations()))
    }
  }
  guard matches.length() <= 1 else {
    @failure.reject(
      "protected-content", "Ambiguous slicer cache for pivot field",
    )
  }
  if matches is [cache] {
    return (cache, self.workbook)
  }
  guard paths.length() < 64 &&
    (uids.is_empty() || uids.length() == paths.length()) else {
    @failure.reject(
      "protected-content", "Slicer cache count or UID profile requires support",
    )
  }
  for key in self.formula_names().sources.keys() {
    names[key.1.to_upper()] = true
  }
  for table in self.formula_names().tables {
    names[table.name.to_upper()] = true
  }
  let name = for index in 1..<=16384 {
    let name = "odSlicerCache\{index}"
    if !names.contains(name.to_upper()) {
      break name
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Slicer cache names exhausted")
  }
  let uid = slicer_creation_uid(uids, paths.length(), "00000002")
  let values = data.axis_items(field)
  guard !values.is_empty() && values.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Slicer members exceed budget")
  }
  let cache_id = self.part_xml(pivot.part).nodes()[0]
    .attribute("cacheId")
    .unwrap()
  let items = values.mapi((index, _) => "<i x=\"\{index}\" s=\"1\"/>").join("")
  let source = "<slicerCacheDefinition xmlns=\"\{slicer_uri}\"\{uid} name=\"\{name}\" sourceName=\"\{escaped_attribute(encoded_text(data.headers[field]))}\"><pivotTables><pivotTable tabId=\"\{tab}\" name=\"\{escaped_attribute(encoded_text(pivot.name))}\"/></pivotTables><data><tabular pivotCacheId=\"\{cache_id}\" sortOrder=\"ascending\" customListSort=\"0\" crossFilter=\"showItemsWithDataAtTop\"><items count=\"\{values.length()}\">\{items}</items></tabular></data></slicerCacheDefinition>"
  let (part, relation) = self.create_sheet_resource(
    self.main,
    "slicerCache",
    source,
    parts,
    created,
    edits,
  )
  let (workbook, edit) = slicer_reference(
    self.workbook,
    slicer_cache_extension,
    "slicerCaches",
    "slicerCache",
    relation,
  )
  edits.push((self.main, edit))
  let candidate = { ..self, parts, workbook, }
  let cache = candidate.read_slicer_cache(part, self.pivot_locations())
  candidate.sync_slicer_state(cache, settings, data, edits)
  (candidate.read_slicer_cache(part, self.pivot_locations()), workbook)
}
