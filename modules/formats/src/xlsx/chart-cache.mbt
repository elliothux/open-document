///|
fn newly_broken_chart_reference(before : String, after : String) -> Bool {
  before != after &&
  !broken_chart_reference(before) &&
  broken_chart_reference(after)
}

///|
fn SheetObject::freeze_chart_cache(
  self : SheetObject,
  part : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  let old = self.chart.unwrap().1
  let visible = self.chart_visibility.unwrap()
  let document = parts[part]
  let stored = @chart.read_worksheet(part, document)
  let categories = if newly_broken_chart_reference(
      old.categories,
      stored.categories,
    ) {
    visible.categories.map(index => old.data.categories[index])
  } else {
    old.data.categories
  }
  let series = old.data.series.mapi((index, series) => {
    if newly_broken_chart_reference(old.values[index], stored.values[index]) {
      {
        ..series,
        values: visible.values[index].map(index => series.values[index]),
      }
    } else {
      series
    }
  })
  let mut colors = old.colors
  if ["pie", "doughnut"].contains(old.data.kind) {
    for index, indices in visible.values {
      if indices.is_empty() {
        continue
      }
      if newly_broken_chart_reference(old.values[index], stored.values[index]) {
        colors = indices.map(index => {
          old.colors.get(index).unwrap_or_else(() => @layout.chart_color(index))
        })
      }
      break
    }
  }
  let next = { ..stored, data: { ..old.data, categories, series, }, colors, }
  if next.data == stored.data && next.colors == stored.colors {
    return
  }
  let root = document.nodes()[0]
  guard !document.source().contains("<!--") &&
    !document.source()[root.start:root.end].contains("<?") else {
    @failure.reject(
      "protected-content", "Chart annotations require source-preserving cache editing",
    )
  }
  let (document, edit) = pivot_root_edit(
    document,
    next.markup().split("?>").last().unwrap().to_owned(),
  )
  parts[part] = document
  edits.push((part, edit))
}
