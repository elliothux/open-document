///|
fn Paragraph::content_widths(
  self : Paragraph,
  probe : TextProbe,
  profile : Map[String, String],
) -> (Double, Double, Double) raise @failure.Failure {
  let cache = ParagraphCache::new(probe, profile)
  let lines = cache
    .lines(probe, { ..self, align: "left", }, profile, 1000000000, inTable=true)
    .map(item => item.line)
  let mut hard = 0.0
  let mut minimum = 0.0
  let mut maximum = 0.0
  let marker = probe.paragraph_marker(self, profile, 14400)
  for line in lines {
    let indent = self.right +
      (if line.start == 0 {
        marker.map(m => m.indent).unwrap_or(self.left + self.first)
      } else {
        self.left
      })
    hard = hard.max(indent + 0.05)
    maximum = maximum.max(line.width + indent)
    let breaks : Map[Int32, Bool] = Map([])
    for
      (offset, _) in @linebreak.linebreaks(
        line.text
        .replace_all(old="\u000b", new="\u2060")
        .replace_all(old="\u000c", new="\u2060"),
      ) {
      breaks[offset + line.start] = true
    }
    let mut word = 0.0
    let mut visible = 0.0
    for i = 0; i + 1 < line.carets.length(); i = i + 1 {
      let a = line.carets[i]
      let b = line.carets[i + 1]
      let width = (b.before - a.after).abs()
      hard = hard.max(width + indent)
      word += width
      let text = line.text[a.offset - line.start:b.offset - line.start]
      if !text.trim().is_empty() {
        visible = word
      }
      if breaks.contains(b.offset) {
        minimum = minimum.max(visible + indent)
        word = 0
        visible = 0
      }
    }
    minimum = minimum.max(visible + indent)
  }
  (hard, minimum.max(hard), maximum.max(minimum).max(hard))
}

///|
fn width_constraint(
  widths : Array[Double],
  start : Int32,
  span : Int32,
  required : Double,
  basis : Array[Double],
) -> Unit {
  let total = widths[start:start + span].fold(init=0.0, (sum, width) => {
    sum + width
  })
  if required <= total {
    return
  }
  let weight = basis[start:start + span].fold(init=0.0, (sum, width) => {
    sum + width
  })
  for c in start..<(start + span) {
    widths[c] += (required - total) * basis[c] / weight
  }
}

///|
fn width_distribution(
  base : Array[Int32],
  target : Int32,
  weights : Array[Double],
) -> Array[Int32] {
  let extra = target - base.fold(init=0, (sum, width) => sum + width)
  let total = weights.fold(init=0.0, (sum, weight) => sum + weight)
  let mut edge = 0.0
  let mut previous = 0
  base.mapi((i, width) => {
    edge += if total > 0 { weights[i] } else { 1 }
    let next = (extra.to_double() *
      edge /
      (if total > 0 { total } else { base.length().to_double() }))
      .round()
      .to_int()
    let result = width + next - previous
    previous = next
    result
  })
}

///|
pub fn Table::fit_widths(
  self : Table,
  probe : TextProbe,
  profile : Map[String, String],
  available : Double,
) -> Table raise @failure.Failure {
  if !self.autoFit {
    return self
  }
  self.check_grid()
  guard self.widths.length() <= 63 &&
    self.widths.all(v => v > 0 && !v.is_inf() && !v.is_nan()) else {
    @failure.reject("invalid-table", "Invalid automatic table grid")
  }
  guard available > 0 &&
    available <= 14400 &&
    self.preferredWidths.length() == self.rows.length() else {
    @failure.reject(
      "invalid-table", "Invalid automatic table width preferences",
    )
  }
  let count = self.widths.length()
  let preferred_width = self.preferredWidth.resolve(available)
  let hard = Array::make(count, 0.05)
  let minimum = Array::make(count, 0.05)
  let maximum = Array::make(count, 0.05)
  let preferred = Array::make(count, 0.0)
  let cells : Array[(Int32, Int32, Double, Double, Double, Double)] = []
  for r, row in self.rows {
    guard self.preferredWidths[r].length() == row.length() else {
      @failure.reject(
        "invalid-table", "Cell width preferences differ from the grid",
      )
    }
    let mut column = 0
    for c, paragraphs in row {
      let span = self.columnSpans[r][c]
      if self.rowSpans[r][c] > 0 {
        let margins = self.cell_insets(r, c)
        let inset = margins.left + margins.right
        let mut a = inset + 0.05
        let mut b = a
        let mut d = a
        for paragraph in paragraphs {
          let (hard, minimum, maximum) = paragraph.content_widths(
            probe, profile,
          )
          a = a.max(hard + inset)
          b = b.max(minimum + inset)
          d = d.max(maximum + inset)
        }
        for child in self.nestedTables {
          if child.row == r && child.column == c {
            let fitted = child.table.fit_widths(
              probe,
              profile,
              available - inset,
            )
            let width = fitted.widths.fold(init=0.0, (sum, width) => sum + width)
            b = b.max(width + inset)
            d = d.max(width + inset)
          }
        }
        let hint = self.preferredWidths[r][c].resolve(available)
        cells.push((column, span, a, b, d, hint))
      }
      column += span
    }
  }
  // Resolve single columns first, then distribute merged-cell requirements in source order.
  for merged in [false, true] {
    for (start, span, a, b, d, hint) in cells {
      if (span > 1) != merged {
        continue
      }
      width_constraint(hard, start, span, a, self.widths)
      width_constraint(minimum, start, span, b, self.widths)
      width_constraint(
        maximum,
        start,
        span,
        if hint > 0 {
          hint.max(b)
        } else {
          d
        },
        self.widths,
      )
      width_constraint(preferred, start, span, hint, self.widths)
    }
  }
  let floor = hard.map(v => (v * 20 - 0.000001).ceil().to_int())
  let low = minimum.mapi((i, v) => {
    (v * 20 - 0.000001).ceil().to_int().max(floor[i])
  })
  let high = maximum.mapi((i, v) => {
    (v * 20 - 0.000001).ceil().to_int().max(low[i])
  })
  let sum = fn(values : Array[Int32]) {
    values.fold(init=0, (total, width) => total + width)
  }
  let limit = (available * 20).floor().to_int()
  guard sum(floor) <= limit else {
    @failure.reject(
      "layout-overflow", "Table content cannot fit the page width",
    )
  }
  let target = if preferred_width > 0 {
    (preferred_width * 20).round().to_int().min(limit).max(sum(floor))
  } else {
    sum(high).min(limit).max(sum(floor))
  }
  let widths = if target < sum(low) {
    width_distribution(
      floor,
      target,
      low.mapi((i, value) => (value - floor[i]).to_double()),
    )
  } else if target < sum(high) {
    width_distribution(
      low,
      target,
      high.mapi((i, value) => (value - low[i]).to_double()),
    )
  } else {
    let weights = if preferred.any(v => v == 0) {
      preferred.mapi((i, value) => {
        if value == 0 {
          high[i].to_double()
        } else {
          0
        }
      })
    } else {
      high.map(v => v.to_double())
    }
    width_distribution(high, target, weights)
  }
  { ..self, widths: widths.map(v => v.to_double() / 20), }
}
