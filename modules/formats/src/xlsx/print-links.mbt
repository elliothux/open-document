///|
priv struct PrintedCell {
  range : Range
  rect : @layout.SelectionRect
}

///|
fn Session::print_page_links(
  self : Session,
  sheets : Array[PrintedSheet],
  destinations : Map[(String, Int32, Int32), @layout.LinkTarget],
  formulas : FormulaWork,
) -> Array[@layout.PageLink] raise @failure.Failure {
  let links : Array[@layout.PageLink] = []
  let mut work = 0
  for printed in sheets {
    for (range, address) in printed.links {
      let target = if address.has_prefix("#") {
        let destination = try {
          let (sheet, range) = self.hyperlink_destination(
            self.sheet_index(printed.id),
            { row: range.top, column: range.left, },
            address,
            work=formulas,
          )
          let cell = self.sheets[self.sheet_index(sheet)].cell_range({
            row: range.top,
            column: range.left,
          })
          destinations.get((sheet, cell.top, cell.left))
        } catch {
          @failure.Failure(code="limit-exceeded", ..) as error => raise error
          @failure.Failure(..) => None
        }
        guard destination is Some(target) else { continue }
        target
      } else {
        @layout.External(address)
      }
      for cell in printed.cells {
        work += 1
        guard work <= 8388608 else {
          @failure.reject(
            "limit-exceeded", "Printed link lookup exceeds the work budget",
          )
        }
        if !range.intersects(cell.range) {
          continue
        }
        guard range.covers(cell.range) else {
          @failure.reject(
            "unsupported-print", "Hyperlink must contain the complete printed merged cell",
          )
        }
        guard links.length() < 65536 else {
          @failure.reject(
            "limit-exceeded", "Printed links exceed the rectangle budget",
          )
        }
        links.push({ rect: cell.rect, target, })
      }
    }
  }
  links
}
