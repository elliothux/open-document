///|
fn xlsx_conditional_settings(
  rule : Json,
) -> @model.ConditionalFormat raise @failure.Failure {
  guard rule is { "format": format, .. } else {
    @failure.reject("invalid-operation", "Conditional format is required")
  }
  {
    kind: field_string(rule, "kind"),
    operator: field_string(rule, "operator"),
    formula1: field_string(rule, "formula1"),
    formula2: field_string(rule, "formula2"),
    text: if rule is { "text": value, .. } {
      guard value is String(text) else {
        @failure.reject(
          "invalid-operation", "Conditional text must be a string",
        )
      }
      Some(text)
    } else {
      None
    },
    stopIfTrue: field_boolean(rule, "stopIfTrue"),
    timePeriod: if rule is { "timePeriod": value, .. } {
      guard value is String(period) else {
        @failure.reject(
          "invalid-operation", "Conditional period must be a string",
        )
      }
      Some(period)
    } else {
      None
    },
    format: xlsx_cell_format(format),
    icons: if rule is { "icons": icons, .. } {
      guard icons is { "thresholds": Array(thresholds), .. } &&
        thresholds.length() >= 3 &&
        thresholds.length() <= 5 else {
        @failure.reject(
          "invalid-operation", "Three to five icon thresholds are required",
        )
      }
      Some({
        kind: field_string(icons, "kind"),
        reverse: field_boolean(icons, "reverse"),
        showValue: field_boolean(icons, "showValue"),
        percent: field_boolean(icons, "percent"),
        thresholds: thresholds.map(t => {
          kind: field_string(t, "kind"),
          value: field_string(t, "value"),
          greaterOrEqual: field_boolean(t, "greaterOrEqual"),
        }),
      })
    } else {
      None
    },
    rank: if rule is { "rank": rank, .. } {
      guard rank is Object(fields) && fields.length() == 3 else {
        @failure.reject("invalid-operation", "Invalid conditional rank fields")
      }
      Some({
        rank: field_int(rank, "rank"),
        percent: field_boolean(rank, "percent"),
        bottom: field_boolean(rank, "bottom"),
      })
    } else {
      None
    },
    average: if rule is { "average": average, .. } {
      guard average is Object(fields) && fields.length() == 3 else {
        @failure.reject(
          "invalid-operation", "Invalid conditional average fields",
        )
      }
      Some({
        above: field_boolean(average, "above"),
        equal: field_boolean(average, "equal"),
        stdDev: field_int(average, "stdDev"),
      })
    } else {
      None
    },
    bar: if field_string(rule, "kind") == "dataBar" {
      guard rule is { "bar": bar, .. } &&
        bar is { "minimum": minimum, "maximum": maximum, .. } else {
        @failure.reject("invalid-operation", "Data bar settings are required")
      }
      Some({
        minimum: {
          kind: field_string(minimum, "kind"),
          value: field_string(minimum, "value"),
        },
        maximum: {
          kind: field_string(maximum, "kind"),
          value: field_string(maximum, "value"),
        },
        color: field_string(bar, "color"),
        showValue: field_boolean(bar, "showValue"),
        minLength: field_int(bar, "minLength"),
        maxLength: field_int(bar, "maxLength"),
      })
    } else {
      None
    },
    stops: if field_string(rule, "kind") == "colorScale" {
      guard rule is { "stops": Array(stops), .. } &&
        [2, 3].contains(stops.length()) else {
        @failure.reject(
          "invalid-operation", "Color scale requires two or three stops",
        )
      }
      stops.map(stop => @model.ConditionalStop::{
        kind: field_string(stop, "kind"),
        value: field_string(stop, "value"),
        color: field_string(stop, "color"),
      })
    } else {
      []
    },
  }
}

///|
fn xlsx_validation_settings(
  rule : Json,
) -> @model.DataValidation raise @failure.Failure {
  {
    kind: field_string(rule, "kind"),
    operator: field_string(rule, "operator"),
    formula1: field_string(rule, "formula1"),
    formula2: field_string(rule, "formula2"),
    allowBlank: field_boolean(rule, "allowBlank"),
    showErrorMessage: field_boolean(rule, "showErrorMessage"),
    errorStyle: field_string(rule, "errorStyle"),
    errorTitle: field_string(rule, "errorTitle"),
    error: field_string(rule, "error"),
    showInputMessage: field_boolean(rule, "showInputMessage"),
    promptTitle: field_string(rule, "promptTitle"),
    prompt: field_string(rule, "prompt"),
    showDropDown: field_boolean(rule, "showDropDown"),
  }
}
