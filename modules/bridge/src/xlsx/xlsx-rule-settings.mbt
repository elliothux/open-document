///|
priv struct ConditionalRuleRequest {
  kind : String
  operator : String
  formula1 : String
  formula2 : String
  stopIfTrue : Bool
  format : CellFormatRequest
  text : String?
  timePeriod : String?
  icons : @model.IconSet?
  rank : ConditionalRankRequest?
  average : ConditionalAverageRequest?
} derive(@json.FromJson)

///|
priv struct ConditionalRankRequest {
  rank : @common.RequestInt
  percent : Bool
  bottom : Bool
} derive(@json.FromJson)

///|
priv struct ConditionalAverageRequest {
  above : Bool
  equal : Bool
  stdDev : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct DataBarRequest {
  minimum : @model.ConditionalThreshold
  maximum : @model.ConditionalThreshold
  color : String
  showValue : Bool
  minLength : @common.RequestInt
  maxLength : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct ConditionalSettingsRequest {
  value : @model.ConditionalFormat
}

///|
impl @json.FromJson for ConditionalSettingsRequest with fn from_json(rule, path) {
  guard rule is Object(fields) &&
    !(fields.get("text") is Some(Null)) &&
    !(fields.get("timePeriod") is Some(Null)) else {
    raise @json.JsonDecodeError((path, "Invalid conditional rule settings"))
  }
  if fields.get("icons") is Some(icons) {
    guard icons is { "thresholds": Array(thresholds), .. } &&
      thresholds.length() >= 3 &&
      thresholds.length() <= 5 else {
      raise @json.JsonDecodeError(
        (path.add_key("icons"), "Three to five icon thresholds are required"),
      )
    }
  }
  for key in ["rank", "average"] {
    if fields.get(key) is Some(value) {
      guard value is Object(settings) && settings.length() == 3 else {
        raise @json.JsonDecodeError(
          (path.add_key(key), "Invalid conditional \{key} fields"),
        )
      }
    }
  }
  let request : ConditionalRuleRequest = @json.from_json(rule, path~)
  let value : @model.ConditionalFormat = {
    kind: request.kind,
    operator: request.operator,
    formula1: request.formula1,
    formula2: request.formula2,
    text: request.text,
    stopIfTrue: request.stopIfTrue,
    timePeriod: request.timePeriod,
    format: request.format.value,
    icons: request.icons,
    rank: request.rank.map(rank => {
      rank: rank.rank.value,
      percent: rank.percent,
      bottom: rank.bottom,
    }),
    average: request.average.map(average => {
      above: average.above,
      equal: average.equal,
      stdDev: average.stdDev.value,
    }),
    bar: if request.kind == "dataBar" {
      guard fields.get("bar") is Some(bar) else {
        raise @json.JsonDecodeError(
          (path.add_key("bar"), "Data bar settings are required"),
        )
      }
      let request : DataBarRequest = @json.from_json(
        bar,
        path=path.add_key("bar"),
      )
      Some({
        minimum: request.minimum,
        maximum: request.maximum,
        color: request.color,
        showValue: request.showValue,
        minLength: request.minLength.value,
        maxLength: request.maxLength.value,
      })
    } else {
      None
    },
    stops: if request.kind == "colorScale" {
      guard fields.get("stops") is Some(Array(stops) as raw_stops) &&
        [2, 3].contains(stops.length()) else {
        raise @json.JsonDecodeError(
          (path.add_key("stops"), "Color scale requires two or three stops"),
        )
      }
      @json.from_json(raw_stops, path=path.add_key("stops"))
    } else {
      []
    },
  }
  { value, }
}

///|
fn xlsx_conditional_settings(
  rule : Json,
) -> @model.ConditionalFormat raise @failure.Failure {
  let request : ConditionalSettingsRequest = @common.request(rule)
  request.value
}
