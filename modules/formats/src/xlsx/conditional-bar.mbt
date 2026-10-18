///|
pub(all) struct ConditionalThreshold {
  kind : String
  value : String
} derive(Eq, ToJson)

///|
pub extend ConditionalThreshold with Eq::{equal, not_equal}

///|
pub extend ConditionalThreshold with ToJson::{to_json}

///|
pub(all) struct DataBar {
  minimum : ConditionalThreshold
  maximum : ConditionalThreshold
  color : String
  showValue : Bool
  minLength : Int
  maxLength : Int
} derive(Eq, ToJson)

///|
pub extend DataBar with Eq::{equal, not_equal}

///|
pub extend DataBar with ToJson::{to_json}

///|
priv struct ConditionalBar {
  fraction : Double
  reverse : Bool
  color : String
  showValue : Bool
  minLength : Int
  maxLength : Int
} derive(Eq)

///|
fn DataBar::check(
  self : DataBar,
  anchor : Address,
  sheets : Array[Sheet],
  index : Int,
  work : FormulaWork,
) -> Unit raise @failure.Failure {
  guard self.minLength >= 0 &&
    self.minLength <= self.maxLength &&
    self.maxLength <= 100 else {
    @failure.reject("invalid-operation", "Invalid data bar length percentages")
  }
  for threshold in [self.minimum, self.maximum] {
    ConditionalStop::{
      kind: threshold.kind,
      value: threshold.value,
      color: self.color,
    }.check(anchor, sheets, index, work)
  }
}

///|
fn read_conditional_bar(
  tree : Tree,
  node : @xml.Node,
  theme : Array[String],
  anchor : Address,
  sheets : Array[Sheet],
  index : Int,
  work : FormulaWork,
) -> DataBar raise @failure.Failure {
  conditional_node(tree, node, ["minLength", "maxLength", "showValue"], [
    "cfvo", "color",
  ])
  let thresholds = tree.all(node.id, "cfvo")
  let colors = tree.all(node.id, "color")
  guard thresholds.length() == 2 && colors.length() == 1 else {
    @failure.reject(
      "malformed-xlsx", "Data bars require two thresholds and one color",
    )
  }
  let thresholds = thresholds.map(node => {
    conditional_node(tree, node, ["type", "val", "gte"], [])
    ignore(flag(node, "gte", fallback=true))
    let kind = node.attribute("type").unwrap_or("")
    ConditionalThreshold::{
      kind,
      value: if kind == "min" || kind == "max" {
        ""
      } else {
        node.attribute("val").unwrap_or("")
      },
    }
  })
  let bar : DataBar = {
    minimum: thresholds[0],
    maximum: thresholds[1],
    color: conditional_color(tree, colors[0], theme),
    showValue: flag(node, "showValue", fallback=true),
    minLength: natural(node.attribute("minLength").unwrap_or("10"), 100),
    maxLength: natural(node.attribute("maxLength").unwrap_or("90"), 100),
  }
  bar.check(anchor, sheets, index, work)
  bar
}

///|
fn ConditionalRules::data_bar(
  self : ConditionalRules,
  rule : ConditionalRule,
  address : Address,
  sheets : Array[Sheet],
  index : Int,
  values : Map[(Int, String), Value],
  work : FormulaWork,
) -> ConditionalBar? raise @failure.Failure {
  guard rule.bar is Some(bar) &&
    calculated_cell(sheets, values, index, address) is Number(value) else {
    return None
  }
  let bounds = self.scale_bounds(rule, sheets, index, values, work)
  guard bounds.length() == 2 else { return None }
  let low = bounds[0]
  let high = bounds[1]
  let reverse = high <= 0
  let fraction = if high == low {
    0.0
  } else {
    let part = (value.max(low).min(high) / 2 - low / 2) / (high / 2 - low / 2)
    if reverse {
      1 - part
    } else {
      part
    }
  }
  Some({
    fraction,
    reverse,
    color: bar.color,
    showValue: bar.showValue,
    minLength: bar.minLength,
    maxLength: bar.maxLength,
  })
}

///|
fn ConditionalBar::paint(
  self : ConditionalBar,
  page : PagePaint,
  cell : @layout.Border,
) -> Unit raise @failure.Failure {
  // ONLYOFFICE legacy data bars use one-pixel insets and lighten the end by 82.8%.
  let available = (cell.width - 2.25).max(0)
  let minimum = (available * self.minLength.to_double() / 100 / 0.75).floor() *
    0.75
  let maximum = (available * self.maxLength.to_double() / 100 / 0.75).floor() *
    0.75
  let width = minimum + self.fraction * (maximum - minimum)
  if width <= 0 || cell.height <= 2.25 {
    return
  }
  let end = StringBuilder()
  let digits = "0123456789abcdef"
  for offset in [0, 2, 4] {
    let channel = @string.parse_int(self.color[offset:offset + 2], base=16) catch {
      _ => @failure.reject("invalid-drawing", "Invalid data bar color")
    }
    let light = (channel.to_double() + 0.828 * (255 - channel).to_double() + 0.5)
      .floor()
      .to_int()
    end.write_char(digits.get_char(light / 16).unwrap())
    end.write_char(digits.get_char(light % 16).unwrap())
  }
  let end = end.to_string()
  page.bars.push(
    GradientRectangle(
      {
        x: cell.x + 0.75 + (if self.reverse { available - width } else { 0 }),
        y: cell.y + 0.75,
        width,
        height: cell.height - 2.25,
      },
      [
        {
          opacity: 1,
          position: 0,
          color: if self.reverse {
            end
          } else {
            self.color
          },
        },
        {
          opacity: 1,
          position: 1,
          color: if self.reverse {
            self.color
          } else {
            end
          },
        },
      ],
    ),
  )
}
