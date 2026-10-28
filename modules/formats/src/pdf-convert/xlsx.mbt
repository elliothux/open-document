///|
fn write_xlsx(
  pages : Array[Page],
  budget : @archive.Budget,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Bytes, Array[PageMap]) raise @failure.Failure {
  let sheets : Array[@xlsx.ContentSheet] = []
  let mapping : Array[PageMap] = []
  for pageIndex, page in pages {
    guard !page.tables.is_empty() else {
      @failure.reject(
        "conversion-unavailable",
        "Page \{pageIndex+1}: no table with explicit cell boundaries was found",
      )
    }
    for region, table in page.tables {
      let widths = Array::makei(table.xs.length() - 1, column => {
        table.xs[column + 1] - table.xs[column]
      })
      let heights = Array::makei(table.ys.length() - 1, row => {
        table.ys[row + 1] - table.ys[row]
      })
      let cells = table.cells.map(cell => {
        let text = cell.lines.map(@pdf.read_line_text).join("\n")
        let style = cell.lines
          .iter()
          .filter_map(line => line.runs.get(0))
          .next()
          .unwrap_or({
            text: "",
            font: "Calibri",
            identity: "",
            size: 11,
            color: "000000",
            bold: false,
            italic: false,
          })
        let value : @xlsx.ContentCell = {
          row: cell.row,
          column: cell.column,
          rowSpan: cell.rowSpan,
          columnSpan: cell.columnSpan,
          text,
          numeric: numeric_text(text),
          font: style.font,
          size: style.size,
          color: style.color,
          bold: style.bold,
          italic: style.italic,
          fill: cell.fill,
        }
        value
      })
      sheets.push({
        name: "Page \{pageIndex+1} Table \{region+1}",
        widths,
        heights,
        cells,
      })
      mapping.push({ source: page.source, target: sheets.length(), })
    }
  }
  let target = @xlsx.Session::create_content(sheets, budget, probe, profile)
  defer target.close()
  (target.save(), mapping)
}
