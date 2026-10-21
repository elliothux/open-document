///|
priv struct PrintedCell {
  range : Range
  rect : @layout.SelectionRect
}

///|
fn Session::print_page_links(
  _self : Session,
  sheets : Array[PrintedSheet],
) -> Array[@layout.PageLink] raise @failure.Failure {
  let links : Array[@layout.PageLink] = []
  let mut work = 0
  for printed in sheets {
    for (range, address) in printed.links {
      if address.has_prefix("#") {
        continue
      }
      let target = @layout.External(address)
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
