///|
fn Session::check_fill_resources(
  self : Session,
  sheet : Sheet,
  range : Range,
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
      "hyperlinks" => tree.all(node.id, "hyperlink")
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
  for link in self.relationships() {
    if link.owner != sheet.id {
      continue
    }
    guard !link.kind.to_lower().contains("threadedcomment") else {
      @failure.reject(
        "protected-content", "Threaded comments require fill ownership support",
      )
    }
    if link.kind == relationship_uri + "comments" {
      for node in self.part_xml(link.target).nodes() {
        if node.name == "comment" &&
          Range::parse(node.attribute("ref").unwrap_or("")).intersects(range) {
          @failure.reject(
            "protected-content", "Comments require fill ownership support",
          )
        }
      }
    }
  }
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
  let selected = Range::parse(range)
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
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  if seed < 1 || seed > (if vertical { 1048576 } else { 16384 }) {
    return self.query(sheet=Some(sheet), range=Some(selected.name()))
  }
  let target = if adjacent {
    selected
  } else if vertical {
    {
      ..selected,
      top: if forward {
        first + 1
      } else {
        first
      },
      bottom: if forward {
        last
      } else {
        last - 1
      },
    }
  } else {
    {
      ..selected,
      left: if forward {
        first + 1
      } else {
        first
      },
      right: if forward {
        last
      } else {
        last - 1
      },
    }
  }
  let source = if vertical {
    { ..selected, top: seed, bottom: seed, }
  } else {
    { ..selected, left: seed, right: seed, }
  }
  let affected = {
    top: source.top.min(target.top),
    left: source.left.min(target.left),
    bottom: source.bottom.max(target.bottom),
    right: source.right.max(target.right),
  }
  for scope in [source, target] {
    let reason = self.format_reason(current, scope)
    guard reason.is_empty() &&
      !current.merges.any(merge => merge.intersects(scope)) else {
      @failure.reject(
        "protected-content",
        if reason.is_empty() {
          "Merged cells require fill geometry support"
        } else {
          reason
        },
      )
    }
  }
  self.check_fill_resources(current, affected)
  let updates : Map[String, CellContent] = Map([])
  let styles : Map[String, Int] = Map([])
  let formulas : Map[String, Expression] = Map([])
  let mut units = 0
  for row in target.top..<=target.bottom {
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let from : Address = if vertical {
        { row: seed, column, }
      } else {
        { row, column: seed, }
      }
      let key = address.name()
      let origin = from.name()
      let cell = current.cells.get(origin)
      let formula = cell
        .bind(cell => cell.formula)
        .map(text => {
          let expression = formulas
            .get(origin)
            .unwrap_or_else(() => {
              let expression = parse_formula(text)
              formulas[origin] = expression
              expression
            })
          expression.source(
            rows=row - from.row,
            columns=column - from.column,
            invalid_ref=true,
          )
        })
      let value = if formula is Some(_) {
        Blank
      } else {
        cell.map(cell => cell.value).unwrap_or(Blank)
      }
      units += formula
        .map(text => text.length())
        .unwrap_or(value.display().length())
      guard units <= 1048576 &&
        formula.map(text => text.length() <= 8192).unwrap_or(true) else {
        @failure.reject(
          "limit-exceeded", "Cell fill exceeds text or formula budget",
        )
      }
      let style = current.style_at(from)
      let old = current.cells.get(key)
      if old.bind(cell => cell.formula) != formula ||
        (
          formula is None &&
          old.map(cell => cell.value).unwrap_or(Blank) != value
        ) ||
        current.style_at(address) != style {
        updates[key] = { value, formula, keep_shared: false, }
        styles[key] = style
      }
    }
  }
  if updates.is_empty() {
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
    (sheet, selected),
    styles=Map([(index, styles)]),
  )
}
