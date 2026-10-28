///|
/// Visible zero-based source offsets, independently ordered for categories and each series.
pub(all) struct ChartVisibility {
  categories : Array[Int32]
  values : Array[Array[Int32]]
  colors : Array[String]
}

///|
fn chart_visible_indices(indices : Array[Int32], count : Int32) -> Bool {
  indices.length() <= count &&
  indices.all(index => index >= 0 && index < count) &&
  indices
  .mapi((i, index) => i == 0 || indices[i - 1] < index)
  .all(value => value)
}

///|
fn ChartData::visible_data(
  self : ChartData,
  visible : ChartVisibility?,
) -> (ChartData, Array[String]) raise @failure.Failure {
  let pie = ["pie", "doughnut"].contains(self.kind)
  guard visible is Some(visible) else {
    return (
      self,
      Array::makei(
        if pie {
          self.categories.length()
        } else {
          self.series.length()
        },
        chart_color,
      ),
    )
  }
  guard visible.values.length() == self.series.length() &&
    chart_visible_indices(visible.categories, self.categories.length()) &&
    visible.values
    .mapi((index, indices) => {
      chart_visible_indices(indices, self.series[index].values.length())
    })
    .all(value => value) &&
    visible.colors.length() <= 256 &&
    visible.colors.all(color => {
      color.length() == 6 &&
      color
      .iter()
      .all(c => {
        (c >= '0' && c <= '9') ||
        (c >= 'a' && c <= 'f') ||
        (c >= 'A' && c <= 'F')
      })
    }) else {
    @failure.reject(
      "invalid-chart", "Chart visibility requires ordered source indices",
    )
  }
  let series = visible.values
    .mapi((index, indices) => (index, indices))
    .filter(entry => !entry.1.is_empty())
  let count = series.fold(init=visible.categories.length(), (count, entry) => {
    count.max(entry.1.length())
  })
  let data = {
    ..self,
    categories: Array::makei(count, index => {
      visible.categories
      .get(index)
      .map(source => self.categories[source])
      .unwrap_or(
        if self.kind == "scatter" {
          ""
        } else {
          (index + 1).to_string()
        },
      )
    }),
    series: series.map(entry => {
      let original = self.series[entry.0]
      {
        ..original,
        values: Array::makei(count, index => {
          entry.1.get(index).bind(source => original.values[source])
        }),
      }
    }),
  }
  let colors = if pie {
    let indices = series.get(0).map(entry => entry.1).unwrap_or([])
    Array::makei(count, index => {
      chart_paint_color(visible.colors, indices.get(index).unwrap_or(index))
    })
  } else {
    series.map(entry => chart_paint_color(visible.colors, entry.0))
  }
  (data, colors)
}

///|
fn chart_paint_color(colors : Array[String], index : Int32) -> String {
  colors.get(index).unwrap_or_else(() => chart_color(index))
}
