///|
fn projected_analysis_field(
  mapping : Array[Int32],
  field : Int32,
) -> Int32 raise @failure.Failure {
  guard mapping.get(field) is Some(next) && next >= 0 else {
    @failure.reject(
      "protected-content", "A pivot or analysis control still uses the removed source field",
    )
  }
  next
}

///|
fn analysis_column_mapping(
  source : Range,
  fields : Int32,
  change : AxisChange,
) -> Array[Int32] {
  let mapping : Array[Int32] = []
  let width = source.right - source.left + 1
  let mut index = 0
  for field in 0..<fields {
    if change.insert {
      mapping.push(
        field +
        (if source.left + field >= change.first || field >= width {
          change.count
        } else {
          0
        }),
      )
    } else if field < width &&
      source.left + field >= change.first &&
      source.left + field < change.first + change.count {
      mapping.push(-1)
    } else {
      mapping.push(index)
      index += 1
    }
  }
  mapping
}

///|
fn project_analysis_fields(
  document : @xml.Document,
  mapping : Array[Int32],
  added : Map[Int32, String],
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(document)
  let cache = tree.nodes[0].name == "pivotCacheDefinition"
  let list = tree
    .one(0, if cache { "cacheFields" } else { "pivotFields" })
    .unwrap()
  let fields = tree.all(
    list.id,
    if cache {
      "cacheField"
    } else {
      "pivotField"
    },
  )
  guard fields.length() == mapping.length() &&
    natural(list.attribute("count").unwrap_or(""), 80) == fields.length() else {
    @failure.reject("malformed-xlsx", "Analysis field count is inconsistent")
  }
  let removed = fields
    .mapi((index, field) => if mapping[index] < 0 { Some(field) } else { None })
    .filter_map(field => field)
  let changes = metadata_changes(list, [
    ("count", (fields.length() - removed.length() + added.length()).to_string()),
  ])
  for field in removed {
    changes.push(sheet_node_removal(tree, field))
  }
  let mut position = 0
  let prefix = list.qualified[:list.qualified.length() - list.name.length()].to_owned()
  for index, field in fields {
    if mapping[index] < 0 {
      continue
    }
    let markup = StringBuilder()
    while position < mapping[index] {
      if cache {
        markup <+
          "<\{prefix}cacheField name='\{escaped_attribute(encoded_text(added[position]))}'><\{prefix}sharedItems count='1' containsBlank='1'><\{prefix}m/></\{prefix}sharedItems></\{prefix}cacheField>"
      } else {
        markup <+
          "<\{prefix}pivotField dataField='0' defaultSubtotal='0' showAll='0' compact='0' outline='0'/>"
      }
      position += 1
    }
    if !markup.to_string().is_empty() {
      changes.push({
        node: list.id,
        offset: field.start - list.start,
        length: 0,
        xml: markup.to_string(),
      })
    }
    position = mapping[index] + 1
  }
  for node in document.nodes() {
    if removed.any(field => node.start >= field.start && node.end <= field.end) {
      continue
    }
    let attributes = if cache && node.name == "fieldGroup" {
      ["base", "par"]
    } else if !cache && node.name == "field" {
      ["x"]
    } else if !cache && node.name == "dataField" {
      ["fld", "baseField"]
    } else if !cache && node.name == "pageField" {
      ["fld"]
    } else {
      []
    }
    for name in attributes {
      if node.attribute(name) is Some(value) && value != "-2" {
        let field = natural(value, mapping.length() - 1)
        changes.append(
          metadata_changes(node, [
            (name, projected_analysis_field(mapping, field).to_string()),
          ]),
        )
      }
    }
  }
  document.edit_source(changes)
}

///|
fn Session::project_analysis_columns(
  self : Session,
  path : String,
  source : Range,
  next : Range,
  change : AxisChange,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  projected_records : Map[String, Array[Int32]],
  resources : Array[String],
) -> Unit raise @failure.Failure {
  let original = self.part_xml(path)
  let tree = Tree::new(original)
  let fields = tree.all(tree.one(0, "cacheFields").unwrap().id, "cacheField")
  let width = source.right - source.left + 1
  guard !change.rows &&
    change.band is None &&
    fields.length() >= width &&
    fields.length() <= 80 else {
    @failure.reject(
      "protected-content", "Pivot source field changes require complete column intervals",
    )
  }
  let next_width = next.right - next.left + 1
  guard width <= 64 &&
    next_width <= 64 &&
    fields.length() + next_width - width <= 80 else {
    @failure.reject(
      "limit-exceeded", "Pivot source or native field count exceeds budget",
    )
  }
  let mapping = analysis_column_mapping(source, fields.length(), change)
  let added : Map[Int32, String] = Map([])
  if change.insert {
    let names : Array[String] = []
    for part in resources {
      for node in self.part_xml(part).nodes() {
        if ["cacheField", "dataField"].contains(node.name) &&
          node.attribute("name") is Some(name) {
          names.push(decode_text(name))
        }
      }
    }
    for
      field in (change.first - source.left)..<(change.first -
      source.left +
      change.count) {
      added[field] = pivot_field_name("Column" + (field + 1).to_string(), names)
    }
  }
  let headers = fields.map(field => {
    decode_text(field.attribute("name").unwrap_or(""))
  })
  let removed = headers
    .mapi((field, name) => if mapping[field] < 0 { Some(name) } else { None })
    .filter_map(name => name)
  let pivots = self.pivot_locations().filter(pivot => pivot.cache == path)
  for pivot in pivots {
    let settings = self.cached_pivot_settings(pivot).0
    for field in settings.used_source_fields() {
      ignore(projected_analysis_field(mapping, field))
    }
  }
  for cache in self.affected_slicer_caches(pivots) {
    guard !removed.contains(cache.source) else {
      @failure.reject(
        "protected-content", "A slicer still uses the removed source field",
      )
    }
  }
  for sheet in self.sheets {
    for control in self.read_timelines(sheet.id) {
      if control.cache.pivot_cache == path ||
        control.cache.connections.any(pair => pair.0.cache == path) {
        guard !removed.contains(control.cache.source) else {
          @failure.reject(
            "protected-content", "A timeline still uses the removed source field",
          )
        }
      }
    }
  }
  let relationships = self.relationships()
  let links = relationships.filter(link => link.owner == path)
  guard links is [record] &&
    !record.external &&
    record.kind == relationship_uri + "pivotCacheRecords" else {
    @failure.reject(
      "protected-content", "Analysis records require a single internal owner link",
    )
  }
  let plain = tree
    .one(0, "extLst")
    .map(list => original.edit_source([sheet_node_removal(tree, list)]).0)
    .unwrap_or(original)
  pivot_cache_profile(plain, record.id)
  guard !relationships.any(link => link.owner == record.target) else {
    @failure.reject(
      "protected-content", "Analysis record relationships require preservation support",
    )
  }
  for
    owner in relationships.filter(link => {
      !link.external && link.target == record.target
    }) {
    guard owner.kind == relationship_uri + "pivotCacheRecords" &&
      resources.contains(owner.owner) else {
      @failure.reject(
        "protected-content", "Unknown analysis record ownership prevents column editing",
      )
    }
    let peer = Tree::new(self.part_xml(owner.owner))
    let origin = peer
      .one(0, "cacheSource")
      .bind(node => peer.one(node.id, "worksheetSource"))
    let current = tree
      .one(0, "cacheSource")
      .bind(node => tree.one(node.id, "worksheetSource"))
      .unwrap()
    guard peer.nodes[0].name == "pivotCacheDefinition" &&
      origin is Some(origin) &&
      self.worksheet_pivot_source(origin).0 ==
      self.worksheet_pivot_source(current).0 else {
      @failure.reject(
        "protected-content", "Shared analysis records require coordinated source columns",
      )
    }
    let range = self.worksheet_pivot_source(origin).1.unwrap_or_else(() => {
      @failure.reject(
        "protected-content", "Shared analysis source is unavailable",
      )
    })
    guard range.right - range.left + 1 == width &&
      analysis_column_mapping(range, width, change) ==
      mapping[:width].to_owned() else {
      @failure.reject(
        "protected-content", "Shared analysis records require the same field mapping",
      )
    }
  }
  let (records, record_edit) = project_analysis_records(
    self.part_xml(record.target),
    original,
    mapping[:width].to_owned(),
  )
  if projected_records.get(record.target) is Some(previous) {
    guard previous == mapping[:width].to_owned() else {
      @failure.reject(
        "protected-content", "Shared analysis records require the same field mapping",
      )
    }
  } else {
    parts[record.target] = records
    edits.push((record.target, record_edit))
    projected_records[record.target] = mapping[:width].to_owned()
  }
  for pivot in pivots {
    let (document, edit) = project_analysis_fields(
      parts.get(pivot.part).unwrap_or(self.part_xml(pivot.part)),
      mapping,
      added,
    )
    parts[pivot.part] = document
    edits.push((pivot.part, edit))
  }
  let (document, edit) = project_analysis_fields(original, mapping, added)
  edits.push((path, edit))
  let source_node = Tree::new(document)
    .one(0, "cacheSource")
    .bind(node => Tree::new(document).one(node.id, "worksheetSource"))
    .unwrap()
  let changes = if source_node.attribute("name") is None {
    metadata_changes(source_node, [("ref", next.name())])
  } else {
    []
  }
  changes.append(metadata_changes(document.nodes()[0], [("invalid", "1")]))
  let (document, edit) = document.edit_source(changes)
  parts[path] = document
  edits.push((path, edit))
}
