///|
fn check_format_merges(
  merges : Array[Range],
  rows : Int,
  columns : Int,
) -> Unit raise @failure.Failure {
  guard merges.length() <= 1024 else {
    @failure.reject(
      "limit-exceeded", "Copied merged range count exceeds budget",
    )
  }
  let occupied = Array::make(rows * columns, false)
  for merge in merges {
    guard merge.top >= 1 &&
      merge.left >= 1 &&
      merge.bottom >= merge.top &&
      merge.right >= merge.left &&
      merge.bottom <= rows &&
      merge.right <= columns &&
      (merge.top != merge.bottom || merge.left != merge.right) else {
      @failure.reject(
        "invalid-operation", "Copied merge must fit the format rectangle",
      )
    }
    for row in merge.top..<=merge.bottom {
      for column in merge.left..<=merge.right {
        let index = (row - 1) * columns + column - 1
        guard !occupied[index] else {
          @failure.reject("invalid-operation", "Copied merged ranges overlap")
        }
        occupied[index] = true
      }
    }
  }
}

///|
fn Sheet::format_merges(
  self : Sheet,
  target : Range,
  pattern : Array[Range],
  rows : Int,
  columns : Int,
) -> Array[Range] raise @failure.Failure {
  check_merge_markup(Tree::new(self.document))
  let result = self.merges.filter(merge => !merge.intersects(target))
  for top = target.top; top <= target.bottom; top = top + rows {
    for left = target.left; left <= target.right; left = left + columns {
      for source in pattern {
        let range : Range = {
          top: top + source.top - 1,
          left: left + source.left - 1,
          bottom: (top + source.bottom - 1).min(target.bottom),
          right: (left + source.right - 1).min(target.right),
        }
        if range.top <= range.bottom &&
          range.left <= range.right &&
          (range.top != range.bottom || range.left != range.right) {
          guard result.length() < 1024 else {
            @failure.reject(
              "limit-exceeded", "Painted merged range count exceeds budget",
            )
          }
          result.push(range)
        }
      }
    }
  }
  if result.length() == self.merges.length() &&
    result.all(merge => self.merges.contains(merge)) {
    self.merges
  } else {
    result
  }
}
