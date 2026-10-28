///|
pub(all) struct ConditionalIconThreshold {
  kind : String
  value : String
  greaterOrEqual : Bool
} derive(Eq, ToJson)

///|
pub extend ConditionalIconThreshold with Eq::{equal, not_equal}

///|
pub extend ConditionalIconThreshold with ToJson::{to_json}

///|
pub(all) struct IconSet {
  kind : String
  reverse : Bool
  showValue : Bool
  percent : Bool
  thresholds : Array[ConditionalIconThreshold]
} derive(Eq, ToJson)

///|
pub extend IconSet with Eq::{equal, not_equal}

///|
pub extend IconSet with ToJson::{to_json}

///|
priv struct ConditionalIcon {
  kind : String
  index : Int32
  showValue : Bool
} derive(Eq)

///|
fn Session::cell_icon_matches(
  self : Session,
  index : Int32,
  address : Address,
  set : String,
  id : Int32?,
  rules : ConditionalRules,
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  let current = self.sheets[index]
  let style = rules.applied(
    self.styles[current.style_at(address)],
    address,
    self.sheets,
    index,
    self.calculation.map(c => c.values).unwrap_or(Map([])),
    work,
  )
  guard style.diagnostic.is_empty() else {
    @failure.reject("protected-content", style.diagnostic)
  }
  match (style.icon, id) {
    (Some(icon), Some(id)) => icon.kind == set && icon.index == id
    (None, None) => true
    _ => false
  }
}

///|
fn conditional_icon_count(kind : String) -> Int32 {
  match kind {
    "3Arrows"
    | "3ArrowsGray"
    | "3TrafficLights1"
    | "3Flags"
    | "3Signs"
    | "3Symbols"
    | "3Symbols2"
    | "3TrafficLights2" => 3
    "4Arrows" | "4ArrowsGray" | "4Rating" | "4RedToBlack" | "4TrafficLights" =>
      4
    "5Arrows" | "5ArrowsGray" | "5Rating" | "5Quarters" => 5
    _ => 0
  }
}

///|
fn IconSet::check(
  self : IconSet,
  anchor : Address,
  sheets : Array[Sheet],
  index : Int32,
  work : FormulaWork,
) -> Unit raise @failure.Failure {
  guard conditional_icon_count(self.kind) > 0 &&
    self.thresholds.length() == conditional_icon_count(self.kind) else {
    @failure.reject(
      "invalid-operation", "Unsupported conditional icon set or threshold count",
    )
  }
  for threshold in self.thresholds {
    ConditionalStop::{
      kind: threshold.kind,
      value: threshold.value,
      color: "000000",
    }.check(anchor, sheets, index, work)
  }
}

///|
fn read_conditional_icons(
  tree : Tree,
  node : @xml.Node,
  anchor : Address,
  sheets : Array[Sheet],
  index : Int32,
  work : FormulaWork,
) -> IconSet raise @failure.Failure {
  conditional_node(tree, node, ["iconSet", "showValue", "percent", "reverse"], [
    "cfvo",
  ])
  let icons : IconSet = {
    kind: node.attribute("iconSet").unwrap_or("3TrafficLights1"),
    reverse: flag(node, "reverse"),
    showValue: flag(node, "showValue", fallback=true),
    percent: flag(node, "percent", fallback=true),
    thresholds: tree
    .all(node.id, "cfvo")
    .map(node => {
      conditional_node(tree, node, ["type", "val", "gte"], [])
      let kind = node.attribute("type").unwrap_or("")
      {
        kind,
        value: if kind == "min" || kind == "max" {
          ""
        } else {
          node.attribute("val").unwrap_or("")
        },
        greaterOrEqual: flag(node, "gte", fallback=true),
      }
    }),
  }
  icons.check(anchor, sheets, index, work)
  icons
}

///|
fn ConditionalRules::icon(
  self : ConditionalRules,
  rule : ConditionalRule,
  address : Address,
  sheets : Array[Sheet],
  index : Int32,
  values : Map[(Int32, String), Value],
  work : FormulaWork,
) -> ConditionalIcon? raise @failure.Failure {
  guard rule.icons is Some(icons) &&
    calculated_cell(sheets, values, index, address) is Number(value) else {
    return None
  }
  let bounds = self.scale_bounds(rule, sheets, index, values, work)
  let last = icons.thresholds.length() - 1
  guard bounds.length() == last + 1 else { return None }
  let selected = for i = last; i >= 0; i = i - 1 {
    if value > bounds[i] ||
      (value == bounds[i] && icons.thresholds[i].greaterOrEqual) {
      break if icons.reverse { last - i } else { i }
    }
  } nobreak {
    0
  }
  Some({ kind: icons.kind, index: selected, showValue: icons.showValue, })
}

///|
fn IconSet::markup(
  self : IconSet,
  priority : Int32,
) -> String raise @failure.Failure {
  let thresholds = self.thresholds
    .map(stop => {
      "<od:cfvo type=\"\{stop.kind}\" gte=\"\{if stop.greaterOrEqual {1} else {0}}\"" +
      (if stop.value.is_empty() {
        ""
      } else {
        " val=\"\{escaped_attribute(stop.value)}\""
      }) +
      "/>"
    })
    .join("")
  "<od:cfRule xmlns:od='\{spreadsheet_uri}' type='iconSet' priority='\{priority}'><od:iconSet iconSet='\{self.kind}' reverse='\{if self.reverse {1} else {0}}' showValue='\{if self.showValue {1} else {0}}' percent='\{if self.percent {1} else {0}}'>\{thresholds}</od:iconSet></od:cfRule>"
}
