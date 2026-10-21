///|
fn Session::formula_hyperlink_owner(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> Bool {
  guard self.calculation is Some(calculation) &&
    !calculation.hyperlinks.is_empty() else {
    return false
  }
  let native = try {
    let tree = Tree::new(sheet.document)
    hyperlink_nodes(tree).map(node => {
      Range::parse(node.attribute("ref").unwrap_or(""))
    })
  } catch {
    @failure.Failure(..) => return true
  }
  let index = self.sheets.search_by(s => s.id == sheet.id).unwrap()
  let mut remaining = 1048576
  calculation.hyperlinks
  .keys()
  .any(key => {
    if key.0 != index {
      return false
    }
    guard sheet.cells.get(key.1) is Some(source) else { return false }
    let address = source.address
    let cell = sheet.cell_range(address)
    if address.row != cell.top ||
      address.column != cell.left ||
      !cell.intersects(range) {
      return false
    }
    let explicit = native.any(bounds => {
      remaining -= 1
      remaining < 0 || bounds.covers(cell)
    })
    remaining < 0 || !explicit
  })
}

///|
fn Session::with_formula_hyperlinks(
  self : Session,
  sheet : Sheet,
  links : Array[(Range, String)],
  target? : Range,
  work? : FormulaWork,
) -> Array[(Range, String)] raise @failure.Failure {
  guard self.calculation is Some(calculation) &&
    !calculation.hyperlinks.is_empty() else {
    return links
  }
  let work = work.unwrap_or_else(() => {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  })
  let index = self.sheet_index(sheet.id)
  let derived : Array[(Range, String)] = []
  for key, address in calculation.hyperlinks {
    work.spend()
    if key.0 != index {
      continue
    }
    let owner = Address::parse(key.1)
    let range = sheet.cell_range(owner)
    if owner.row != range.top ||
      owner.column != range.left ||
      target.map(t => !t.intersects(range)).unwrap_or(false) {
      continue
    }
    let mut explicit = false
    for (bounds, _) in links {
      work.spend()
      if bounds.intersects(range) {
        guard bounds.covers(range) else {
          @failure.reject(
            "protected-content", "Native hyperlink must contain the complete formula merged cell",
          )
        }
        explicit = true
        break
      }
    }
    if explicit {
      continue
    }
    if address is Some(address) {
      check_hyperlink_target(address)
      derived.push((range, address))
    }
  }
  [..links, ..derived]
}
