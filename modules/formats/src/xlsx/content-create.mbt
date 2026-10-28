///|
pub(all) struct ContentCell {
  row : Int32
  column : Int32
  rowSpan : Int32
  columnSpan : Int32
  text : String
  numeric : Bool
  font : String
  size : Double
  color : String
  bold : Bool
  italic : Bool
  fill : String
}

///|
pub(all) struct ContentSheet {
  name : String
  widths : Array[Double]
  heights : Array[Double]
  cells : Array[ContentCell]
}

///|
/// Build typed native cells in batches. Text is never interpreted as a formula.
pub fn Session::create_content(
  tables : Array[ContentSheet],
  budget : @archive.Budget,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Session raise @failure.Failure {
  guard !tables.is_empty() && tables.length() <= 32 else {
    @failure.reject(
      "limit-exceeded", "Imported workbook requires 1 to 32 tables",
    )
  }
  let session = Session::create(budget)
  errdefer session.close()
  let digit = session.digit_width(probe, profile)
  let edge : CellBorder = { style: "thin", color: "000000", }
  for index, table in tables {
    let rows = table.heights.length()
    let columns = table.widths.length()
    guard rows > 0 &&
      columns > 0 &&
      rows <= 256 &&
      columns <= 63 &&
      rows * columns <= 4096 else {
      @failure.reject(
        "limit-exceeded", "Imported worksheet exceeds table limits",
      )
    }
    if index > 0 {
      ignore(session.edit_sheet(session.revision, session.selection.0, Add))
    }
    let sheet = session.selection.0
    ignore(session.edit_sheet(session.revision, sheet, Rename(table.name)))
    let values : Array[Array[String]] = Array::makei(rows, _ => {
      Array::make(columns, "")
    })
    let styles : Array[Array[CellFormat]] = Array::makei(rows, _ => {
      Array::makei(columns, _ => CellFormat::new())
    })
    let owners = Array::make(rows * columns, -1)
    let mut mergeCount = 0
    for cellIndex, cell in table.cells {
      guard cell.row >= 0 &&
        cell.column >= 0 &&
        cell.rowSpan > 0 &&
        cell.columnSpan > 0 &&
        cell.row + cell.rowSpan <= rows &&
        cell.column + cell.columnSpan <= columns else {
        @failure.reject(
          "invalid-operation", "Imported cell spans exceed table dimensions",
        )
      }
      if cell.rowSpan > 1 || cell.columnSpan > 1 {
        mergeCount += 1
      }
      if cell.numeric {
        let number = @string.parse_double(cell.text[:]) catch {
          _ =>
            @failure.reject(
              "invalid-operation", "Imported numeric cell is not a number",
            )
        }
        guard !number.is_inf() && !number.is_nan() else {
          @failure.reject(
            "invalid-operation", "Imported numeric cell is not finite",
          )
        }
      }
      values[cell.row][cell.column] = if cell.text.is_empty() {
        ""
      } else if cell.numeric {
        cell.text
      } else {
        "'" + cell.text
      }
      let style = CellFormat::new(
        family=Some(cell.font),
        size=Some(cell.size),
        color=Some(cell.color),
        fill=Some(cell.fill),
        bold=Some(cell.bold),
        italic=Some(cell.italic),
        underline=Some(false),
        strike=Some(false),
        script=Some("baseline"),
        horizontal=Some("general"),
        wrap=Some(true),
        shrinkToFit=Some(false),
        indent=Some(0),
        textRotation=Some(0),
        locked=Some(true),
        formulaHidden=Some(false),
        vertical=Some("top"),
        numberFormat=Some(if cell.numeric { "General" } else { "@" }),
        left=Some(edge),
        right=Some(edge),
        top=Some(edge),
        bottom=Some(edge),
      )
      for row in cell.row..<(cell.row + cell.rowSpan) {
        for column in cell.column..<(cell.column + cell.columnSpan) {
          let slot = row * columns + column
          guard owners[slot] == -1 else {
            @failure.reject("invalid-operation", "Imported cell spans overlap")
          }
          owners[slot] = cellIndex
          styles[row][column] = style
        }
      }
    }
    guard owners.all(owner => owner >= 0) && mergeCount <= 128 else {
      @failure.reject(
        "limit-exceeded", "Imported table has gaps or too many merged regions",
      )
    }
    let end = Address::name({ row: rows, column: columns, })
    ignore(session.replace(session.revision, sheet, "A1:" + end, values))
    ignore(session.select(session.revision, sheet, "A1:" + end))
    ignore(session.apply_format(session.revision, styles, []))
    for cell in table.cells {
      if cell.rowSpan > 1 || cell.columnSpan > 1 {
        let start = Address::name({
          row: cell.row + 1,
          column: cell.column + 1,
        })
        let end = Address::name({
          row: cell.row + cell.rowSpan,
          column: cell.column + cell.columnSpan,
        })
        ignore(
          session.edit_sheet(
            session.revision,
            sheet,
            Merge(start + ":" + end, true),
          ),
        )
      }
    }
    for column, width in table.widths {
      guard width > 0 && width <= 14400 else {
        @failure.reject("invalid-transform", "Imported column width is invalid")
      }
      ignore(
        session.edit_sheet(
          session.revision,
          sheet,
          ColumnWidth(
            column + 1,
            column + 1,
            ((width / 0.75 - 5) / digit).max(1).min(255),
          ),
        ),
      )
    }
    for row, height in table.heights {
      guard height > 0 && height <= 14400 else {
        @failure.reject("invalid-transform", "Imported row height is invalid")
      }
      ignore(
        session.edit_sheet(
          session.revision,
          sheet,
          RowHeight(row + 1, row + 1, height.min(409.5)),
        ),
      )
    }
  }
  session
}
