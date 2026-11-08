///|
fn chart_sheet_print_coordinate(value : Double, scale : Double) -> Double {
  // Native metafile transforms truncate physical coordinates to 1e-5 mm.
  (value * scale / 72 * 25.4 * 100000).trunc() / 100000 * 72 / 25.4 / scale
}

///|
fn Session::print_chart_sheet(
  self : Session,
  index : Int32,
  range : String?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  page : @layout.PageSetup?,
  work : PrintWork,
) -> PrintedSheet raise @failure.Failure {
  let sheet = self.sheets[index]
  let print_range = self.read_print_range(index)
  guard range is None &&
    print_range.area.is_empty() &&
    print_range.rows.is_empty() &&
    print_range.columns.is_empty() else {
    @failure.reject(
      "unsupported-print",
      "Chart sheets have no cell print range",
      part=sheet.id,
    )
  }
  let tree = Tree::new(sheet.document)
  if tree.one(tree.sheet_root().id, "pageSetup") is Some(setup) {
    guard ["scale", "fitToWidth", "fitToHeight"].all(name => {
      setup.attribute(name) is None
    }) else {
      @failure.reject(
        "unsupported-print",
        "Chart sheet scaling settings require support",
        part=sheet.id,
      )
    }
  }
  let settings = { ..read_print_setup(sheet), fitWidth: 1, fitHeight: 1, }
  let setup = page.unwrap_or(settings.page())
  validate_print_page(setup)
  let dimensions = self.resolved_dimensions(sheet, probe, profile)
  let objects = self
    .sheet_objects(sheet, dimensions)
    .filter(item => item.visible && item.printable)
  for diagnostic in self.diagnostics {
    if diagnostic.has_prefix("unrendered:" + sheet.id + ":") &&
      !drawing_diagnostic(sheet, diagnostic) {
      @failure.reject(
        "unsupported-print",
        "Unrendered chart sheet content: " + diagnostic,
        part=sheet.id,
      )
    }
  }
  let workbook = Tree::new(self.part_xml(self.main))
  let snapshot = self.revision == 0 &&
    workbook
    .one(workbook.root("workbook").id, "calcPr")
    .bind(node => node.attribute("calcMode")) ==
    Some("manual")
  for object in objects {
    guard !object.chart_pending || snapshot else {
      @failure.reject(
        "unsupported-print",
        uncalculated_chart_reason,
        part=sheet.id,
      )
    }
  }
  let used = drawing_used(sheet.used(), objects, dimensions)
  let rows = dimensions.rows.visible(used.top, used.bottom)
  let columns = dimensions.columns.visible(used.left, used.right)
  let scale = print_scale(
    settings,
    setup,
    dimensions,
    rows,
    columns,
    [],
    [],
    self.print_headers(sheet, used.bottom, probe, profile),
  )
  let clip : @layout.Border = {
    x: setup.left / scale,
    y: setup.top / scale,
    width: (setup.width - setup.left - setup.right) / scale,
    height: (setup.height - setup.top - setup.bottom) / scale,
  }
  work.pages += 1
  guard work.pages <= 1024 else {
    @failure.reject("limit-exceeded", "Print page count exceeds budget")
  }
  let primitives : Array[@layout.PositionedPrimitive] = [
    Transform({ a: scale, b: 0, c: 0, d: scale, e: 0, f: 0, }),
    Clip(clip),
  ]
  let mut units = 0
  for object in objects {
    let first = primitives.length()
    let inset = 0.75
    object.paint(
      primitives,
      {
        ..object.rect,
        x: chart_sheet_print_coordinate(object.rect.x + inset + clip.x, scale),
        y: chart_sheet_print_coordinate(object.rect.y + inset + clip.y, scale),
      },
      probe,
      profile,
    )
    work.add_graphics(primitives, first)
    for i in first..<primitives.length() {
      if primitives[i] is @layout.Text(line) {
        for run in line.runs {
          units += run.text.length()
          guard units <= 262144 else {
            @failure.reject(
              "limit-exceeded", "Printed chart text exceeds page budget",
            )
          }
        }
      }
    }
  }
  primitives.append([Restore, Restore])
  {
    id: sheet.id,
    name: sheet.name,
    setup,
    scale,
    headers: read_header_footer(sheet),
    first_page: print_first_page(sheet),
    pages: [{ width: setup.width, height: setup.height, primitives, }],
    units: [units],
    cells: [],
    links: [],
  }
}
