///|
priv enum BodyBlock {
  BodyParagraph(Paragraph)
  FramedBlocks(ParagraphFrame, Array[BodyBlock])
  KeptParagraphs(Array[Paragraph], Table?)
  TableStart(Table)
  TableRows(Table, Int32, Int32)
  TableEnd(Table)
}

///|
fn Flow::body_blocks(self : Flow) -> Array[BodyBlock] raise @failure.Failure {
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
      let item = self.tables[table]
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
  keep_next_blocks(framed_blocks(blocks))
}

///|
fn Table::finite_geometry(self : Table) -> Bool {
  self.nestedTables.all(child => {
    child.table.finite_geometry() &&
    child.table.paragraphs().all(p => p.finite_geometry())
  }) &&
  !self.widths.any(value => value.is_nan() || value.is_inf()) &&
  !self.preferredWidth.value.is_nan() &&
  !self.preferredWidth.value.is_inf() &&
  self.preferredWidths.all(row => {
    row.all(width => !width.value.is_nan() && !width.value.is_inf())
  })
}

///|
fn paragraph_keys(
  cache : ParagraphCache,
  paragraphs : ArrayView[Paragraph],
) -> Json? {
  let keys : Array[Json] = []
  for paragraph in paragraphs {
    if cache.version(paragraph) is Some(version) {
      keys.push(Json(version.number))
    } else {
      guard paragraph.finite_geometry() else { return None }
      keys.push(paragraph.to_json())
    }
  }
  Some(Json::array(keys))
}

///|
fn table_row_keys(
  cache : ParagraphCache,
  rows : ArrayView[Array[Array[Paragraph]]],
) -> Json? {
  let keys : Array[Json] = []
  for row in rows {
    let cells : Array[Json] = []
    for cell in row {
      guard paragraph_keys(cache, cell[:]) is Some(key) else { return None }
      cells.push(key)
    }
    keys.push(Json::array(cells))
  }
  Some(Json::array(keys))
}

///|
fn BodyBlock::key(self : BodyBlock, cache : ParagraphCache) -> String? {
  let value : Json = match self {
    FramedBlocks(_, _) => return None
    KeptParagraphs(paragraphs, table) => {
      guard paragraph_keys(cache, paragraphs[:]) is Some(keys) else {
        return None
      }
      let following = if table is Some(table) {
        guard TableStart(table).key(cache) is Some(start) &&
          TableRows(table, 0, table.row_group_end(0)).key(cache) is Some(rows) else {
          return None
        }
        Json::array([Json(start), Json(rows)])
      } else {
        Json::null()
      }
      Json::array([Json("kept-paragraphs"), keys, following])
    }
    BodyParagraph(paragraph) => {
      if cache.version(paragraph) is Some(version) {
        return Some("paragraph-version:\{version.number}")
      }
      guard paragraph.finite_geometry() else { return None }
      Json::array([Json("paragraph"), paragraph.to_json()])
    }
    TableStart(table) => {
      guard table.finite_geometry() else { return None }
      let fields = {
        "id": Json(table.id),
        "autoFit": Json(table.autoFit),
        "preferredWidth": Json(table.preferredWidth),
        "preferredWidths": Json(table.preferredWidths),
        "headerRows": Json(table.headerRows),
        "legacyCellAlignment": Json(table.legacyCellAlignment),
        "widths": Json(table.widths),
        "align": Json(table.align),
        "borders": Json(table.borders),
      }
      if table.autoFit {
        guard table_row_keys(cache, table.rows[:]) is Some(keys) else {
          return None
        }
        fields["rows"] = keys
        fields["nestedTables"] = Json(table.nestedTables)
      }
      Json::array([Json("table-start"), Json::object(fields)])
    }
    TableRows(table, row, end) => {
      guard table.finite_geometry() &&
        table.heights[row:end + 1]
        .iter()
        .all(height => !height.is_nan() && !height.is_inf()) else {
        return None
      }
      guard table_row_keys(cache, table.rows[row:end + 1]) is Some(keys) else {
        return None
      }
      let headers = if table.headerRows == 0 {
        Json::null()
      } else {
        guard table_row_keys(cache, table.rows[:table.headerRows]) is Some(keys) else {
          return None
        }
        Json::array([
          keys,
          Json(table.heights[:table.headerRows].to_owned()),
          Json(table.exactHeights[:table.headerRows].to_owned()),
          Json(table.splitRows[:table.headerRows].to_owned()),
          Json(table.margins[:table.headerRows].to_owned()),
          Json(table.fills[:table.headerRows].to_owned()),
          Json(table.verticalAligns[:table.headerRows].to_owned()),
          Json(table.columnSpans[:table.headerRows].to_owned()),
          Json(table.rowSpans[:table.headerRows].to_owned()),
        ])
      }
      Json::array([
        Json("table-row"),
        Json(table.id),
        Json(
          table.nestedTables.filter(child => {
            (child.row >= row && child.row <= end) ||
            child.row < table.headerRows
          }),
        ),
        Json(table.widths),
        Json(table.align),
        Json(table.legacyCellAlignment),
        Json(table.borders),
        Json(table.headerRows),
        headers,
        Json(table.margins[row:end + 1].to_owned()),
        keys,
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
    FramedBlocks(frame, blocks) =>
      pagination.paragraph_frame(
        frame, blocks, cache, probe, profile, images, additive,
      )
    KeptParagraphs(paragraphs, table) =>
      pagination.kept_paragraphs(
        cache, probe, paragraphs, table, profile, images, additive,
      )
    BodyParagraph(paragraph) =>
      pagination.paragraph(cache, probe, paragraph, profile, images, additive)
    TableStart(table) => {
      pagination.y += pagination.after + pagination.gap
      pagination.after = 0
      pagination.gap = 0
      pagination.prepare_table(table, cache, probe, profile, additive)
    }
    TableRows(table, row, end) =>
      pagination.table_rows(
        cache,
        probe,
        pagination.tables.get(table.id).unwrap_or(table),
        row,
        end,
        profile,
        images,
        additive,
      )
    TableEnd(table) => {
      pagination.y += table.border_width(table.rows.length())
      pagination.active_table = None
    }
  }
}

///|
fn pagination_keys(
  blocks : Array[BodyBlock],
  cache : ParagraphCache,
) -> Array[String]? {
  guard blocks.length() <= 1024 else { return None }
  let keys = []
  let mut units = 0
  for block in blocks {
    guard block.key(cache) is Some(key) else { return None }
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
  tables : Map[Int32, Table],
) -> Unit raise @failure.Failure {
  match self {
    KeptParagraphs(paragraphs, _) =>
      for paragraph in paragraphs {
        cache.retain(paragraph, page.width - page.left - page.right)
      }
    BodyParagraph(paragraph) =>
      cache.retain(paragraph, page.width - page.left - page.right)
    TableRows(original, first, last) => {
      let table = tables.get(original.id).unwrap_or(original)
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
              inTable=true,
            )
          }
        }
      }
    }
    _ => ()
  }
}
