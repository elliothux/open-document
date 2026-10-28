///|
fn xlsx_chart_settings(
  value : Json,
) -> @model.SheetChartSettings raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 8 &&
    fields
    .keys()
    .all(key => {
      [
        "kind", "title", "label", "legend", "holeSize", "categories", "names", "values",
      ].contains(key)
    }) else {
    @failure.reject("invalid-operation", "Chart settings require known fields")
  }
  let refs = fn(name : String) raise @failure.Failure {
    guard fields.get(name) is Some(Array(items)) && items.length() <= 8 else {
      @failure.reject(
        "invalid-operation", "Chart reference list exceeds limits",
      )
    }
    items.map(value => {
      match value {
        String(value) => value
        _ =>
          @failure.reject("invalid-operation", "Chart reference must be text")
      }
    })
  }
  {
    kind: field_string(value, "kind"),
    title: field_string(value, "title"),
    label: field_string(value, "label"),
    legend: field_string(value, "legend"),
    hole_size: if fields.get("holeSize") == Some(Json::null()) {
      None
    } else {
      Some(field_int(value, "holeSize"))
    },
    categories: field_string(value, "categories"),
    names: refs("names"),
    values: refs("values"),
  }
}

///|
fn Context::xlsx_chart_operation(
  self : Context,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  guard self.xlsx is Some(session) else {
    @failure.reject("session-required", "Open an XLSX workbook first")
  }
  let revision = field_int(request, "revision")
  let sheet = field_string(request, "sheet")
  let profile = font_profile(request)
  match operation {
    "getXlsxChart" => session.charts(revision, sheet, self.probe, profile)
    "insertXlsxChart" | "setXlsxChart" => {
      guard request is { "settings": settings, .. } else {
        @failure.reject("invalid-operation", "Chart settings required")
      }
      let settings = xlsx_chart_settings(settings)
      if operation == "insertXlsxChart" {
        session.insert_chart(
          revision,
          sheet,
          settings,
          field_number(request, "width"),
          field_number(request, "height"),
          self.probe,
          profile,
        )
      } else {
        session.set_chart(
          revision,
          sheet,
          field_string(request, "id"),
          settings,
          self.probe,
          profile,
        )
      }
    }
    "insertRangeXlsxChart" =>
      session.insert_chart_range(
        revision,
        sheet,
        field_string(request, "range"),
        field_string(request, "kind"),
        field_string(request, "title"),
        field_number(request, "width"),
        field_number(request, "height"),
        self.probe,
        profile,
      )
    "frameXlsxChart" => {
      guard request is { "settings": settings, .. } else {
        @failure.reject("invalid-operation", "Chart frame settings required")
      }
      session.set_chart_frame(
        revision,
        sheet,
        field_string(request, "id"),
        field_string(settings, "anchor"),
        {
          x: field_number(settings, "x"),
          y: field_number(settings, "y"),
          width: field_number(settings, "width"),
          height: field_number(settings, "height"),
        },
        field_string(settings, "name"),
        field_string(settings, "description"),
        self.probe,
        profile,
      )
    }
    "deleteXlsxChart" =>
      session.delete_chart(
        revision,
        sheet,
        field_string(request, "id"),
        self.probe,
        profile,
      )
    _ =>
      @failure.reject("invalid-operation", "Unknown worksheet chart operation")
  }
}
