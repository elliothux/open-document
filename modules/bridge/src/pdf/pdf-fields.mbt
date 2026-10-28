///|
fn pdf_field_design(
  value : Json,
) -> @model.PdfFieldDesign raise @failure.Failure {
  guard value
    is {
      "placement": placement,
      "options": Array(options),
      "value": current,
      "defaultValue": defaultValue,
      ..
    } &&
    options.length() <= 4096 else {
    @failure.reject(
      "invalid-operation", "Field design specification is required",
    )
  }
  {
    name: field_string(value, "name"),
    tooltip: field_string(value, "tooltip"),
    kind: field_string(value, "kind"),
    placement: pdf_placement(placement),
    options: options.map(option => {
      (field_string(option, "value"), field_string(option, "label"))
    }),
    value: current,
    defaultValue,
    readOnly: field_boolean(value, "readOnly"),
    required: field_boolean(value, "required"),
    multiline: field_boolean(value, "multiline"),
    multiSelect: field_boolean(value, "multiSelect"),
    maxLength: field_int(value, "maxLength"),
    font: field_string(value, "font"),
    size: field_number(value, "size"),
    color: field_string(value, "color"),
    background: field_string(value, "background"),
    border: field_number(value, "border"),
  }
}
