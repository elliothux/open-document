///|
/// Resolve native body links against the exact completed export layout.
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
  let targets : Map[Int, @layout.LinkTarget] = Map([])
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
      .fold(init=sum, (sum, line) => sum + line.carets.length() + 1)
    })
  let mut work = 0
  for paragraph in paragraphs {
    for span in paragraph.spans {
      if targets.contains(span.node) {
        continue
      }
      let destination = if span.field.has_prefix("PAGEREF:") {
        let reference = @layout.PageReference::parse(span.field)
        if reference.hyperlink {
          Some("#" + reference.bookmark)
        } else {
          None
        }
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
            is Some((paragraph, offset)) {
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
        targets[span.node] = target
      }
    }
  }
  let links : Array[@layout.PageLink] = []
  if targets.is_empty() {
    return links
  }
  for page, frame in layout.pages {
    for index, line in frame.lines {
      for run in line.runs {
        for source in run.sources {
          guard targets.get(source.node) is Some(target) else { continue }
          work += line.carets.length()
          guard work <= 8388608 else {
            @failure.reject(
              "limit-exceeded", "Link geometry exceeds the work budget",
            )
          }
          let start = run.start + source.offset
          for rect in line.link_rects(start, start + source.end - source.start) {
            let x = rect.x.max(0)
            let y = rect.y.max(0)
            let width = (rect.x + rect.width).min(frame.width) - x
            let height = (rect.y + rect.height).min(frame.height) - y
            if width <= 0 || height <= 0 {
              continue
            }
            guard links.length() < 65536 else {
              @failure.reject(
                "limit-exceeded", "Link rectangles exceed the output budget",
              )
            }
            links.push({
              rect: { page, line: index, x, y, width, height, },
              target,
            })
          }
        }
      }
    }
  }
  links
}
