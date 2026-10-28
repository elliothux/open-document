///|
fn Session::prepare_fill_hyperlinks(
  self : Session,
  plan : CellEditPlan,
  index : Int32,
  source : Range,
  target : Range,
) -> Bool raise @failure.Failure {
  let sheet = plan.sheets[index]
  let seeds = self.capture_hyperlinks(sheet, source, complete=true)
  guard seeds.all(link => {
    [link.display, link.tooltip].all(text => {
      text.map(v => v.length() <= 32767).unwrap_or(true)
    })
  }) else {
    @failure.reject(
      "limit-exceeded", "Filled hyperlink metadata exceeds budget",
    )
  }
  let vertical = source.left == target.left && source.right == target.right
  let stride = if vertical {
    source.bottom - source.top + 1
  } else {
    source.right - source.left + 1
  }
  let first = if vertical { target.top } else { target.left }
  let last = if vertical { target.bottom } else { target.right }
  let origin = if vertical { source.top } else { source.left }
  let start = first - ((first - origin) % stride + stride) % stride
  let links : Array[CopiedHyperlink] = []
  let mut units = 0
  for axis = start; axis <= last; axis = axis + stride {
    for seed in seeds {
      let range : Range = if vertical {
        {
          ..seed.range,
          top: seed.range.top + axis - origin,
          bottom: seed.range.bottom + axis - origin,
        }
      } else {
        {
          ..seed.range,
          left: seed.range.left + axis - origin,
          right: seed.range.right + axis - origin,
        }
      }
      if target.covers(range) {
        links.push({ ..seed, range, })
        units += seed.target.length() +
          seed.display.map(String::length).unwrap_or(0) +
          seed.tooltip.map(String::length).unwrap_or(0)
        guard links.length() <= 4096 && units <= 1048576 else {
          @failure.reject("limit-exceeded", "Filled hyperlinks exceed budget")
        }
      }
    }
  }
  let before = self.capture_hyperlinks(sheet, target)
  let keys = (items : Array[CopiedHyperlink]) => {
    let result = items.map(link => {
      (link.range, link.target, link.display, link.tooltip)
    })
    result.sort_by((a, b) => {
      let row = a.0.top.compare(b.0.top)
      if row == 0 {
        a.0.left.compare(b.0.left)
      } else {
        row
      }
    })
    result
  }
  if keys(before) == keys(links) {
    return false
  }
  self.prepare_hyperlinks(plan, index, target, links)
  true
}
