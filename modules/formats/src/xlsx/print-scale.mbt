///|
fn print_axis_fits(
  axis : Axis,
  indices : Array[Int],
  available : Double,
  limit : Int,
  titles : Array[Int],
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
  rows : Array[Int],
  columns : Array[Int],
  title_rows : Array[Int],
  title_columns : Array[Int],
) -> Double raise @failure.Failure {
  if settings.fitWidth == 0 && settings.fitHeight == 0 {
    return settings.scale.to_double() / 100
  }
  let fits = fn(percent : Int) {
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
  for low = 10, high = 100; low < high; {
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
