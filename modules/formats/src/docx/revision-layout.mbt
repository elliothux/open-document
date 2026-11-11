///|
/// Returns read-only review geometry without changing the editing selection or source.
pub fn Session::revision_rects(
  self : Session,
  revision : Int32,
  layout : @layout.Layout,
  id : String,
) -> Array[@layout.SelectionRect] raise @failure.Failure {
  self.check_revision(revision)
  guard layout.revision == revision else {
    @failure.reject(
      "stale-layout", "Revision navigation requires the current layout",
    )
  }
  let tree = WordTree::new(self.document())
  guard tree
    .revision_entries()
    .iter()
    .find_first(entry => entry.node.to_string() == id)
    is Some(entry) &&
    entry.reason.is_empty() &&
    entry.paragraph is Some(paragraph) else {
    @failure.reject("protected-content", "Revision has no supported body range")
  }
  let flow = self.flow()
  if entry.is_table_revision() {
    let paragraphs = tree.revision_table_paragraphs(flow, entry.node)
    return row_revision_rects(paragraphs, layout)
  }
  let paragraphs = flow.paragraphs +
    flow.tables.map(table => table.paragraphs()).flatten()
  let (start, end) = tree.revision_text_range(
    entry,
    paragraphs.iter().find_first(p => p.id == paragraph),
  )
  let mut low = -1
  let mut high : Int32? = None
  for page in layout.pages {
    for line in page.lines {
      if line.paragraph != paragraph || line.repeated {
        continue
      }
      for caret in line.carets {
        if caret.offset <= start {
          low = low.max(caret.offset)
        }
        if caret.offset >= end {
          high = Some(high.unwrap_or(caret.offset).min(caret.offset))
        }
      }
    }
  }
  guard low >= 0 && high is Some(high) else {
    @failure.reject(
      "protected-content", "Revision range has no current layout geometry",
    )
  }
  revision_selection_rects(layout, paragraph, low, high)
}

///|
fn RevisionEntry::is_table_revision(self : RevisionEntry) -> Bool {
  ["rowInsert", "rowDelete", "rowFormat", "tableFormat", "cellFormat"].contains(
    self.kind,
  )
}

///|
fn WordTree::revision_text_range(
  tree : WordTree,
  entry : RevisionEntry,
  paragraph : @layout.Paragraph?,
) -> (Int32, Int32) raise @failure.Failure {
  guard paragraph is Some(p) else {
    @failure.reject(
      "protected-content", "Revision paragraph has no layout content",
    )
  }
  let target = match entry.kind {
    "characterFormat" => tree.nodes[tree.nodes[entry.node].parent].parent
    "paragraphFormat" => p.id
    _ => entry.node
  }
  let target = tree.nodes[target]
  guard p.readOnlyReason.is_empty() ||
    p.readOnlyReason == "Tracked revisions require review before editing" else {
    @failure.reject("protected-content", p.readOnlyReason)
  }
  let mut offset = 0
  let mut start : Int32? = None
  let mut end = 0
  let mut insertion = 0
  for span in p.spans {
    let node = tree.nodes[span.node]
    if target.start <= node.start && node.end <= target.end {
      if start is None {
        start = Some(offset)
      }
      end = offset + span.text.length()
    }
    if node.end <= target.start {
      insertion = offset + span.text.length()
    }
    offset += span.text.length()
  }
  let start = if tree.is_paragraph_revision(entry.node) ||
    (entry.kind == "characterFormat" && target.name == "pPr") {
    offset
  } else {
    start.unwrap_or(insertion)
  }
  (start, end.max(start))
}

///|
fn revision_selection_rects(
  layout : @layout.Layout,
  paragraph : Int32,
  low : Int32,
  high : Int32,
) -> Array[@layout.SelectionRect] raise @failure.Failure {
  let rects = layout
    .selection_rects((paragraph, low, "after"), (paragraph, high, "before"))
    .filter_map(rect => {
      let page = layout.pages[rect.page]
      let x = rect.x.max(0)
      let y = rect.y.max(0)
      let width = (rect.x + rect.width).min(page.width) - x
      let height = (rect.y + rect.height).min(page.height) - y
      if width > 0 && height > 0 {
        Some({ ..rect, x, y, width, height, })
      } else {
        None
      }
    })
  guard rects.length() <= 65536 else {
    @failure.reject(
      "limit-exceeded", "Revision rectangles exceed geometry budget",
    )
  }
  if !rects.is_empty() {
    return rects
  }
  let caret = layout.caret(paragraph, low, "after")
  let page = layout.pages[caret.page]
  let y = caret.y.max(0)
  let height = (caret.y + caret.height).min(page.height) - y
  guard height > 0 && page.width > 0 else {
    @failure.reject("protected-content", "Revision range is outside the page")
  }
  [
    {
      page: caret.page,
      line: caret.line,
      x: caret.x.max(0).min((page.width - 1.5).max(0)),
      y,
      width: 1.5.min(page.width),
      height,
    },
  ]
}
