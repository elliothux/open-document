///|
priv enum BodyBlock {
  BodyParagraph(Paragraph)
  TableStart(Table)
  TableRows(Table, Int, Int)
  TableEnd(Table)
}

///|
fn Flow::body_blocks(
  self : Flow,
  probe : TextProbe,
  profile : Map[String, String],
) -> Array[BodyBlock] raise @failure.Failure {
  let blocks : Array[BodyBlock] = []
  let mut paragraph = 0
  let mut table = 0
  while paragraph < self.paragraphs.length() || table < self.tables.length() {
    if paragraph < self.paragraphs.length() &&
      (
        table == self.tables.length() ||
        paragraph < self.tables[table].beforeParagraph
      ) {
      blocks.push(BodyParagraph(self.paragraphs[paragraph]))
      paragraph += 1
    } else {
      let item = self.tables[table].fit_widths(
        probe,
        profile,
        self.page.width - self.page.left - self.page.right,
      )
      item.check_grid()
      blocks.push(TableStart(item))
      let mut row = 0
      while row < item.rows.length() {
        let end = item.row_group_end(row)
        blocks.push(TableRows(item, row, end))
        row = end + 1
      }
      blocks.push(TableEnd(item))
      table += 1
    }
  }
  blocks
}

///|
fn Table::finite_geometry(self : Table) -> Bool {
  !self.widths.any(value => value.is_nan() || value.is_inf())
}

///|
fn BodyBlock::key(self : BodyBlock) -> String? {
  let value : Json = match self {
    BodyParagraph(paragraph) => {
      guard paragraph.finite_geometry() else { return None }
      Json::array([Json("paragraph"), paragraph.to_json()])
    }
    TableStart(table) => {
      guard table.finite_geometry() else { return None }
      let value = table.to_json()
      if value is Object(fields) {
        for
          key in [
            "beforeParagraph", "rows", "heights", "fills", "columnSpans", "rowSpans",
            "verticalAligns", "margins", "exactHeights", "splitRows",
          ] {
          fields.remove(key)
        }
      }
      Json::array([Json("table-start"), value])
    }
    TableRows(table, row, end) => {
      guard table.finite_geometry() &&
        table.rows[row:end + 1]
        .iter()
        .all(row => row.all(cell => cell.all(p => p.finite_geometry()))) &&
        table.heights[row:end + 1]
        .iter()
        .all(height => !height.is_nan() && !height.is_inf()) else {
        return None
      }
      Json::array([
        Json("table-row"),
        Json(table.id),
        Json(table.widths),
        Json(table.align),
        Json(table.borders),
        Json(table.headerRows),
        if table.headerRows == 0 {
          Json::null()
        } else {
          Json::array([
            Json(table.rows[:table.headerRows].to_owned()),
            Json(table.heights[:table.headerRows].to_owned()),
            Json(table.exactHeights[:table.headerRows].to_owned()),
            Json(table.splitRows[:table.headerRows].to_owned()),
            Json(table.margins[:table.headerRows].to_owned()),
            Json(table.fills[:table.headerRows].to_owned()),
            Json(table.verticalAligns[:table.headerRows].to_owned()),
            Json(table.columnSpans[:table.headerRows].to_owned()),
            Json(table.rowSpans[:table.headerRows].to_owned()),
          ])
        },
        Json(table.margins[row:end + 1].to_owned()),
        Json(table.rows[row:end + 1].to_owned()),
        Json(table.heights[row:end + 1].to_owned()),
        Json(table.exactHeights[row:end + 1].to_owned()),
        Json(table.splitRows[row:end + 1].to_owned()),
        Json(table.fills[row:end + 1].to_owned()),
        Json(table.verticalAligns[row:end + 1].to_owned()),
        Json(table.columnSpans[row:end + 1].to_owned()),
        Json(table.rowSpans[row:end + 1].to_owned()),
      ])
    }
    TableEnd(table) =>
      Json::array([Json("table-end"), Json(table.id), Json(table.borders)])
  }
  Some(value.stringify())
}

///|
fn BodyBlock::place(
  self : BodyBlock,
  pagination : Pagination,
  cache : ParagraphCache,
  probe : TextProbe,
  profile : Map[String, String],
  images : Images,
  additive : Bool,
) -> Unit raise @failure.Failure {
  match self {
    BodyParagraph(paragraph) =>
      pagination.paragraph(cache, probe, paragraph, profile, images, additive)
    TableStart(table) => {
      pagination.y += pagination.after + pagination.gap
      pagination.after = 0
      pagination.gap = 0
      ignore(table.left(pagination.page))
    }
    TableRows(table, row, end) =>
      pagination.table_rows(
        cache, probe, table, row, end, profile, images, additive,
      )
    TableEnd(table) => pagination.y += table.border_width(table.rows.length())
  }
}

///|
fn pagination_keys(blocks : Array[BodyBlock]) -> Array[String]? {
  guard blocks.length() <= 1024 else { return None }
  let keys = []
  let mut units = 0
  for block in blocks {
    guard block.key() is Some(key) else { return None }
    guard key.length() <= 1048576 - units else { return None }
    units += key.length()
    keys.push(key)
  }
  Some(keys)
}

///|
fn BodyBlock::retain(
  self : BodyBlock,
  cache : ParagraphCache,
  page : PageSetup,
) -> Unit {
  match self {
    BodyParagraph(paragraph) =>
      cache.retain(paragraph, page.width - page.left - page.right)
    TableRows(table, first, last) =>
      for row in first..<=last {
        for column, cell in table.rows[row] {
          if table.rowSpans[row][column] == 0 {
            continue
          }
          let insets = table.cell_insets(row, column)
          for paragraph in cell {
            cache.retain(
              paragraph,
              table.cell_width(row, column) - insets.left - insets.right,
            )
          }
        }
      }
    _ => ()
  }
}
