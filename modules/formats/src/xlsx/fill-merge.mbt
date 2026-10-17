///|
fn fill_destination(
  source : Range,
  selected : Range,
  direction : String,
) -> Range {
  match direction {
    "down" => { ..selected, top: source.bottom + 1, }
    "up" => { ..selected, bottom: source.top - 1, }
    "right" => { ..selected, left: source.right + 1, }
    _ => { ..selected, right: source.left - 1, }
  }
}

///|
fn fill_merge_size(ranges : Array[Range], scope : Range) -> (Int, Int)? {
  guard ranges.get(0) is Some(first) else { return None }
  let width = first.right - first.left + 1
  let height = first.bottom - first.top + 1
  if ranges.all(r => {
      r.right - r.left + 1 == width && r.bottom - r.top + 1 == height
    }) &&
    ranges.length() * width * height ==
    (scope.right - scope.left + 1) * (scope.bottom - scope.top + 1) {
    Some((width, height))
  } else {
    None
  }
}

///|
fn Sheet::fill_merges(
  self : Sheet,
  source : Range,
  selected : Range,
  direction : String,
) -> Array[Range] raise @failure.Failure {
  let target = fill_destination(source, selected, direction)
  let seeds = self.merges.filter(r => r.intersects(source))
  let removed = self.merges.filter(r => r.intersects(target))
  guard seeds.all(r => source.covers(r)) && removed.all(r => target.covers(r)) else {
    @failure.reject(
      "protected-content", "Fill must include complete merged cells",
    )
  }
  if seeds.is_empty() && removed.is_empty() {
    return self.merges
  }
  check_merge_markup(Tree::new(self.document))
  let result = self.merges.filter(r => !r.intersects(target))
  let vertical = direction == "down" || direction == "up"
  let start = if vertical { source.top } else { source.left }
  let count = if vertical {
    source.bottom - source.top + 1
  } else {
    source.right - source.left + 1
  }
  let first = if vertical { target.top } else { target.left }
  let last = if vertical { target.bottom } else { target.right }
  let initial = first - ((first - start) % count + count) % count
  for axis = initial; axis <= last; axis = axis + count {
    for seed in seeds {
      let offset = axis - start
      let merge : Range = if vertical {
        {
          ..seed,
          top: (seed.top + offset).max(target.top),
          bottom: (seed.bottom + offset).min(target.bottom),
        }
      } else {
        {
          ..seed,
          left: (seed.left + offset).max(target.left),
          right: (seed.right + offset).min(target.right),
        }
      }
      if merge.top <= merge.bottom &&
        merge.left <= merge.right &&
        (merge.top != merge.bottom || merge.left != merge.right) {
        guard result.length() < 1024 else {
          @failure.reject(
            "limit-exceeded", "Filled merged range count exceeds budget",
          )
        }
        result.push(merge)
      }
    }
  }
  if result.length() == self.merges.length() &&
    result.all(r => self.merges.contains(r)) {
    self.merges
  } else {
    if !removed.is_empty() {
      let size = fill_merge_size(seeds, source)
      guard size is Some(_) && size == fill_merge_size(removed, target) else {
        @failure.reject(
          "protected-content", "Existing fill merges must tile equally sized source and target cells",
        )
      }
    }
    result
  }
}

///|
fn fill_merge_changes(
  document : @xml.Document,
  merges : Array[Range],
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(document)
  check_merge_markup(tree)
  let root = tree.root("worksheet")
  let container = tree.one(root.id, "mergeCells")
  let old = container.map(n => tree.all(n.id, "mergeCell")).unwrap_or([])
  let existing = old.map(n => Range::parse(n.attribute("ref").unwrap_or("")))
  let added = merges.filter(r => !existing.contains(r))
  let markup = added
    .map(r => {
      "<od:mergeCell xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{r.name()}\"/>"
    })
    .join("")
  let changes : Array[@xml.SourceChange] = []
  if container is Some(container) {
    for node in old {
      if !merges.contains(Range::parse(node.attribute("ref").unwrap_or(""))) {
        changes.push(sheet_node_removal(tree, node))
      }
    }
    changes.append(
      metadata_changes(container, [("count", merges.length().to_string())]),
    )
    if !markup.is_empty() {
      changes.push(insertion(container, markup))
    }
  } else if !merges.is_empty() {
    let after = [
      "phoneticPr", "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions",
      "pageMargins", "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "customProperties",
      "cellWatches", "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF",
      "picture", "oleObjects", "controls", "webPublishItems", "tableParts", "extLst",
    ]
    let markup = "<od:mergeCells xmlns:od=\"\{spreadsheet_uri}\" count=\"\{merges.length()}\">\{markup}</od:mergeCells>"
    changes.push(
      if tree.children
        .get(root.id)
        .unwrap_or([])
        .iter()
        .find_first(n => after.contains(n.name))
        is Some(next) {
        {
          node: root.id,
          offset: next.start - root.start,
          length: 0,
          xml: markup,
        }
      } else {
        insertion(root, markup)
      },
    )
  }
  document.edit_source(changes)
}
