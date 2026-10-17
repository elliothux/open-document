///|
/// Resolves read-only annotation geometry from the same layout used by preview and PDF.
pub fn Session::comment_overlays(
  self : Session,
  layout : @layout.Layout,
) -> Json raise @failure.Failure {
  guard layout.revision == self.revision else {
    @failure.reject(
      "stale-layout", "Comment geometry requires the current revision",
    )
  }
  try {
    let source = self.comment_source()
    let entries = source.map(s => s.entries).unwrap_or([])
    let known = Map::from_array(entries.map(e => (e.key, true)))
    let anchors = Map::from_array(
      WordTree::new(self.display_document())
      .comment_anchors()
      .map(a => (a.key, a)),
    )
    guard anchors.keys().all(key => known.contains(key)) else {
      @failure.reject("protected-content", "Comment body is missing")
    }
    let roots = entries.filter(e => e.parent is None && !e.done)
    if roots.is_empty() {
      return { "reason": "", "items": [] }
    }
    let units = layout.pages
      .iter()
      .fold(init=0, (sum, page) => {
        page.lines
        .iter()
        .fold(init=sum, (sum, line) => sum + line.carets.length() + 1)
      })
    guard units <= 8388608 / roots.length() else {
      @failure.reject(
        "limit-exceeded", "Comment geometry exceeds the work budget",
      )
    }
    let mut count = 0
    let items : Array[Json] = []
    for root in roots {
      let rects : Array[@layout.SelectionRect] = []
      let reason = try {
        guard anchors.get(root.key) is Some(anchor) &&
          anchor.reason.is_empty() &&
          anchor.selection is Some(selection) else {
          @failure.reject(
            "protected-content", "Comment has no editable body anchor",
          )
        }
        let start = selection.anchor
        let end = selection.focus
        let selected = layout.selection_rects(
          (start.paragraph, start.offset, start.affinity),
          (end.paragraph, end.offset, end.affinity),
        )
        rects.append(
          selected.filter_map(r => {
            let page = layout.pages[r.page]
            let x = r.x.max(0)
            let y = r.y.max(0)
            let width = (r.x + r.width).min(page.width) - x
            let height = (r.y + r.height).min(page.height) - y
            if width > 0 && height > 0 {
              Some({ ..r, x, y, width, height, })
            } else {
              None
            }
          }),
        )
        if rects.is_empty() {
          let caret = layout.caret(
            start.paragraph,
            start.offset,
            start.affinity,
          )
          guard caret.reason.is_empty() && caret.height > 0 else {
            @failure.reject(
              "protected-content", "Comment anchor has no visible caret",
            )
          }
          let page = layout.pages[caret.page]
          let y = caret.y.max(0)
          let height = (caret.y + caret.height).min(page.height) - y
          guard height > 0 && page.width > 0 else {
            @failure.reject(
              "protected-content", "Comment anchor is outside the page",
            )
          }
          rects.push({
            page: caret.page,
            line: caret.line,
            x: caret.x.max(0).min((page.width - 1.5).max(0)),
            y,
            width: 1.5.min(page.width),
            height,
          })
        }
        ""
      } catch {
        @failure.Failure(message~, ..) => message
      }
      count += rects.length()
      guard count <= 65536 else {
        @failure.reject(
          "limit-exceeded", "Comment rectangles exceed the geometry budget",
        )
      }
      items.push({ "id": root.key, "reason": reason, "rects": rects })
    }
    { "reason": "", "items": items }
  } catch {
    @failure.Failure(message~, ..) => { "reason": message, "items": [] }
  }
}
