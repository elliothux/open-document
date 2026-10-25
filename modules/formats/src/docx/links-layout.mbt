///|
/// Resolve native body, text box and running links against the completed export layout.
pub fn Session::page_links(
  self : Session,
  layout : @layout.Layout,
) -> Array[@layout.PageLink] raise @failure.Failure {
  self.check_idle()
  guard layout.revision == self.revision else {
    @failure.reject("stale-layout", "Links require the current layout")
  }
  let tree = WordTree::new(self.document())
  let flow = self.flow()
  let paragraphs = flow.paragraphs.copy()
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        paragraphs.append(cell)
      }
    }
  }
  for paragraph in paragraphs.copy() {
    for span in paragraph.spans {
      if span.drawing is Some({ content: @layout.TextBox(_, text), .. }) {
        paragraphs.append(text.paragraphs())
      }
    }
  }
  let running : Map[(Int, Int), String] = Map([])
  let sections = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "sectPr"
  })
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri ||
      !["headerReference", "footerReference"].contains(node.name) {
      continue
    }
    let kind = if node.name == "headerReference" { "header" } else { "footer" }
    let section = sections.search(node.parent).unwrap_or(0)
    let properties = flow.sectionBreaks.get(section - 1)
    let stories = if kind == "header" {
      properties.map(s => s.headers).unwrap_or(flow.headers)
    } else {
      properties.map(s => s.footers).unwrap_or(flow.footers)
    }
    guard stories.get(node.attribute("type", uri=word_uri).unwrap_or(""))
      is Some(story) else {
      continue
    }
    let values = self.running_links(
      Some(self.running_part(tree, id, kind)),
      story,
    )
    for paragraph in story {
      for span in paragraph.spans {
        if values.get(span.node) is Some(target) {
          running[(paragraph.id, span.node)] = target
        }
      }
    }
    paragraphs.append(story)
  }
  let targets : Map[(Int, Int), @layout.LinkTarget] = Map([])
  let drawing_nodes : Map[(Int, Int), Int] = Map([])
  let drawing_sources : Set[(Int, Int)] = Set([])
  let positions : Map[String, @layout.LinkTarget?] = Map([])
  let addresses : Map[Int, String] = Map([])
  let relationships = self.hyperlink_relationships()
  let bookmarks = Map::from_array(
    flow.bookmarks.keys().map(name => (name, true)).to_array(),
  )
  let units = layout.pages
    .iter()
    .fold(init=0, (sum, page) => {
      page.lines
      .iter()
      .fold(init=sum, (sum, line) => {
        line.drawings
        .iter()
        .fold(init=sum + line.carets.length() + 1, (sum, drawing) => {
          drawing
          .text_lines()
          .iter()
          .fold(init=sum, (sum, nested) => sum + nested.carets.length() + 1)
        })
      })
    }) +
    layout.running
    .iter()
    .flat_map(lines => lines.iter())
    .fold(init=0, (sum, line) => sum + line.carets.length() + 1)
  let mut work = 0
  for paragraph in paragraphs {
    for span in paragraph.spans; offset = 0 {
      if span.drawing is Some(_) &&
        paragraph.id >= 0 &&
        tree.nodes[span.node].name == "drawing" {
        drawing_nodes[(paragraph.id, offset)] = span.node
        drawing_sources.add((paragraph.id, span.node))
      }
      continue offset + span.text.length()
    }
    for span in paragraph.spans {
      let key = (paragraph.id, span.node)
      if targets.contains(key) {
        continue
      }
      let drawing_target = if drawing_sources.contains(key) {
        self.drawing_link_target(
          tree,
          span.node,
          links=relationships,
          bookmarks~,
        )
      } else {
        None
      }
      let destination = if span.field.has_prefix("PAGEREF:") ||
        span.field.has_prefix("NOTEREF:") ||
        span.field.has_prefix("REF:") {
        body_field_link(span.field)
      } else if paragraph.id < 0 {
        running.get(key)
      } else if drawing_target is Some(_) {
        drawing_target
      } else if tree.run_hyperlink(tree.nodes[span.node].parent) is Some(id) {
        if !addresses.contains(id) {
          addresses[id] = hyperlink_target(
            tree,
            tree.nodes[span.node].parent,
            relationships,
            bookmarks,
          ).unwrap()
        }
        Some(addresses[id])
      } else {
        None
      }
      guard destination is Some(destination) else { continue }
      let target = if destination.has_prefix("#") {
        let name = destination[1:].to_owned().to_lower()
        if !positions.contains(name) {
          positions[name] = if flow.bookmarks.get(name)
            is Some((paragraph, offset, _, _)) {
            work += units
            guard work <= 8388608 else {
              @failure.reject(
                "limit-exceeded", "Link destinations exceed the work budget",
              )
            }
            let hit = layout.caret(paragraph, offset, "after")
            Some(@layout.Internal(hit.page, hit.x, hit.y))
          } else {
            None
          }
        }
        positions[name]
      } else {
        Some(@layout.External(destination))
      }
      if target is Some(target) {
        targets[key] = target
      }
    }
  }
  let links : Array[@layout.PageLink] = []
  if targets.is_empty() {
    return links
  }
  fn collect(
    page : Int,
    index : Int,
    line : @layout.Line,
    clip : @layout.Border?,
  ) -> Unit raise @failure.Failure {
    let frame = layout.pages[page]
    fn add(
      rect : @layout.Border,
      target : @layout.LinkTarget,
      clip : @layout.Border?,
    ) -> Unit raise @failure.Failure {
      let x = rect.x.max(clip.map(c => c.x).unwrap_or(0)).max(0)
      let y = rect.y.max(clip.map(c => c.y).unwrap_or(0)).max(0)
      let width = (rect.x + rect.width)
        .min(clip.map(c => c.x + c.width).unwrap_or(frame.width))
        .min(frame.width) -
        x
      let height = (rect.y + rect.height)
        .min(clip.map(c => c.y + c.height).unwrap_or(frame.height))
        .min(frame.height) -
        y
      if width <= 0 || height <= 0 {
        return
      }
      guard links.length() < 65536 else {
        @failure.reject(
          "limit-exceeded", "Link rectangles exceed the output budget",
        )
      }
      links.push({ rect: { page, line: index, x, y, width, height, }, target, })
    }
    for drawing in line.drawings {
      if drawing_nodes
        .get((line.paragraph, drawing.start))
        .bind(node => targets.get((line.paragraph, node)))
        is Some(target) {
        let horizontal = if drawing.width == 0 { 3.0 } else { 0.0 }
        let vertical = if drawing.height == 0 { 3.0 } else { 0.0 }
        add(
          {
            x: drawing.x - horizontal,
            y: drawing.y - vertical,
            width: drawing.width + 2 * horizontal,
            height: drawing.height + 2 * vertical,
          },
          target,
          if drawing.anchor is None {
            line.cellClip
          } else {
            None
          },
        )
      }
    }
    for run in line.runs {
      for source in run.sources {
        guard targets.get((line.paragraph, source.node)) is Some(target) else {
          continue
        }
        if drawing_sources.contains((line.paragraph, source.node)) {
          continue
        }
        work += line.carets.length()
        guard work <= 8388608 else {
          @failure.reject(
            "limit-exceeded", "Link geometry exceeds the work budget",
          )
        }
        let start = run.start + source.offset
        for rect in line.link_rects(start, start + source.end - source.start) {
          add(rect, target, clip)
        }
      }
    }
  }
  for page, frame in layout.pages {
    for index, line in layout.running[page] {
      collect(page, index, line, None)
    }
    for index, line in frame.lines {
      collect(page, index, line, None)
      for drawing in line.drawings {
        for nested in drawing.text_lines() {
          collect(
            page,
            index,
            nested,
            if drawing.anchor is None {
              line.cellClip
            } else {
              None
            },
          )
        }
      }
    }
  }
  links
}

///|
fn body_field_link(code : String) -> String? raise @failure.Failure {
  let (bookmark, hyperlink) = if code.has_prefix("PAGEREF:") {
    let reference = @layout.PageReference::parse(code)
    (reference.bookmark, reference.hyperlink)
  } else if code.has_prefix("NOTEREF:") {
    let reference = @layout.NoteReference::parse(code)
    (reference.bookmark, reference.hyperlink)
  } else if code.has_prefix("REF:") {
    let reference = @layout.TextReference::parse(code)
    (reference.bookmark, reference.hyperlink)
  } else {
    return None
  }
  if hyperlink {
    Some("#" + bookmark)
  } else {
    None
  }
}
