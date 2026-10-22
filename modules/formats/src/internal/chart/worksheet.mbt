///|
pub(all) struct WorksheetChart {
  data : @layout.ChartData
  categories : String
  names : Array[String]
  values : Array[String]
}

///|
pub fn WorksheetChart::markup(
  self : WorksheetChart,
) -> String raise @failure.Failure {
  self.data.validate()
  guard self.names.length() == self.data.series.length() &&
    self.values.length() == self.data.series.length() else {
    @failure.reject("invalid-chart", "Chart references must match every series")
  }
  let formulas = self.names
    .mapi((index, name) => [name, self.categories, self.values[index]])
    .flatten()
  guard formulas.all(value => {
    !value.is_empty() && value.length() <= 1024 && @xml.valid_text(value)
  }) else {
    @failure.reject("invalid-chart", "Chart references exceed source limits")
  }
  let document = @xml.Document::parse(
    @utf8.encode(markup(self.data, "worksheet")),
    "chart.xml",
    64,
    1048576,
  )
  let nodes = document.nodes()
  let sources = nodes
    .iter()
    .filter(node => node.uri == chart_uri && node.name == "f")
    .to_array()
  guard sources.length() == formulas.length() else {
    @failure.reject("invalid-chart", "Unexpected chart reference structure")
  }
  let changes : Array[@xml.SourceChange] = sources.mapi((index, node) => {
    node: node.id,
    offset: node.opening_end - node.start,
    length: node.closing_start - node.opening_end,
    xml: @xml.escape_text(formulas[index]),
  })
  for node in nodes {
    if node.uri == chart_uri && node.name == "externalData" {
      changes.push({
        node: node.parent,
        offset: node.start - nodes[node.parent].start,
        length: node.end - node.start,
        xml: "",
      })
    }
  }
  document.edit_source(changes).0.source()
}

///|
pub fn read_worksheet(
  part : String,
  document : @xml.Document,
) -> WorksheetChart raise @failure.Failure {
  let (root, data) = read_chart(part, document)
  let formulas = document
    .nodes()
    .filter(node => node.uri == chart_uri && node.name == "f")
    .map(node => node.text)
  guard formulas.length() == data.series.length() * 3 else {
    @failure.reject(
      "unsupported-chart", "Worksheet chart references must cover every series",
    )
  }
  let categories = formulas[1]
  guard data.series
    .mapi((index, _) => formulas[index * 3 + 1] == categories)
    .all(value => value) else {
    @failure.reject(
      "unsupported-chart", "Series require a common category source",
    )
  }
  let result : WorksheetChart = {
    data,
    categories,
    names: data.series.mapi((index, _) => formulas[index * 3]),
    values: data.series.mapi((index, _) => formulas[index * 3 + 2]),
  }
  let expected = @xml.Document::parse(
    @utf8.encode(result.markup()),
    part,
    64,
    1048576,
  )
  let tree = Tree::new(part, expected)
  guard chart_structure(root, { tree, node: expected.nodes()[0], }) else {
    @failure.reject(
      "unsupported-chart", "Chart styles or source structure require support",
    )
  }
  result
}
