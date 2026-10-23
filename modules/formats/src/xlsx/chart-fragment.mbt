///|
fn read_chart_fragment(
  value : Json,
  budget : @archive.Budget,
) -> (@chart.WorksheetChart, @xml.Document)? raise @failure.Failure {
  if value is Null {
    return None
  }
  guard value is Object(fields) &&
    fields.length() == 2 &&
    value is { "source": String(source), "visible": Array(groups), .. } &&
    source.length() <= 1048576 else {
    @failure.reject("invalid-operation", "Invalid drawing clipboard chart")
  }
  let document = @xml.Document::parse(
    @utf8.encode(source),
    "chart.xml",
    budget.xml_depth,
    budget.entry_bytes.min(1048576),
  )
  let chart = @chart.read_worksheet("chart.xml", document)
  guard groups.length() == chart.data.series.length() + 1 else {
    @failure.reject(
      "invalid-operation", "Chart visibility requires every source",
    )
  }
  let visible = groups.mapi((group, value) => {
    let count = if group == 0 {
      chart.data.categories.length()
    } else {
      chart.data.series[group - 1].values.length()
    }
    guard value is Array(indices) && indices.length() <= count else {
      @failure.reject("invalid-operation", "Invalid chart clipboard visibility")
    }
    let values = indices.map(value => {
      guard value is Number(number, ..) &&
        number >= 0 &&
        number < count.to_double() &&
        number.floor() == number else {
        @failure.reject(
          "invalid-operation", "Invalid chart clipboard source index",
        )
      }
      number.to_int()
    })
    guard values
      .mapi((index, value) => index == 0 || values[index - 1] < value)
      .all(value => value) else {
      @failure.reject(
        "invalid-operation", "Chart source indices must be ordered",
      )
    }
    values
  })
  let rows = StringBuilder()
  let mut row = 1
  fn vector(
    values : Array[Value],
    shown : Array[Int],
  ) -> String raise @failure.Failure {
    if values.is_empty() {
      return "#REF!"
    }
    let first = row
    for index, value in values {
      let cell = match value {
        Number(number) => "<c r='A\{row}'><v>\{number}</v></c>"
        Text(text) =>
          "<c r='A\{row}' t='inlineStr'><is><t xml:space='preserve'>\{@xml.escape_text(text)}</t></is></c>"
        Blank => "<c r='A\{row}'/>"
        _ => @failure.reject("invalid-chart", "Invalid copied chart value")
      }
      rows.write_string(
        "<row r='\{row}'\{if shown.contains(index) { "" } else { " hidden='1'" }}>\{cell}</row>",
      )
      row += 1
    }
    "Sheet1!$A$\{first}:$A$\{row-1}"
  }
  let categories = vector(
    chart.data.categories.map(value => {
      if chart.data.kind == "scatter" {
        if value.is_empty() {
          Blank
        } else {
          Number(number(value))
        }
      } else {
        Text(value)
      }
    }),
    visible[0],
  )
  let names : Array[String] = []
  let values : Array[String] = []
  for index, series in chart.data.series {
    names.push(vector([Text(series.name)], [0]))
    values.push(
      vector(
        series.values.map(value => {
          value.map(value => Value::Number(value)).unwrap_or(Blank)
        }),
        visible[index + 1],
      ),
    )
  }
  let data = @xml.Document::parse(
    @utf8.encode(
      "<worksheet xmlns='\{spreadsheet_uri}'><sheetData>\{rows}</sheetData></worksheet>",
    ),
    "chart-data.xml",
    budget.xml_depth,
    budget.entry_bytes,
  )
  Some(({ ..chart, categories, names, values, }, data))
}

///|
fn drawing_fragment_reference(
  document : @xml.Document,
  uri : String,
  name : String,
  attribute : String,
  relation : String,
) -> @xml.Document raise @failure.Failure {
  let references = document
    .nodes()
    .filter(node => node.uri == uri && node.name == name)
  guard references is [node] &&
    node.attributes is [attr] &&
    attr.uri == relationship_uri[:relationship_uri.length() - 1].to_owned() &&
    attr.name == attribute else {
    @failure.reject(
      "invalid-operation", "Drawing clipboard requires one native resource reference",
    )
  }
  document.edit_source([
    {
      node: node.id,
      offset: attr.start - node.start,
      length: attr.end - attr.start,
      xml: escaped_attribute(relation),
    },
  ]).0
}
