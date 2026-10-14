///|
priv enum BodyBlock {
  BodyParagraph(Paragraph)
  TableStart(Table)
  TableRow(Table, Int)
  TableEnd(Table)
}

///|
fn Flow::body_blocks(self : Flow) -> Array[BodyBlock] {
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
      blocks.push(TableStart(item))
      for row in 0..<item.rows.length() {
        blocks.push(TableRow(item, row))
      }
      blocks.push(TableEnd(item))
      table += 1
    }
  }
  blocks
}

///|
fn Table::finite_geometry(self : Table) -> Bool {
  ![self.padding, self.verticalPadding, ..self.widths].any(value => {
    value.is_nan() || value.is_inf()
  })
}

///|
fn BodyBlock::key(self : BodyBlock) -> String? {
  let value : Json = match self {
    BodyParagraph(paragraph) => {
      guard paragraph.finite_geometry() else { return None }
      Json::array(["paragraph".to_json(), paragraph.to_json()])
    }
    TableStart(table) => {
      guard table.finite_geometry() else { return None }
      let value = table.to_json()
      if value is Object(fields) {
        for key in ["beforeParagraph", "rows", "heights", "fills"] {
          fields.remove(key)
        }
      }
      Json::array(["table-start".to_json(), value])
    }
    TableRow(table, row) => {
      guard table.finite_geometry() &&
        table.rows[row].all(cell => cell.all(p => p.finite_geometry())) &&
        table.heights.get(row) is Some(height) &&
        !height.is_nan() &&
        !height.is_inf() else {
        return None
      }
      Json::array([
        "table-row".to_json(),
        table.id.to_json(),
        table.widths.to_json(),
        table.align.to_json(),
        table.borders.to_json(),
        table.padding.to_json(),
        table.verticalPadding.to_json(),
        table.rows[row].to_json(),
        table.heights.get(row).to_json(),
        table.fills.get(row).to_json(),
      ])
    }
    TableEnd(table) =>
      Json::array([
        "table-end".to_json(),
        table.id.to_json(),
        table.borders.to_json(),
      ])
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
    TableRow(table, row) =>
      pagination.table_row(cache, probe, table, row, profile, images, additive)
    TableEnd(table) => if table.borders { pagination.y += 0.5 }
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
    TableRow(table, row) =>
      for column, cell in table.rows[row] {
        for paragraph in cell {
          cache.retain(paragraph, table.widths[column] - table.padding * 2)
        }
      }
    _ => ()
  }
}
