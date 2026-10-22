///|
pub(all) struct ConditionalRank {
  rank : Int
  percent : Bool
  bottom : Bool
} derive(Eq, ToJson)

///|
pub extend ConditionalRank with Eq::{equal, not_equal}

///|
pub extend ConditionalRank with ToJson::{to_json}

///|
fn ConditionalRank::check(
  self : ConditionalRank,
) -> Unit raise @failure.Failure {
  guard self.rank >= 1 && self.rank <= (if self.percent { 100 } else { 1000 }) else {
    @failure.reject(
      "invalid-operation", "Conditional rank exceeds supported range",
    )
  }
}

///|
pub(all) struct ConditionalAverage {
  above : Bool
  equal : Bool
  stdDev : Int
} derive(Eq, ToJson)

///|
pub extend ConditionalAverage with Eq::{equal, not_equal}

///|
pub extend ConditionalAverage with ToJson::{to_json}

///|
fn ConditionalFormat::check_nonformula(
  self : ConditionalFormat,
) -> Bool raise @failure.Failure {
  if ["top10", "aboveAverage", "duplicateValues", "uniqueValues"].contains(
      self.kind,
    ) ||
    conditional_predicate_kind(self.kind) {
    guard self.operator.is_empty() &&
      self.formula1.is_empty() &&
      self.formula2.is_empty() &&
      self.stops.is_empty() &&
      self.bar is None &&
      (self.rank is Some(_)) == (self.kind == "top10") &&
      (self.average is Some(_)) == (self.kind == "aboveAverage") else {
      @failure.reject("invalid-operation", "Invalid built-in conditional rule")
    }
    if self.rank is Some(rank) {
      rank.check()
    }
    if self.average is Some(average) {
      average.check()
    }
    return true
  }
  guard self.rank is None && self.average is None else {
    @failure.reject(
      "invalid-operation", "Only statistical rules have rank or average settings",
    )
  }
  false
}

///|
fn ConditionalAverage::check(
  self : ConditionalAverage,
) -> Unit raise @failure.Failure {
  guard self.stdDev >= 0 && self.stdDev <= 3 else {
    @failure.reject(
      "invalid-operation", "Conditional standard deviation must be between zero and three",
    )
  }
}

///|
fn ConditionalRules::statistical_match(
  self : ConditionalRules,
  rule : ConditionalRule,
  address : Address,
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  guard calculated_cell(sheets, values, index, address) is Number(actual) else {
    return false
  }
  let bounds = self.scales
    .get(rule.priority)
    .unwrap_or_else(() => {
      let numbers : Array[Double] = []
      for cell in sheets[index].cells.values() {
        work.spend()
        if rule.ranges.any(range => {
            work.spend()
            range.contains(cell.address)
          }) &&
          calculated_cell(sheets, values, index, cell.address) is Number(value) {
          numbers.push(value)
        }
      }
      let bounds : Array[Double] = []
      if !numbers.is_empty() {
        if rule.rank is Some(rank) {
          work.spend(amount=numbers.length() * 13)
          numbers.sort_by((a, b) => {
            if a < b {
              -1
            } else if a > b {
              1
            } else {
              0
            }
          })
          let count = (if rank.percent {
              numbers.length() * rank.rank / 100
            } else {
              rank.rank
            })
            .max(1)
            .min(numbers.length())
          bounds.push(
            numbers[if rank.bottom {
              count - 1
            } else {
              numbers.length() - count
            }],
          )
        } else if rule.average is Some(average) {
          let origin = numbers[0]
          let mut mean = 0.0
          for i, number in numbers {
            work.spend()
            mean += (number - origin - mean) / (i + 1).to_double()
          }
          let deviation = if average.stdDev == 0 {
            0.0
          } else {
            guard variance_result(numbers, false, work) is Number(variance) else {
              @failure.reject(
                "limit-exceeded", "Conditional variance exceeds numeric range",
              )
            }
            variance.sqrt() * average.stdDev.to_double()
          }
          let threshold = origin +
            mean +
            (if average.above { deviation } else { -deviation })
          guard !threshold.is_nan() && !threshold.is_inf() else {
            @failure.reject(
              "limit-exceeded", "Conditional average exceeds numeric range",
            )
          }
          bounds.push(threshold)
        }
      }
      self.scales[rule.priority] = bounds
      bounds
    })
  guard bounds is [threshold] else { return false }
  if rule.rank is Some(rank) {
    return if rank.bottom { actual <= threshold } else { actual >= threshold }
  }
  let average = rule.average.unwrap()
  (if average.above { actual > threshold } else { actual < threshold }) ||
  (average.equal && actual == threshold)
}
