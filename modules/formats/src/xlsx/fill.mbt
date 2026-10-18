///|
fn Session::check_fill_resources(
  self : Session,
  sheet : Sheet,
  range : Range,
  hyperlinks~ : Bool = false,
) -> Unit raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  for cell in sheet.cells.values() {
    if range.contains(cell.address) &&
      tree.one(cell.node, "extLst") is Some(extension) &&
      (
        !tree.children.get(extension.id).unwrap_or([]).is_empty() ||
        !extension.text.trim().is_empty()
      ) {
      @failure.reject(
        "protected-content", "Cell extensions require fill ownership support",
      )
    }
  }
  for node in tree.children.get(root.id).unwrap_or([]) {
    guard node.uri == spreadsheet_uri &&
      !(["extLst", "tableParts", "pivotTableParts"].contains(node.name) &&
      !tree.children.get(node.id).unwrap_or([]).is_empty()) else {
      @failure.reject(
        "protected-content", "Cell-bound resources require fill ownership support",
      )
    }
    let rules = match node.name {
      "conditionalFormatting" => [node]
      "dataValidations" => tree.all(node.id, "dataValidation")
      "hyperlinks" =>
        if hyperlinks {
          []
        } else {
          tree.all(node.id, "hyperlink")
        }
      _ => []
    }
    for rule in rules {
      let refs = rule
        .attribute(if node.name == "hyperlinks" { "ref" } else { "sqref" })
        .unwrap_or("")
      guard !clear_rule_ranges(refs).any(item => item.intersects(range)) else {
        @failure.reject(
          "protected-content", "Rules and links require reference-aware fill support",
        )
      }
    }
  }
  // Autofill changes values and styles; existing cell notes stay at their cells.
  ignore(self.read_sheet_notes(sheet))
}

///|
fn Session::fill_cells(
  self : Session,
  sheet : String,
  range : String,
  direction : String,
) -> Json raise @failure.Failure {
  guard ["down", "up", "right", "left"].contains(direction) else {
    @failure.reject("invalid-operation", "Invalid cell fill direction")
  }
  let current = self.sheets[self.sheet_index(sheet)]
  let selected = current.merge_target(Range::parse(range))
  guard (selected.bottom - selected.top + 1).to_int64() *
    (selected.right - selected.left + 1).to_int64() <=
    4096 else {
    @failure.reject("limit-exceeded", "Cell fill exceeds 4096 cells")
  }
  let vertical = direction == "down" || direction == "up"
  let forward = direction == "down" || direction == "right"
  let first = if vertical { selected.top } else { selected.left }
  let last = if vertical { selected.bottom } else { selected.right }
  let adjacent = first == last
  let seed = if forward {
    first - (if adjacent { 1 } else { 0 })
  } else {
    last + (if adjacent { 1 } else { 0 })
  }
  if seed < 1 || seed > (if vertical { 1048576 } else { 16384 }) {
    return self.query(sheet=Some(sheet), range=Some(selected.name()))
  }
  let edge = if vertical {
    { ..selected, top: seed, bottom: seed, }
  } else {
    { ..selected, left: seed, right: seed, }
  }
  let mut source = edge
  for merge in current.merges {
    if merge.intersects(edge) {
      source = if vertical {
        {
          ..source,
          top: source.top.min(merge.top),
          bottom: source.bottom.max(merge.bottom),
        }
      } else {
        {
          ..source,
          left: source.left.min(merge.left),
          right: source.right.max(merge.right),
        }
      }
    }
  }
  if source == selected {
    return self.query()
  }
  guard (if adjacent {
    !source.intersects(selected)
  } else {
    selected.covers(source)
  }) else {
    @failure.reject(
      "protected-content", "Fill must include complete merged source cells",
    )
  }
  let affected = {
    top: selected.top.min(source.top),
    bottom: selected.bottom.max(source.bottom),
    left: selected.left.min(source.left),
    right: selected.right.max(source.right),
  }
  self.fill_series(
    sheet,
    CopySeries,
    source.name(),
    affected.name(),
    direction,
    result_selection=Some(selected),
  )
}

///|
fn Session::check_fill_cells(
  self : Session,
  current : Sheet,
  scopes : Array[Range],
) -> Unit raise @failure.Failure {
  for scope in scopes {
    let reason = self.format_reason(current, scope)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
  }
}

///|
fn Session::commit_fill(
  self : Session,
  index : Int,
  selected : Range,
  updates : Map[String, CellContent],
  styles : Map[String, Int],
  merges~ : Array[Range]? = None,
) -> Json raise @failure.Failure {
  let current = self.sheets[index]
  let merges = merges.unwrap_or(current.merges)
  if updates.is_empty() && merges == current.merges {
    return self.query()
  }
  current.expand_shared_updates(updates)
  let expanded_units = updates
    .values()
    .fold(init=0L, (sum, value) => {
      sum +
      value.formula
      .map(f => f.length())
      .unwrap_or(value.value.display().length())
      .to_int64()
    })
  guard expanded_units <= 1048576 else {
    @failure.reject(
      "limit-exceeded", "Expanded fill formulas exceed source budget",
    )
  }
  self.commit_cells(
    Map([(index, updates)]),
    (current.id, selected),
    styles=Map([(index, styles)]),
    merges=Map([(index, merges)]),
  )
}
