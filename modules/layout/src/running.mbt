///|
// ONLYOFFICE HeaderFooter.js: first-page selection precedes even-page selection.
fn running_lines(
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
  page~ : Int32 = -1,
  total~ : Int32 = 1,
) -> (Array[PageFrame], Array[PageSetup]) raise @failure.Failure {
  flow.pageNumbering.validate()
  let prepared : Map[String, (PageFrame, Double)] = Map([])
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
      guard story.paragraphs.length() <= 32768 && story.tables.length() <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Running content exceeds paragraph or table budget",
        )
      }
      if story.paragraphs.is_empty() && story.tables.is_empty() {
        continue
      }
      if (variant == "first" && !flow.differentFirst) ||
        (variant == "even" && !flow.differentEven) {
        continue
      }
      let active = flow.pageNumbering.variant(
        page.max(0),
        flow.differentFirst,
        flow.differentEven,
      )
      if page >= 0 && variant != active {
        continue
      }
      let area = Pagination::new(
        { ..flow.page, top: 0, bottom: 0, },
        anchorPage=Some(flow.page),
      )
      let resolved = story.map_paragraphs(paragraph => {
        guard !paragraph.pageBreakBefore && !paragraph_has_break(paragraph) else {
          @failure.reject(
            "unsupported-layout", "Page or column breaks in headers or footers are unsupported",
          )
        }
        {
          ..paragraph,
          spans: paragraph.spans.map(span => {
            guard span.field.is_empty() || span.drawing is None else {
              @failure.reject("unsupported-layout", "Unsupported running field")
            }
            {
              ..span,
              field: "",
              text: if span.field.is_empty() {
                span.text
              } else {
                flow.pageNumbering.field_text(span.field, page.max(0), total)
              },
            }
          }),
        }
      })
      let content = {
        ..flow,
        paragraphs: resolved.paragraphs,
        tables: resolved.tables,
      }
      for table in content.tables; previous = 0 {
        guard table.beforeParagraph >= previous &&
          table.beforeParagraph <= content.paragraphs.length() else {
          @failure.reject("invalid-table", "Invalid running table position")
        }
        table.check_nested()
        continue table.beforeParagraph
      }
      for block in content.body_blocks() {
        block.place(area, cache, probe, profile, images, flow.additiveSpacing)
      }
      guard area.pages.length() == 1 else {
        @failure.reject("layout-overflow", "Header or footer exceeds one page")
      }
      let height = area.y +
        area.after +
        (if story.tables
          .last()
          .map(t => t.beforeParagraph == story.paragraphs.length())
          .unwrap_or(false) {
          0.0
        } else {
          story.paragraphs
          .last()
          .map(p => p.line.terminal_gap(p.nominalSize))
          .unwrap_or(0)
        })
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
        markerImage: line.markerImage.map(image => {
          ..image,
          y: image.y + offset,
        }),
        drawings: line.drawings.map(image => {
          let fixed = match image.anchor {
            Some(
              {
                vertical: Offset("page" | "margin", _)
                | Aligned("page" | "margin", _),
                ..
              },
            ) => true
            _ => false
          }
          { ..image, y: image.y + (if fixed { 0 } else { offset }), }
        }),
        readOnlyReason: "protected-content:running-area",
      })
      prepared[(if footer { "footer" } else { "header" }) + variant] = (
        {
          ..area.pages[0],
          lines,
          borders: area.pages[0].borders.map(b => {
            ..b,
            rect: { ..b.rect, y: b.rect.y + offset, },
          }),
          fills: area.pages[0].fills.map(f => { ..f, y: f.y + offset, }),
          cellAreas: [],
        },
        distance + height,
      )
    }
  }
  let patterns : Array[PageFrame] = []
  let empty : PageFrame = {
    width: flow.page.width,
    height: flow.page.height,
    lines: [],
    borders: [],
    fills: [],
    pageBorders: [],
    cellAreas: [],
  }
  let setups : Array[PageSetup] = []
  for index in (if page >= 0 { [page] } else { [0, 1, 2] }) {
    let variant = flow.pageNumbering.variant(
      index,
      flow.differentFirst,
      flow.differentEven,
    )
    let (header, top) = prepared.get("header" + variant).unwrap_or((empty, 0))
    let (footer, bottom) = prepared
      .get("footer" + variant)
      .unwrap_or((empty, 0))
    let page = {
      ..flow.page,
      top: flow.page.top.max(top),
      bottom: flow.page.bottom.max(bottom),
    }
    page.validate()
    setups.push(page)
    patterns.push({
      ..empty,
      lines: header.lines + footer.lines,
      borders: header.borders + footer.borders,
      fills: header.fills + footer.fills,
    })
  }
  (patterns, setups)
}
