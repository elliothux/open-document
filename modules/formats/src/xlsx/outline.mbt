///|
priv struct OutlineGroup {
  first : Int
  last : Int
  level : Int
  summary : Int
  collapsed : Bool
}

///|
priv struct OutlineAxis {
  summary_after : Bool
  limit : Int
  bands : Array[(Int, Int, Int)]
  collapsed : Map[Int, Bool]
  groups : Array[OutlineGroup]
}

///|
fn outline_settings(tree : Tree) -> (Bool, Bool) raise @failure.Failure {
  let properties = tree.one(tree.root("worksheet").id, "sheetPr")
  let outline = properties.bind(node => tree.one(node.id, "outlinePr"))
  if outline is Some(node) {
    guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() &&
        ["applyStyles", "summaryBelow", "summaryRight", "showOutlineSymbols"].contains(
          a.name,
        )
      }) &&
      !flag(node, "applyStyles") else {
      @failure.reject(
        "protected-content", "Extended outline properties require grouping support",
      )
    }
    (
      flag(node, "summaryBelow", fallback=true),
      flag(node, "summaryRight", fallback=true),
    )
  } else {
    (true, true)
  }
}

///|
fn Sheet::outline_axis(
  self : Sheet,
  rows : Bool,
) -> OutlineAxis raise @failure.Failure {
  let tree = Tree::new(self.document)
  let (below, right) = outline_settings(tree)
  let after = if rows { below } else { right }
  let limit = if rows { 1048576 } else { 16384 }
  let bands : Array[(Int, Int, Int)] = []
  let collapsed : Map[Int, Bool] = Map([])
  let items = if rows {
    self.rows
    .iter()
    .map(pair => (pair.0, pair.0, tree.nodes[pair.1]))
    .to_array()
  } else {
    tree
    .one(tree.root("worksheet").id, "cols")
    .map(node => tree.all(node.id, "col"))
    .unwrap_or([])
    .map(node => {
      (
        natural(node.attribute("min").unwrap_or(""), limit),
        natural(node.attribute("max").unwrap_or(""), limit),
        node,
      )
    })
  }
  for (first, last, node) in items {
    let level = natural(node.attribute("outlineLevel").unwrap_or("0"), 7)
    if level > 0 {
      bands.push((first, last, level))
    }
    if flag(node, "collapsed") {
      guard last - first < 4096 else {
        @failure.reject("limit-exceeded", "Outline markers exceed budget")
      }
      for index in first..<=last {
        collapsed[index] = true
      }
    }
  }
  bands.sort_by((a, b) => a.0.compare(b.0))
  let groups : Array[OutlineGroup] = []
  for level in 1..<=7 {
    let intervals : Array[(Int, Int)] = []
    for (first, last, value) in bands {
      if value < level {
        continue
      }
      if intervals.last() is Some((start, end)) && first == end + 1 {
        intervals[intervals.length() - 1] = (start, last)
      } else {
        intervals.push((first, last))
      }
    }
    for (first, last) in intervals {
      let summary = if after { last + 1 } else { first - 1 }
      groups.push({
        first,
        last,
        level,
        summary,
        collapsed: collapsed.contains(summary),
      })
      guard groups.length() <= 1024 else {
        @failure.reject("limit-exceeded", "Outline groups exceed 1024")
      }
    }
  }
  { summary_after: after, limit, bands, collapsed, groups, }
}

///|
fn OutlineAxis::level(self : OutlineAxis, index : Int) -> Int {
  for low = 0, high = self.bands.length(); low < high; {
    let middle = low + (high - low) / 2
    let band = self.bands[middle]
    if index < band.0 {
      continue low, middle
    }
    if index > band.1 {
      continue middle + 1, high
    }
    return band.2
  } nobreak {
    0
  }
}

///|
fn OutlineAxis::json(self : OutlineAxis) -> Json {
  {
    "summaryAfter": self.summary_after,
    "groups": self.groups.map(group => {
      let value : Json = {
        "first": group.first,
        "last": group.last,
        "level": group.level,
        "summary": group.summary,
        "collapsed": group.collapsed,
      }
      value
    }),
  }
}

///|
fn Session::outline_query(self : Session, sheet : Sheet) -> Json {
  {
    "rows": sheet.outline_axis(true).json(),
    "columns": sheet.outline_axis(false).json(),
    "reason": self.dimension_reason(sheet),
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "rows": { "summaryAfter": true, "groups": [] },
        "columns": { "summaryAfter": true, "groups": [] },
        "reason": message,
      }
  }
}
