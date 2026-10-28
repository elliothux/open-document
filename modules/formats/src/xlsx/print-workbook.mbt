///|
pub(all) enum PrintSheets {
  CurrentSheet
  VisibleSheets
  SelectedSheets(Array[String])
}

///|
priv struct PrintWork {
  mut cells : Int64
  mut pages : Int32
  formulas : FormulaWork
  destinations : Map[(String, Int32, Int32), @layout.LinkTarget]
}

///|
priv struct PrintedSheet {
  id : String
  name : String
  setup : @layout.PageSetup
  scale : Double
  headers : HeaderFooter
  first_page : Int32
  pages : Array[@layout.PositionedPage]
  units : Array[Int32]
  cells : Array[PrintedCell]
  links : Array[(Range, String)]
}

///|
/// Print current or selected visible sheets in workbook order with shared output limits.
pub fn Session::print_layout(
  self : Session,
  revision : Int32,
  sheet : String,
  range : String?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  setup? : @layout.PageSetup,
  sheets~ : PrintSheets = CurrentSheet,
) -> @layout.PositionedDocument raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheet_index(sheet)
  let indices = match sheets {
    CurrentSheet => [current]
    VisibleSheets =>
      Array::makei(self.sheets.length(), i => i).filter(i => {
        self.sheets[i].state == "visible"
      })
    SelectedSheets(ids) => {
      guard !ids.is_empty() && ids.length() <= 256 else {
        @failure.reject(
          "invalid-sheet", "Select between one and 256 worksheets to print",
        )
      }
      let selected : Map[Int32, Bool] = Map([])
      for id in ids {
        let index = self.sheet_index(id)
        guard !selected.contains(index) else {
          @failure.reject("invalid-sheet", "Duplicate printed worksheet")
        }
        selected[index] = true
      }
      Array::makei(self.sheets.length(), i => i).filter(i => {
        selected.contains(i)
      })
    }
  }
  guard indices.all(i => self.sheets[i].state == "visible") else {
    @failure.reject(
      "invalid-sheet", "Show hidden worksheets before printing them",
    )
  }
  let work : PrintWork = {
    cells: 0L,
    pages: 0,
    destinations: Map([]),
    formulas: {
      remaining: 1048576,
      date1904: self.date1904,
      origin: { row: 1, column: 1, },
      names: self.formula_names(),
    },
  }
  let planned = indices.map(index => {
    self.print_sheet(index, range, probe, profile, setup, work)
  })
  let pages : Array[@layout.PositionedPage] = []
  for printed in planned {
    for ordinal, page in printed.pages {
      let (headers, units) = self.paint_header_footer(
        printed.name,
        printed.headers,
        printed.setup,
        printed.scale,
        ordinal,
        printed.first_page + ordinal,
        work.pages,
        probe,
        profile,
      )
      guard printed.units[ordinal] + units <= 262144 else {
        @failure.reject(
          "limit-exceeded", "Printed text including headers exceeds page budget",
        )
      }
      pages.push({ ..page, primitives: [..page.primitives, ..headers], })
    }
  }
  self.font_context = Some((probe, profile.copy()))
  {
    pages,
    fonts: probe.font_info(),
    links: self.print_page_links(planned, work.destinations, work.formulas),
  }
}
