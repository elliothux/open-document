///|
fn print_axis_fits(
  axis : Axis,
  indices : Array[Int32],
  available : Double,
  limit : Int32,
  titles : Array[Int32],
) -> Bool {
  try {
    let count = print_groups(axis, indices, available, titles).length()
    limit == 0 || count <= limit
  } catch {
    _ => false
  }
}

///|
fn print_scale(
  settings : PrintSetup,
  setup : @layout.PageSetup,
  dimensions : Dimensions,
  rows : Array[Int32],
  columns : Array[Int32],
  title_rows : Array[Int32],
  title_columns : Array[Int32],
  headers : (Double, Double),
) -> Double raise @failure.Failure {
  if settings.fitWidth == 0 && settings.fitHeight == 0 {
    return settings.scale.to_double() / 100
  }
  // Native fitting reserves header extents and one grid pixel before rounding its percentage.
  let total_width = columns.fold(init=0.0, (sum, i) => {
    sum + dimensions.columns.size(i)
  })
  let total_height = rows.fold(init=0.0, (sum, i) => {
    sum + dimensions.rows.size(i)
  })
  let width_scale = if settings.fitWidth > 0 && total_width > 0 {
    (setup.width - setup.left - setup.right - headers.0 - 0.75) *
    settings.fitWidth.to_double() /
    total_width
  } else {
    1.0
  }
  let height_scale = if settings.fitHeight > 0 && total_height > 0 {
    (setup.height - setup.top - setup.bottom - headers.1 - 0.75) *
    settings.fitHeight.to_double() /
    total_height
  } else {
    1.0
  }
  let maximum = (width_scale.min(height_scale) * 100)
    .max(10)
    .min(100)
    .round()
    .to_int()
  let fits = fn(percent : Int32) {
    let scale = percent.to_double() / 100
    print_axis_fits(
      dimensions.rows,
      rows,
      (setup.height - setup.top - setup.bottom) / scale,
      settings.fitHeight,
      title_rows,
    ) &&
    print_axis_fits(
      dimensions.columns,
      columns,
      (setup.width - setup.left - setup.right) / scale,
      settings.fitWidth,
      title_columns,
    )
  }
  guard fits(10) else {
    @failure.reject("print-overflow", "Requested page count cannot fit at 10%")
  }
  for low = 10, high = maximum; low < high; {
    let middle = (low + high + 1) / 2
    if fits(middle) {
      continue middle, high
    } else {
      continue low, middle - 1
    }
  } nobreak {
    low.to_double() / 100
  }
}

///|
fn Session::print_headers(
  self : Session,
  sheet : Sheet,
  last_row : Int32,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Double, Double) raise @failure.Failure {
  if !sheet.view.headings && !sheet.is_chart() {
    return (0, 0)
  }
  // Native chart-sheet pagination includes its implicit grid in fitting.
  let digits = last_row.to_string().length().max(3).to_double()
  (
    (digits * self.digit_width(probe, profile) + 5) * 0.75,
    self.normal_row_height(probe, profile),
  )
}
