///|
fn xlsx_sparkline_edit(change : Json) -> @xlsx.SheetEdit raise @failure.Failure {
  guard change is Object(fields) &&
    fields.length() == 4 &&
    fields.keys().all(k => ["action", "cell", "source", "kind"].contains(k)) &&
    fields.get("source") is Some(source) else {
    @failure.reject("invalid-operation", "Invalid sparkline command")
  }
  @xlsx.Sparkline(
    field_string(change, "cell"),
    if source is Null {
      None
    } else {
      Some(field_string(change, "source"))
    },
    field_string(change, "kind"),
  )
}
