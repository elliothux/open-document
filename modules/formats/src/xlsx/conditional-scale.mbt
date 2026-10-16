///|
pub(all) struct ConditionalStop {
  kind : String
  value : String
  color : String
} derive(Eq, ToJson)

///|
pub extend ConditionalStop with Eq::{equal, not_equal}

///|
pub extend ConditionalStop with ToJson::{to_json}

///|
fn ConditionalStop::check(
  self : ConditionalStop,
  anchor : Address,
  sheets : Array[Sheet],
  index : Int,
  work : FormulaWork,
) -> Unit raise @failure.Failure {
  work.spend(amount=self.value.length())
  guard ["min", "max", "num", "percent", "percentile", "formula"].contains(
      self.kind,
    ) &&
    self.value.length() <= 8192 &&
    @xml.valid_text(self.value) &&
    self.color.length() == 6 &&
    self.color.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject("invalid-operation", "Invalid color scale stop")
  }
  if self.kind == "min" || self.kind == "max" {
    guard self.value.is_empty() else {
      @failure.reject(
        "invalid-operation", "Automatic color scale stops have no value",
      )
    }
  } else if self.kind == "formula" {
    guard !self.value.is_empty() else {
      @failure.reject("invalid-operation", "Missing color scale formula")
    }
    ignore(rule_expression(self.value, anchor, anchor, sheets, index, work))
  } else {
    let value = number(self.value) catch {
      @failure.Failure(..) =>
        @failure.reject("invalid-operation", "Invalid color scale threshold")
    }
    guard self.kind == "num" || (value >= 0 && value <= 100) else {
      @failure.reject(
        "invalid-operation", "Color scale percent must be between zero and 100",
      )
    }
  }
}

///|
fn read_conditional_scale(
  tree : Tree,
  node : @xml.Node,
  theme : Array[String],
  anchor : Address,
  sheets : Array[Sheet],
  index : Int,
  work : FormulaWork,
) -> Array[ConditionalStop] raise @failure.Failure {
  conditional_node(tree, node, [], ["cfvo", "color"])
  let thresholds = tree.all(node.id, "cfvo")
  let colors = tree.all(node.id, "color")
  guard [2, 3].contains(thresholds.length()) &&
    colors.length() == thresholds.length() else {
    @failure.reject(
      "malformed-xlsx", "Color scales require two or three matching stops",
    )
  }
  thresholds.mapi((i, node) => {
    conditional_node(tree, node, ["type", "val", "gte"], [])
    ignore(flag(node, "gte", fallback=true))
    let kind = node.attribute("type").unwrap_or("")
    let stop : ConditionalStop = {
      kind,
      value: if kind == "min" || kind == "max" {
        ""
      } else {
        node.attribute("val").unwrap_or("")
      },
      color: conditional_color(tree, colors[i], theme),
    }
    stop.check(anchor, sheets, index, work)
    stop
  })
}

///|
fn ConditionalRules::scale_bounds(
  self : ConditionalRules,
  rule : ConditionalRule,
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> Array[Double] raise @failure.Failure {
  if self.scales.get(rule.priority) is Some(bounds) {
    return bounds
  }
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
  if numbers.is_empty() {
    self.scales[rule.priority] = bounds
    return bounds
  }
  let low = numbers.fold(init=numbers[0], (a, b) => a.min(b))
  let high = numbers.fold(init=numbers[0], (a, b) => a.max(b))
  if rule.stops.any(stop => stop.kind == "percentile") {
    let mut levels = 0
    let mut size = numbers.length()
    while size > 1 {
      levels += 1
      size = (size + 1) / 2
    }
    work.spend(amount=numbers.length() * levels)
    numbers.sort()
  }
  for stop in rule.stops {
    work.spend()
    let value = match stop.kind {
      "min" => low
      "max" => high
      "num" => number(stop.value)
      "percent" => {
        let fraction = number(stop.value) / 100
        low * (1 - fraction) + high * fraction
      }
      "percentile" => {
        let position = (numbers.length() - 1).to_double() *
          (number(stop.value) / 100)
        let first = position.floor().to_int()
        let next = (first + 1).min(numbers.length() - 1)
        numbers[first] * (1 - (position - first.to_double())) +
        numbers[next] * (position - first.to_double())
      }
      _ => {
        work.origin = rule.anchor
        let value = rule_expression(
          stop.value,
          rule.anchor,
          rule.anchor,
          sheets,
          index,
          work,
        ).evaluate(sheets, index, values, work, 0)
        guard value is Number(value) else {
          bounds.clear()
          self.scales[rule.priority] = bounds
          return bounds
        }
        value
      }
    }
    guard !value.is_nan() && !value.is_inf() else {
      @failure.reject(
        "limit-exceeded", "Color scale threshold exceeds numeric range",
      )
    }
    bounds.push(value)
  }
  bounds.sort()
  self.scales[rule.priority] = bounds
  bounds
}

///|
fn scale_color(
  first : String,
  last : String,
  fraction : Double,
) -> String raise @failure.Failure {
  // ONLYOFFICE CGradient uses 256 interpolation steps and signed floor per channel.
  let step = (fraction.max(0).min(1) * 256).floor()
  let output = StringBuilder()
  let digits = "0123456789abcdef"
  for offset in [0, 2, 4] {
    let a = @string.parse_int(first[offset:offset + 2], base=16) catch {
      _ => @failure.reject("malformed-xlsx", "Invalid color scale color")
    }
    let b = @string.parse_int(last[offset:offset + 2], base=16) catch {
      _ => @failure.reject("malformed-xlsx", "Invalid color scale color")
    }
    let color = a + ((b - a).to_double() * step / 256).floor().to_int()
    output.write_char(digits.get_char(color / 16).unwrap())
    output.write_char(digits.get_char(color % 16).unwrap())
  }
  output.to_string()
}

///|
fn ConditionalRules::scale_fill(
  self : ConditionalRules,
  rule : ConditionalRule,
  address : Address,
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> String? raise @failure.Failure {
  guard calculated_cell(sheets, values, index, address) is Number(value) else {
    return None
  }
  let bounds = self.scale_bounds(rule, sheets, index, values, work)
  if bounds.is_empty() {
    return None
  }
  if value >= bounds.last().unwrap() {
    return Some(rule.stops.last().unwrap().color)
  }
  if value <= bounds[0] {
    return Some(rule.stops[0].color)
  }
  let first = if bounds.length() == 3 && value > bounds[1] { 1 } else { 0 }
  Some(
    scale_color(
      rule.stops[first].color,
      rule.stops[first + 1].color,
      (value / 2 - bounds[first] / 2) /
      (bounds[first + 1] / 2 - bounds[first] / 2),
    ),
  )
}
