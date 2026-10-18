///|
fn outline_put(
  metadata : Map[Int, Array[(String, String)]],
  index : Int,
  name : String,
  value : String,
) -> Unit {
  let values = metadata.get_or_init(index, () => [])
  values.retain(pair => pair.0 != name)
  values.push((name, value))
}

///|
fn Sheet::outline_metadata(
  self : Sheet,
  rows : Bool,
  metadata : Map[Int, Array[(String, String)]],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard metadata.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Outline edit exceeds 4096 axis items")
  }
  let tree = Tree::new(self.document)
  if rows {
    return self.row_metadata_changes(tree, metadata)
  }
  let indices = metadata.keys().to_array()
  indices.sort()
  if indices.is_empty() {
    return []
  }
  self.column_metadata_changes(
    tree,
    indices[0],
    indices[indices.length() - 1],
    indices.map(index => (index, index, metadata[index])),
  )
}

///|
fn outline_summary_changes(
  tree : Tree,
  rows : Bool,
  after : Bool,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let root = tree.root("worksheet")
  let name = if rows { "summaryBelow" } else { "summaryRight" }
  let value = if after { "1" } else { "0" }
  let xml = "<od:outlinePr xmlns:od=\"\{spreadsheet_uri}\" \{name}=\"\{value}\"/>"
  if tree.one(root.id, "sheetPr") is Some(properties) {
    if tree.one(properties.id, "outlinePr") is Some(outline) {
      return metadata_changes(outline, [(name, value)])
    }
    return [
      if tree.one(properties.id, "pageSetUpPr") is Some(next) {
        {
          node: properties.id,
          offset: next.start - properties.start,
          length: 0,
          xml,
        }
      } else {
        insertion(properties, xml)
      },
    ]
  }
  [
    {
      node: root.id,
      offset: root.opening_end - root.start,
      length: 0,
      xml: "<od:sheetPr xmlns:od=\"\{spreadsheet_uri}\">\{xml}</od:sheetPr>",
    },
  ]
}

///|
fn outline_level_changes(
  sheet : Sheet,
  rows : Bool,
  maximum : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let name = if rows { "outlineLevelRow" } else { "outlineLevelCol" }
  if tree.one(root.id, "sheetFormatPr") is Some(format) {
    return metadata_changes(format, [(name, maximum.to_string())])
  }
  if maximum == 0 {
    return []
  }
  let before = tree.one(root.id, "cols").unwrap_or(tree.nodes[sheet.data])
  [
    {
      node: root.id,
      offset: before.start - root.start,
      length: 0,
      xml: "<od:sheetFormatPr xmlns:od=\"\{spreadsheet_uri}\" defaultRowHeight=\"15\" \{name}=\"\{maximum}\"/>",
    },
  ]
}

///|
fn Session::edit_outline(
  self : Session,
  sheet : String,
  change : SheetEdit,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let original = self.sheets[index]
  let reason = self.dimension_reason(original)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let axis = match change {
    GroupOutline(axis, _, _, _)
    | CollapseOutline(axis, _, _, _, _)
    | ClearOutline(axis)
    | OutlineSummary(axis, _) => axis
    _ => abort("Invalid outline edit")
  }
  guard ["rows", "columns"].contains(axis) else {
    @failure.reject("invalid-operation", "Invalid outline axis")
  }
  let rows = axis == "rows"
  let outline = original.outline_axis(rows)
  let metadata : Map[Int, Array[(String, String)]] = Map([])
  let hidden : Map[Int, Bool] = Map([])
  let mut summary = None
  let mut levels = false
  match change {
    GroupOutline(_, first, last, remove) => {
      guard first >= 1 && last >= first && last <= outline.limit else {
        @failure.reject("invalid-operation", "Invalid outline interval")
      }
      guard last - first < 4095 else {
        @failure.reject("limit-exceeded", "Outline interval exceeds 4095 items")
      }
      for item in first..<=last {
        let old = outline.level(item)
        guard remove || old < 7 else {
          @failure.reject("invalid-operation", "Outline depth exceeds seven")
        }
        let next = if remove { (old - 1).max(0) } else { old + 1 }
        if next != old {
          outline_put(metadata, item, "outlineLevel", next.to_string())
        }
      }
      levels = true
    }
    ClearOutline(_) => {
      for (first, last, _) in outline.bands {
        guard last - first < 4095 &&
          metadata.length() + last - first + 1 <= 4095 else {
          @failure.reject("limit-exceeded", "Outline clear exceeds 4095 items")
        }
        for item in first..<=last {
          outline_put(metadata, item, "outlineLevel", "0")
          outline_put(metadata, item, "hidden", "0")
          hidden[item] = false
        }
      }
      levels = true
    }
    CollapseOutline(_, first, last, level, collapsed) => {
      guard outline.groups
        .iter()
        .find_first(group => {
          group.first == first && group.last == last && group.level == level
        })
        is Some(group) else {
        @failure.reject("invalid-operation", "Outline group changed")
      }
      guard group.summary >= 1 &&
        group.summary <= outline.limit &&
        !outline.groups.any(other => {
          other.summary == group.summary && other.level < group.level
        }) else {
        @failure.reject(
          "protected-content", "Group requires its outer summary control",
        )
      }
      if group.collapsed == collapsed {
        return self.query()
      }
      guard last - first < 4095 else {
        @failure.reject("limit-exceeded", "Outline collapse exceeds 4095 items")
      }
      outline_put(
        metadata,
        group.summary,
        "collapsed",
        if collapsed {
          "1"
        } else {
          "0"
        },
      )
      for item in first..<=last {
        let keep = collapsed ||
          outline.groups.any(other => {
            other.collapsed &&
            other.summary != group.summary &&
            other.first <= item &&
            other.last >= item &&
            (
              (
                other.level < group.level &&
                other.first <= first &&
                other.last >= last
              ) ||
              (
                other.level > group.level &&
                other.first >= first &&
                other.last <= last
              )
            )
          })
        hidden[item] = keep
        outline_put(metadata, item, "hidden", if keep { "1" } else { "0" })
      }
    }
    OutlineSummary(_, after) => {
      if outline.summary_after == after {
        return self.query()
      }
      summary = Some(after)
      for group in outline.groups {
        let marker = if after { group.last + 1 } else { group.first - 1 }
        guard marker >= 1 && marker <= outline.limit else {
          @failure.reject(
            "protected-content", "No axis item is available for the outline summary",
          )
        }
        if group.collapsed {
          outline_put(metadata, group.summary, "collapsed", "0")
        }
      }
      for group in outline.groups {
        if group.collapsed {
          outline_put(
            metadata,
            if after {
              group.last + 1
            } else {
              group.first - 1
            },
            "collapsed",
            "1",
          )
        }
      }
    }
    _ => abort("Invalid outline edit")
  }
  if metadata.is_empty() && summary is None {
    return self.query()
  }
  let edits : Array[(String, @xml.Edit)] = []
  let parts = self.parts.copy()
  let mut current = original
  let updates = original.outline_metadata(rows, metadata)
  if summary is Some(after) {
    updates.append(
      outline_summary_changes(Tree::new(original.document), rows, after),
    )
  }
  let (document, edit) = original.document.edit_source(join_insertions(updates))
  edits.push((sheet, edit))
  current = Sheet::read(
    sheet,
    original.name,
    original.state,
    document,
    self.strings,
    self.styles.length(),
  )
  if levels {
    let next = current.outline_axis(rows)
    let cleanup : Map[Int, Array[(String, String)]] = Map([])
    for group in outline.groups {
      if group.collapsed &&
        !next.groups.any(other => other.summary == group.summary) {
        outline_put(cleanup, group.summary, "collapsed", "0")
      }
    }
    let updates = current.outline_metadata(rows, cleanup)
    updates.append(
      outline_level_changes(
        current,
        rows,
        next.bands.fold(init=0, (value, band) => value.max(band.2)),
      ),
    )
    if !updates.is_empty() {
      let (document, edit) = current.document.edit_source(
        join_insertions(updates),
      )
      edits.push((sheet, edit))
      current = Sheet::read(
        sheet,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
    }
  }
  if rows && !hidden.is_empty() {
    let indices = hidden.keys().to_array()
    indices.sort()
    let mut start = indices[0]
    let mut last = start
    let mut value = hidden[start]
    let mut source = original
    for position in 1..<=indices.length() {
      let item = indices.get(position).unwrap_or(0)
      if item == last + 1 && hidden.get(item) == Some(value) {
        last = item
        continue
      }
      let (document, changes) = self.filter_dimension_changes(
        source,
        current.document,
        start,
        last,
        if value {
          0
        } else {
          1
        },
        parts,
      )
      edits.append(changes)
      current = Sheet::read(
        sheet,
        original.name,
        original.state,
        document,
        self.strings,
        self.styles.length(),
      )
      source = current
      if item != 0 {
        start = item
        last = item
        value = hidden[item]
      }
    }
  }
  if current.document.source() == original.document.source() {
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = current
  let previous = self.calculation.unwrap()
  let calculation = if !hidden.is_empty() && previous.visibility_dependent() {
    let calculation = self.calculate(sheets, None, [], self.workbook, parts~)
    edits.append(self.cache_edits(sheets, calculation))
    calculation
  } else {
    previous
  }
  self.commit(sheets, self.workbook, calculation, edits, self.selection, parts~)
  self.query()
}
