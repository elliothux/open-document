///|
fn xlsx_conditional_settings(
  rule : Json,
) -> @xlsx.ConditionalFormat raise @failure.Failure {
  guard rule is { "format": format, .. } else {
    @failure.reject("invalid-operation", "Conditional format is required")
  }
  {
    kind: field_string(rule, "kind"),
    operator: field_string(rule, "operator"),
    formula1: field_string(rule, "formula1"),
    formula2: field_string(rule, "formula2"),
    stopIfTrue: xlsx_boolean(rule, "stopIfTrue"),
    format: xlsx_cell_format(format),
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
        showValue: xlsx_boolean(bar, "showValue"),
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
      stops.map(stop => @xlsx.ConditionalStop::{
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
) -> @xlsx.DataValidation raise @failure.Failure {
  {
    kind: field_string(rule, "kind"),
    operator: field_string(rule, "operator"),
    formula1: field_string(rule, "formula1"),
    formula2: field_string(rule, "formula2"),
    allowBlank: xlsx_boolean(rule, "allowBlank"),
    showErrorMessage: xlsx_boolean(rule, "showErrorMessage"),
    errorStyle: field_string(rule, "errorStyle"),
    errorTitle: field_string(rule, "errorTitle"),
    error: field_string(rule, "error"),
    showInputMessage: xlsx_boolean(rule, "showInputMessage"),
    promptTitle: field_string(rule, "promptTitle"),
    prompt: field_string(rule, "prompt"),
    showDropDown: xlsx_boolean(rule, "showDropDown"),
  }
}
