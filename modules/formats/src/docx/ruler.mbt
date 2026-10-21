///|
priv struct RulerContext {
  selection : Selection
  paragraph : @layout.Paragraph
  page : Int
  width : Double
  origin : Double
  extent : Double
  direction : Double
  pageLeft : Double
  pageRight : Double
}

///|
fn ruler_twips(value : Double) -> Double {
  (value * 20).round() / 20
}

///|
fn Session::ruler_context(
  self : Session,
  revision : Int,
  layout : @layout.Layout,
) -> RulerContext raise @failure.Failure {
  self.check_revision(revision)
  guard layout.revision == revision else {
    @failure.reject("stale-layout", "Ruler requires the current layout")
  }
  guard self.selection is Some(selection) else {
    @failure.reject(
      "invalid-position", "Select a paragraph before using the ruler",
    )
  }
  let focus = selection.focus
  self.check_position(focus)
  let hit = layout.caret(
    focus.paragraph,
    focus.offset,
    focus.affinity,
    bidi_level?=focus.bidiLevel,
    frame_start?=focus.frameStart,
  )
  let tree = WordTree::new(self.display_document())
  let (area_x, area_width) = if tree.text_box_drawing(focus.paragraph)
    is Some(_) {
    let line = layout.semantics()[hit.page].lines
      .iter()
      .find_first(line => {
        line.paragraph == focus.paragraph &&
        line.start <= focus.offset &&
        line.end >= focus.offset &&
        hit.y >= line.y &&
        hit.y < line.y + line.height
      })
      .unwrap_or_error(
        @failure.Failure(
          code="invalid-position",
          part="",
          offset=focus.paragraph,
          message="Ruler line is unavailable",
        ),
      )
    (line.areaX, line.areaWidth)
  } else {
    let line = layout.pages[hit.page].lines[hit.line]
    (line.areaX, line.areaWidth)
  }
  let flow = self.flow()
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        for paragraph in cell {
          paragraphs.push(paragraph)
        }
      }
    }
  }
  let nested = paragraphs
    .iter()
    .flat_map(p => p.spans.iter())
    .flat_map(span => {
      match span.drawing {
        Some({ content: @layout.TextBox(_, text), .. }) =>
          text.paragraphs().iter()
        _ => [].iter()
      }
    })
    .collect()
  paragraphs.append(nested)
  let mut found : @layout.Paragraph? = None
  for paragraph in paragraphs {
    if paragraph.id == focus.paragraph {
      found = Some(paragraph)
      break
    }
  }
  guard found is Some(paragraph) else {
    @failure.reject("invalid-position", "Ruler paragraph is unavailable")
  }
  {
    selection,
    paragraph,
    page: hit.page,
    width: layout.pages[hit.page].width,
    origin: area_x + (if paragraph.rtl { area_width } else { 0 }),
    extent: area_width,
    direction: if paragraph.rtl {
      -1
    } else {
      1
    },
    pageLeft: flow.page.left,
    pageRight: flow.page.width - flow.page.right,
  }
}

///|
pub fn Session::ruler(
  self : Session,
  revision : Int,
  layout : @layout.Layout,
) -> Json raise @failure.Failure {
  let context = self.ruler_context(revision, layout)
  let p = context.paragraph
  let markers : Array[Json] = []
  for
    (kind, value) in [
      ("first", p.left + p.first),
      ("hanging", p.left),
      ("left", p.left),
      ("right", context.extent - p.right),
    ] {
    markers.push({
      "kind": kind,
      "position": context.origin + context.direction * value,
      "index": -1,
      "align": "",
      "leader": "",
    })
  }
  for index, stop in p.tabs {
    markers.push({
      "kind": "tab",
      "position": context.origin + context.direction * stop.position,
      "index": index,
      "align": stop.align,
      "leader": stop.leader,
    })
  }
  let page = self.page_setup(revision)
  if page is { "reason": String(""), .. } {
    for
      (kind, position) in [
        ("marginLeft", context.pageLeft),
        ("marginRight", context.pageRight),
      ] {
      markers.push({
        "kind": kind,
        "position": position,
        "index": -1,
        "align": "",
        "leader": "",
      })
    }
  }
  let formatting = self.query_formatting(revision, context.selection)
  let reason = match formatting {
    { "reason": String(reason), .. } => reason
    _ => "Ruler formatting is unavailable"
  }
  {
    "revision": revision,
    "selection": context.selection,
    "page": context.page,
    "width": context.width,
    "origin": context.origin,
    "extent": context.extent,
    "rtl": p.rtl,
    "markers": markers,
    "reason": reason,
  }
}

///|
pub(all) enum RulerEdit {
  RulerIndent(String, Double, Bool)
  RulerMargin(String, Double, Bool)
  RulerTab(Int, Double, String, Bool, Bool)
}

///|
/// Applies one physical ruler position through the existing format or page transaction.
pub fn Session::edit_ruler(
  self : Session,
  revision : Int,
  layout : @layout.Layout,
  selection : Selection,
  change : RulerEdit,
) -> Json raise @failure.Failure {
  let context = self.ruler_context(revision, layout)
  guard context.selection.to_json() == selection.to_json() else {
    @failure.reject(
      "stale-selection", "Selection changed during ruler interaction",
    )
  }
  let (position, snap, step) = match change {
    RulerIndent(_, position, snap) | RulerMargin(_, position, snap) =>
      (position, snap, 4.5)
    RulerTab(_, position, _, _, snap) => (position, snap, 3.0)
  }
  guard !position.is_nan() && !position.is_inf() && position.abs() <= 14400 else {
    @failure.reject("invalid-operation", "Invalid ruler coordinate")
  }
  let step = if snap { step } else { 0.05 }
  let physical = position.max(0).min(context.width)
  let position = ((physical / step).round() * step).max(0).min(context.width)
  let target = ((context.direction * (physical - context.origin) / step).round() *
    step *
    20).round() /
    20
  let p = context.paragraph
  match change {
    RulerMargin(kind, _, _) => {
      let tree = WordTree::new(self.document())
      let section = self.editable_page_section(tree)
      let page = match section {
        Some(id) => tree.page_values(id, default_page_setup())
        None => default_page_setup()
      }
      let page = match kind {
        "marginLeft" =>
          {
            ..page,
            left: ruler_twips(position.min((context.pageRight - 12).max(0))),
          }
        "marginRight" =>
          {
            ..page,
            right: ruler_twips(
              (context.width - position.max(context.pageLeft + 12)).max(0),
            ),
          }
        _ => @failure.reject("invalid-operation", "Unknown ruler margin")
      }
      self.set_page_setup(revision, page)
    }
    RulerIndent(kind, _, _) => {
      let low = if p.rtl {
        context.origin - context.width
      } else {
        -context.origin
      }
      let end = context.extent - p.right
      let patch = match kind {
        "first" =>
          ParagraphFormat::new(
            first=Set(
              ruler_twips(
                (target.max(low).min(end - 4.5) - p.left).max(-1584).min(1584),
              ),
            ),
          )
        "hanging" => {
          let left = ruler_twips(
            target.max(low).max(0).min(end - 4.5).min(1584),
          )
          ParagraphFormat::new(
            left=Set(left),
            first=Set(ruler_twips(p.left + p.first - left)),
          )
        }
        "left" =>
          ParagraphFormat::new(
            left=Set(
              ruler_twips(
                target
                .max(low - p.first.min(0))
                .max(0)
                .min(end - 4.5 - p.first.max(0))
                .min(1584),
              ),
            ),
          )
        "right" => {
          let right = ((
              context.extent - context.direction * (physical - context.origin)
            ) /
            step).round() *
            step
          ParagraphFormat::new(
            right=Set(
              ruler_twips(
                right
                .max(0)
                .min(
                  (context.extent - p.left.max(p.left + p.first) - 4.5).max(0),
                )
                .min(1584),
              ),
            ),
          )
        }
        _ => @failure.reject("invalid-operation", "Unknown ruler indent")
      }
      self.set_paragraph_format(revision, selection, patch)
    }
    RulerTab(index, _, align, remove, _) => {
      guard index >= -1 &&
        index < p.tabs.length() &&
        ["left", "right", "center", "decimal", "bar"].contains(align) &&
        (!remove || index >= 0) else {
        @failure.reject("invalid-operation", "Invalid ruler tab stop")
      }
      let target = ruler_twips(target.max(0).min(context.extent.min(1584)))
      let stops : Array[@layout.TabStop] = []
      for i, stop in p.tabs {
        if i != index {
          stops.push(stop)
        }
      }
      if !remove {
        guard !stops.any(stop => (stop.position - target).abs() < 0.025) else {
          @failure.reject(
            "invalid-operation", "A tab stop already occupies this position",
          )
        }
        let leader = if index >= 0 { p.tabs[index].leader } else { "none" }
        stops.push({ position: target, align, leader, })
        stops.sort_by((a, b) => a.position.compare(b.position))
      }
      self.set_paragraph_format(
        revision,
        selection,
        ParagraphFormat::new(tabs=Set(stops)),
      )
    }
  }
}
