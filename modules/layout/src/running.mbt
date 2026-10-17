///|
// ONLYOFFICE HeaderFooter.js: first-page selection precedes even-page selection.
fn running_lines(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> (Array[Array[Line]], Array[PageSetup]) raise @failure.Failure {
  let prepared : Map[String, (Array[Line], Double)] = Map([])
  for
    (stories, distance, footer) in [
      (flow.headers, flow.headerDistance, false),
      (flow.footers, flow.footerDistance, true),
    ] {
    guard distance >= 0 &&
      distance <= flow.page.height &&
      stories.keys().all(key => ["default", "first", "even"].contains(key)) else {
      @failure.reject(
        "invalid-style", "Invalid running area distance or variant",
      )
    }
    for variant, story in stories {
      if (variant == "first" && !flow.differentFirst) ||
        (variant == "even" && !flow.differentEven) {
        continue
      }
      let area = Pagination::new({ ..flow.page, top: 0, bottom: 0, })
      for paragraph in story {
        guard !paragraph.pageBreakBefore &&
          paragraph.spans.all(span => !span.text.contains("\u000c")) else {
          @failure.reject(
            "unsupported-layout", "Page breaks in headers or footers are unsupported",
          )
        }
        area.paragraph(
          cache,
          probe,
          paragraph,
          profile,
          images,
          flow.additiveSpacing,
        )
      }
      guard area.pages.length() == 1 else {
        @failure.reject("layout-overflow", "Header or footer exceeds one page")
      }
      let height = area.y +
        area.after +
        story.last().map(p => p.line.terminal_gap(p.nominalSize)).unwrap_or(0)
      let offset = if footer {
        flow.page.height - distance - height
      } else {
        distance
      }
      let lines = area.pages[0].lines.map(line => {
        ..line.copy_geometry(),
        container: if footer {
          -2
        } else {
          -1
        },
        y: line.y + offset,
        runs: line.runs.map(run => {
          ..run.copy_geometry(),
          baseline: run.baseline + offset,
        }),
        marker: line.marker.map(run => {
          ..run.copy_geometry(),
          baseline: run.baseline + offset,
        }),
        images: line.images.map(image => { ..image, y: image.y + offset, }),
        readOnlyReason: "protected-content:running-area",
      })
      prepared[(if footer { "footer" } else { "header" }) + variant] = (
        lines,
        distance + height,
      )
    }
  }
  let patterns : Array[Array[Line]] = []
  let setups : Array[PageSetup] = []
  for index in 0..<3 {
    let variant = if index == 0 && flow.differentFirst {
      "first"
    } else if index == 1 && flow.differentEven {
      "even"
    } else {
      "default"
    }
    let (header, top) = prepared.get("header" + variant).unwrap_or(([], 0))
    let (footer, bottom) = prepared.get("footer" + variant).unwrap_or(([], 0))
    let page = {
      ..flow.page,
      top: flow.page.top.max(top),
      bottom: flow.page.bottom.max(bottom),
    }
    page.validate()
    setups.push(page)
    patterns.push(header + footer)
  }
  (patterns, setups)
}
