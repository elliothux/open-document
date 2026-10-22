///|
let chart_uri = "http://schemas.openxmlformats.org/drawingml/2006/chart"

///|
fn Session::chart_reference_values(
  self : Session,
  formula : String,
  owner : String,
  work : FormulaWork,
) -> Array[Value] raise @failure.Failure {
  guard formula.length() <= 1024 &&
    parse_formula(formula) is Reference(target, first, last) else {
    @failure.reject(
      "unsupported-chart", "Chart data requires a worksheet cell range",
    )
  }
  let index = referenced_sheet(self.sheets, self.sheet_index(owner), target)
  let sheet = self.sheets[index]
  let range = first.range(last.unwrap_or(first))
  guard (range.top == range.bottom || range.left == range.right) &&
    range.bottom - range.top + range.right - range.left < 256 else {
    @failure.reject(
      "limit-exceeded", "Chart reference exceeds 256 linear cells",
    )
  }
  work.spend(amount=range.bottom - range.top + range.right - range.left + 1)
  Array::makei(range.bottom - range.top + range.right - range.left + 1, offset => {
    let address : Address = {
      row: range.top + (if range.top == range.bottom { 0 } else { offset }),
      column: range.left + (if range.left == range.right { 0 } else { offset }),
    }
    let name = address.name()
    guard sheet.dimensions.rows.size(address.row) > 0 &&
      sheet.dimensions.columns.size(address.column) > 0 else {
      @failure.reject(
        "unsupported-chart", "Hidden chart data requires visibility-aware series binding",
      )
    }
    let cell = sheet.cells.get(name)
    guard cell.map(cell => cell.calculation_supported).unwrap_or(true) else {
      @failure.reject(
        "unsupported-chart",
        "Chart cell value requires support: " + name,
      )
    }
    let calculated = self.calculation.bind(calculation => {
      calculation.values.get((index, name))
    })
    guard cell.bind(cell => cell.formula) is None || calculated is Some(_) else {
      @failure.reject("unsupported-chart", "Chart formulas must be calculated")
    }
    calculated.unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank))
  })
}

///|
fn chart_label(value : Value) -> String raise @failure.Failure {
  match value {
    Text(text) => text
    Number(value) => value.to_string()
    Blank => ""
    _ =>
      @failure.reject(
        "unsupported-chart", "Chart labels require text, numbers or blanks",
      )
  }
}

///|
fn Session::resolved_chart(
  self : Session,
  owner : String,
  chart : @chart.WorksheetChart,
  work : FormulaWork,
) -> @chart.WorksheetChart raise @failure.Failure {
  let categories = self
    .chart_reference_values(chart.categories, owner, work)
    .map(chart_label)
  let series = chart.names.mapi((index, formula) => {
    guard self.chart_reference_values(formula, owner, work) is [title] else {
      @failure.reject(
        "unsupported-chart", "Chart series title requires one cell",
      )
    }
    let name = chart_label(title)
    let values = self.chart_reference_values(chart.values[index], owner, work)
    guard values.length() == categories.length() else {
      @failure.reject(
        "unsupported-chart", "Chart series references must match category count",
      )
    }
    @layout.ChartSeries::{
      name: if name.is_empty() {
        "Series " + (index + 1).to_string()
      } else {
        name
      },
      values: values.map(value => {
        match value {
          Number(value) => Some(value)
          _ => None
        }
      }),
    }
  })
  let data = { ..chart.data, categories, series, }
  data.validate()
  { ..chart, data, }
}

///|
fn Session::maintain_charts(
  self : Session,
  sheets : Array[Sheet],
  calculation : Calculation,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let view = { ..self, sheets, parts, calculation: Some(calculation), }
  let links = view.relationships()
  let drawings = links.filter(link => {
    !link.external &&
    link.kind == relationship_uri + "drawing" &&
    sheets.any(sheet => sheet.id == link.owner)
  })
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: calculation.names,
  }
  let seen : Set[String] = Set([])
  for link in links {
    if link.external || link.kind != relationship_uri + "chart" {
      continue
    }
    guard drawings.iter().find_first(drawing => drawing.target == link.owner)
      is Some(drawing) else {
      continue
    }
    if !view
      .part_xml(link.owner)
      .nodes()
      .any(node => {
        node.uri == chart_uri &&
        node.name == "chart" &&
        node.attribute(
          "id",
          uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
        ) ==
        Some(link.id)
      }) {
      continue
    }
    guard !seen.contains(link.target) && seen.length() < 256 else {
      @failure.reject(
        "unsupported-chart", "Shared or excessive worksheet chart parts require independent ownership",
      )
    }
    seen.add(link.target)
    let original = view.part_xml(link.target)
    let chart = @chart.read_worksheet(link.target, original)
    let next = view.resolved_chart(drawing.owner, chart, work)
    if next.data == chart.data {
      continue
    }
    guard !original.source().contains("<!--") else {
      @failure.reject(
        "protected-content", "Chart comments require source-preserving cache editing",
      )
    }
    let (document, edit) = pivot_root_edit(
      original,
      next.markup().split("?>").last().unwrap().to_owned(),
    )
    parts[link.target] = document
    edits.push((link.target, edit))
  }
}
