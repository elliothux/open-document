///|
fn page_setup_format(
  request : Json,
) -> @layout.PageSetup raise @failure.Failure {
  guard request is { "page": Object(fields), .. } &&
    (fields.length() == 6 || fields.length() == 7) &&
    fields
    .keys()
    .all(key => {
      ["width", "height", "top", "right", "bottom", "left", "orientation"].contains(
        key,
      )
    }) else {
    @failure.reject("invalid-operation", "Invalid page setup fields")
  }
  fn number(
    fields : Map[String, Json],
    name : String,
  ) -> Double raise @failure.Failure {
    guard fields.get(name) is Some(Number(value, ..)) else {
      @failure.reject("invalid-operation", "Invalid page setup number")
    }
    value
  }
  {
    width: number(fields, "width"),
    height: number(fields, "height"),
    top: number(fields, "top"),
    right: number(fields, "right"),
    bottom: number(fields, "bottom"),
    left: number(fields, "left"),
  }
}

///|
fn page_orientation(request : Json) -> String? raise @failure.Failure {
  if request is { "page": Object(fields) as page, .. } &&
    fields.contains("orientation") {
    Some(field_string(page, "orientation"))
  } else {
    None
  }
}

///|
fn page_border_format(
  request : Json,
) -> @layout.PageBorders? raise @failure.Failure {
  guard request is { "borders": raw, .. } else {
    @failure.reject("invalid-operation", "Page borders are required")
  }
  if raw is Null {
    return None
  }
  guard raw is Object(fields) &&
    fields
    .keys()
    .all(k => ["offsetFrom", "display", "zOrder", "sides"].contains(k)) &&
    fields.get("sides") is Some(Array(sides)) &&
    sides.length() <= 4 else {
    @failure.reject("invalid-operation", "Invalid page border fields")
  }
  Some({
    offsetFrom: field_string(raw, "offsetFrom"),
    display: field_string(raw, "display"),
    zOrder: field_string(raw, "zOrder"),
    sides: sides.map(side => {
      guard side is Object(fields) &&
        fields.keys().all(k => ["side", "color", "width", "space"].contains(k)) else {
        @failure.reject("invalid-operation", "Unknown page border side field")
      }
      {
        side: field_string(side, "side"),
        color: field_string(side, "color"),
        width: xlsx_number(side, "width"),
        space: xlsx_number(side, "space"),
      }
    }),
  })
}

///|
fn running_content(
  request : Json,
) -> Array[@docx.RunningContent] raise @failure.Failure {
  guard request is { "content": Array(content), .. } && content.length() <= 256 else {
    @failure.reject(
      "invalid-operation", "Running content requires at most 256 items",
    )
  }
  content.map(item => {
    guard item is Object(fields) &&
      (fields.length() == 1 || fields.length() == 2) else {
      @failure.reject("invalid-operation", "Invalid running content item")
    }
    match item {
      { "field": String(code), "format": String(format), .. } if fields.length() ==
        2 => @docx.RunningContent::FormattedField(code, format)
      { "text": String(text), .. } if fields.length() == 1 =>
        @docx.RunningContent::Text(text)
      { "field": String(code), .. } if fields.length() == 1 =>
        @docx.RunningContent::Field(code)
      _ => @failure.reject("invalid-operation", "Invalid running content item")
    }
  })
}

///|
fn Foundation::docx_page(
  self : Foundation,
  session : @docx.Session,
  operation : String,
  request : Json,
) -> Json raise @failure.Failure {
  let revision = field_int(request, "revision")
  if operation == "runningArea" {
    return session.running_area(
      revision,
      field_string(request, "kind"),
      field_string(request, "variant"),
    )
  }
  if operation == "pageSetup" {
    return session.page_setup(revision)
  }
  let result = match operation {
    "updateBodyPageFields" =>
      session.update_body_page_fields(
        revision,
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "setPageColumns" => {
      guard request is { "columns": columns, .. } else {
        @failure.reject("invalid-operation", "Column settings are required")
      }
      let value = match columns {
        Null => None
        Object(fields) if fields.length() == 4 &&
          fields
          .keys()
          .all(key => ["count", "gap", "separator", "custom"].contains(key)) =>
          Some(
            @layout.Columns::new(
              count=field_int(columns, "count"),
              gap=xlsx_number(columns, "gap"),
              separator=xlsx_boolean(columns, "separator"),
              custom=match fields.get("custom") {
                Some(Array(items)) if items.length() <= 12 =>
                  items.map(item => {
                    guard item is Object(values) &&
                      values.length() == 2 &&
                      values.keys().all(key => ["width", "gap"].contains(key)) else {
                      @failure.reject(
                        "invalid-operation", "Invalid custom column",
                      )
                    }
                    @layout.Column::{
                      width: xlsx_number(item, "width"),
                      gap: xlsx_number(item, "gap"),
                    }
                  })
                _ =>
                  @failure.reject(
                    "invalid-operation", "Invalid custom column list",
                  )
              },
            ),
          )
        _ => @failure.reject("invalid-operation", "Invalid column settings")
      }
      session.set_page_columns(
        revision,
        value,
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    }
    "setPageNumbering" => {
      guard request is { "numbering": numbering, .. } else {
        @failure.reject("invalid-operation", "Page numbering is required")
      }
      let value = match numbering {
        Null => None
        Object(fields) if fields.length() == 2 &&
          fields.keys().all(k => ["start", "format"].contains(k)) => {
          let start = xlsx_number(numbering, "start")
          guard start >= 0 && start <= 4294967295 && start.floor() == start else {
            @failure.reject("invalid-operation", "Invalid page numbering start")
          }
          Some(@layout.PageNumbering::{
            start: start.to_int64(),
            format: field_string(numbering, "format"),
          })
        }
        _ => @failure.reject("invalid-operation", "Invalid page numbering")
      }
      session.set_page_numbering(
        revision,
        value,
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    }
    "unlinkRunningArea" =>
      session.unlink_running_area(
        revision,
        field_string(request, "kind"),
        field_string(request, "variant"),
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "setRunningOptions" =>
      session.set_running_options(
        revision,
        xlsx_boolean(request, "first"),
        xlsx_boolean(request, "even"),
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "setRunningArea" =>
      session.set_running_area(
        revision,
        field_string(request, "kind"),
        field_string(request, "variant"),
        running_content(request),
        xlsx_number(request, "distance"),
        probe=self.probe,
        profile=xlsx_profile(request),
        images=self.images,
      )
    "setPageSetup" =>
      session.set_page_setup(
        revision,
        page_setup_format(request),
        orientation=page_orientation(request),
      )
    "setPageBackground" =>
      session.set_page_background(revision, page_background_color(request))
    "setPageBorders" =>
      session.set_page_borders(revision, page_border_format(request))
    _ => @failure.reject("invalid-operation", "Unknown document page command")
  }
  if result is { "revision": Number(current, ..), .. } &&
    current != revision.to_double() {
    self.layout = None
  }
  result
}
