///|
fn page_area_for_position(
  flow : @layout.Flow,
  position : Position,
) -> (@layout.PageSetup, @layout.Columns) raise @failure.Failure {
  if flow.sectionBreaks.is_empty() {
    return (flow.page, flow.columns)
  }
  let location = for index, paragraph in flow.paragraphs {
    if paragraph.id == position.paragraph {
      break (index, false)
    }
  } nobreak {
    for index, table in flow.tables {
      if table.rows.any(row => {
          row.any(cell => cell.any(p => p.id == position.paragraph))
        }) {
        break (index, true)
      }
    } nobreak {
      @failure.reject("invalid-position", "Position has no page section")
    }
  }
  for section in flow.sectionBreaks; area = (flow.page, flow.columns) {
    let start = if location.1 {
      section.beforeTable
    } else {
      section.beforeParagraph
    }
    if location.0 < start {
      break area
    }
    continue (section.page, section.columns)
  } nobreak {
    area
  }
}

///|
fn column_width_in(
  flow : @layout.Flow,
  layout : @layout.Layout,
  position : Position,
) -> Double raise @failure.Failure {
  guard layout.revision == flow.revision else {
    @failure.reject("stale-layout", "Column geometry is stale")
  }
  let (area, columns) = page_area_for_position(flow, position)
  if position.frameStart is Some(start) {
    for page in layout.pages {
      for line in page.lines {
        if line.paragraph == position.paragraph &&
          !line.repeated &&
          line.start == start &&
          line.start <= position.offset &&
          position.offset <= line.end {
          return columns.width_at(area, line.areaX)
        }
      }
    }
  }
  let mut previous : Double? = None
  for page in layout.pages {
    for line in page.lines {
      if line.paragraph == position.paragraph &&
        !line.repeated &&
        line.start <= position.offset &&
        position.offset <= line.end {
        if position.offset < line.end ||
          position.affinity == "before" ||
          line.start == line.end {
          return columns.width_at(area, line.areaX)
        }
        previous = Some(line.areaX)
      }
    }
  }
  if previous is Some(x) {
    return columns.width_at(area, x)
  }
  @failure.reject("invalid-position", "Column position has no layout")
}

///|
fn table_start_position(
  table : @layout.Table,
) -> Position raise @failure.Failure {
  guard table.rows.get(0).bind(row => row.get(0)).bind(cell => cell.get(0))
    is Some(paragraph) else {
    @failure.reject("protected-content", "Table start has no paragraph")
  }
  {
    paragraph: paragraph.id,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
}

///|
fn column_width_for_position(
  flow : @layout.Flow,
  position : Position,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Double raise @failure.Failure {
  let (page, columns) = page_area_for_position(flow, position)
  if columns.custom.is_empty() {
    return columns.width(page)
  }
  guard probe is Some(probe) else {
    @failure.reject("missing-font", "Column placement requires a text probe")
  }
  column_width_in(
    flow,
    @layout.paginate(
      probe,
      flow,
      profile,
      images.unwrap_or_else(() => @layout.Images::new()),
    ),
    position,
  )
}

///|
fn table_column_width(
  flow : @layout.Flow,
  table : @layout.Table,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Double raise @failure.Failure {
  column_width_for_position(
    flow,
    table_start_position(table),
    probe,
    profile,
    images,
  )
}
