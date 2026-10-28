///|
let chart_uri = "http://schemas.openxmlformats.org/drawingml/2006/chart"

///|
fn broken_chart_reference(text : String) -> Bool {
  if text == "#REF!" {
    return true
  }
  if !text.has_prefix("#REF!") {
    return false
  }
  try (parse_formula(text[5:].to_owned()) is Reference(None, _, _)) catch {
    @failure.Failure(..) => false
  }
}

///|
fn chart_binding_reason(chart : @chart.WorksheetChart) -> String {
  if ([chart.categories] + chart.names + chart.values).any(
      broken_chart_reference,
    ) {
    "A chart source was deleted; cached values are shown until its references are rebound"
  } else {
    ""
  }
}

///|
fn Session::chart_reference_range(
  self : Session,
  formula : String,
  owner : String,
  work : FormulaWork,
) -> (Int32, Range) raise @failure.Failure {
  guard formula.length() <= 1024 &&
    parse_formula(formula) is Reference(target, first, last) else {
    @failure.reject(
      "unsupported-chart", "Chart data requires a worksheet cell range",
    )
  }
  let index = referenced_sheet(self.sheets, self.sheet_index(owner), target)
  let range = first.range(last.unwrap_or(first))
  guard (range.top == range.bottom || range.left == range.right) &&
    range.bottom - range.top + range.right - range.left < 256 else {
    @failure.reject(
      "limit-exceeded", "Chart reference exceeds 256 linear cells",
    )
  }
  work.spend(amount=range.bottom - range.top + range.right - range.left + 1)
  (index, range)
}

///|
fn Session::chart_reference_values(
  self : Session,
  formula : String,
  owner : String,
  work : FormulaWork,
) -> Array[Value] raise @failure.Failure {
  let (index, range) = self.chart_reference_range(formula, owner, work)
  let sheet = self.sheets[index]
  Array::makei(range.bottom - range.top + range.right - range.left + 1, offset => {
    let address : Address = {
      row: range.top + (if range.top == range.bottom { 0 } else { offset }),
      column: range.left + (if range.left == range.right { 0 } else { offset }),
    }
    let name = address.name()
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
  let categories = if broken_chart_reference(chart.categories) {
    chart.data.categories
  } else {
    self.chart_reference_values(chart.categories, owner, work).map(chart_label)
  }
  let series = chart.names.mapi((index, formula) => {
    let name = if broken_chart_reference(formula) {
      chart.data.series[index].name
    } else {
      guard self.chart_reference_values(formula, owner, work) is [title] else {
        @failure.reject(
          "unsupported-chart", "Chart series title requires one cell",
        )
      }
      chart_label(title)
    }
    let values = if broken_chart_reference(chart.values[index]) {
      chart.data.series[index].values.map(value => {
        value.map(value => Value::Number(value)).unwrap_or(Blank)
      })
    } else {
      self.chart_reference_values(chart.values[index], owner, work)
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
  data.validate_sources()
  { ..chart, data, }
}

///|
fn Session::maintain_charts(
  self : Session,
  sheets : Array[Sheet],
  workbook : @xml.Document,
  calculation : Calculation,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  media : Map[String, Bytes],
) -> Unit raise @failure.Failure {
  let view = {
    ..self,
    sheets,
    workbook,
    parts,
    media,
    calculation: Some(calculation),
  }
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
    let (pending, inputs) = view.chart_input_state(drawing.owner, chart, work)
    if pending {
      guard self.part_xml(link.target).source() == original.source() &&
        self.chart_input_state(drawing.owner, chart, work) == (true, inputs) else {
        @failure.reject(
          "protected-content", "Change affects an uncalculated chart source",
        )
      }
      continue
    }
    let next = view.resolved_chart(drawing.owner, chart, work)
    if next.data == chart.data {
      continue
    }
    let root = original.nodes()[0]
    guard !original.source().contains("<!--") &&
      !original.source()[root.start:root.end].contains("<?") else {
      @failure.reject(
        "protected-content", "Chart annotations require source-preserving cache editing",
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
