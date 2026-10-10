///|
pub struct Foundation {
  probe : @layout.TextProbe
  mut docx : @docx.Session?
  mut closed : Bool
  mut layout : @layout.Layout?
  images : @layout.Images
  mut layout_id : Int
}

///|
pub fn new_foundation() -> Foundation {
  {
    probe: @layout.TextProbe::new(),
    docx: None,
    closed: false,
    layout: None,
    images: @layout.Images::new(),
    layout_id: 0,
  }
}

///|
fn field_int(json : Json, key : String) -> Int raise @failure.Failure {
  guard json is Object(fields) &&
    fields.get(key) is Some(Number(value, ..)) &&
    value >= 0.0 &&
    value <= 2147483647.0 &&
    value == value.to_int().to_double() else {
    @failure.reject("invalid-operation", "Invalid i32 field: " + key)
  }
  value.to_int()
}

///|
fn field_string(json : Json, key : String) -> String raise @failure.Failure {
  guard json is Object(fields) && fields.get(key) is Some(String(value)) else {
    @failure.reject("invalid-operation", "Invalid string field: " + key)
  }
  value
}

///|
fn input_bytes(json : Json, ceiling : Int) -> Bytes raise @failure.Failure {
  let encoded = field_string(json, "bytes")
  guard encoded.length().to_int64() <= (ceiling.to_int64() + 2) / 3 * 4 else {
    @failure.reject("limit-exceeded", "Encoded byte input exceeds budget")
  }
  let bytes = @base64.decode(encoded) catch {
    _ => @failure.reject("invalid-operation", "Invalid base64 byte input")
  }
  guard bytes.length() <= ceiling else {
    @failure.reject("limit-exceeded", "Byte input exceeds budget")
  }
  bytes
}

///|
fn Foundation::dispatch(
  self : Foundation,
  request : Json,
) -> Json raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "Foundation session is closed")
  }
  let operation = field_string(request, "operation")
  match operation {
    "budget" => {
      let budget = @archive.Budget::default()
      {
        "fileBytes": budget.file_bytes,
        "entryBytes": budget.entry_bytes,
        "totalBytes": budget.total_bytes,
        "retainedBytes": budget.retained_bytes,
        "entries": budget.entries,
        "xmlDepth": budget.xml_depth,
        "outputBytes": budget.output_bytes,
      }
    }
    "font" => {
      let index = self.probe.add_font(
        input_bytes(request, 33554432),
        field_string(request, "identity"),
      )
      self.layout = None
      { "font": index }
    }
    "shape" => {
      guard request is { "size": Number(size, ..), .. } else {
        @failure.reject("invalid-operation", "Invalid font size")
      }
      self.probe
      .shape(
        field_string(request, "text"),
        size,
        field_string(request, "language"),
      )
      .to_json()
    }
    "openDocx" => {
      guard self.docx is None else {
        @failure.reject("invalid-operation", "DOCX session is already open")
      }
      guard request is { "budget": budget, .. } else {
        @failure.reject("invalid-budget", "Explicit budget is required")
      }
      let budget : @archive.Budget = {
        file_bytes: field_int(budget, "fileBytes"),
        entry_bytes: field_int(budget, "entryBytes"),
        total_bytes: field_int(budget, "totalBytes"),
        retained_bytes: field_int(budget, "retainedBytes"),
        entries: field_int(budget, "entries"),
        xml_depth: field_int(budget, "xmlDepth"),
        output_bytes: field_int(budget, "outputBytes"),
      }
      let session = @docx.Session::open(
        input_bytes(request, budget.file_bytes.min(budget.retained_bytes)),
        budget,
      )
      self.docx = Some(session)
      session.query()
    }
    "query"
    | "replaceNode"
    | "saveDocx"
    | "flow"
    | "layout"
    | "exportPdf"
    | "imageBytes"
    | "image" => {
      guard self.docx is Some(session) else {
        @failure.reject("invalid-operation", "Open a DOCX session first")
      }
      match operation {
        "query" => session.query()
        "flow" => session.flow().to_json()
        "imageBytes" =>
          {
            "bytes": @base64.encode(
              session.image_bytes(field_string(request, "key")),
            ),
          }
        "image" => {
          self.images.add(
            field_string(request, "key"),
            field_int(request, "width"),
            field_int(request, "height"),
            input_bytes(request, 16777216),
          )
          self.layout = None
          { "ready": true }
        }
        "layout" => {
          guard request is { "profile": Object(fields), .. } &&
            fields.length() <= 64 else {
            @failure.reject(
              "invalid-operation", "Explicit font profile is required",
            )
          }
          let profile : Map[String, String] = Map([])
          for key, value in fields {
            guard value is String(identity) else {
              @failure.reject(
                "invalid-operation", "Invalid font profile identity",
              )
            }
            profile[key] = identity
          }
          self.layout = None
          let result = @layout.paginate(
            self.probe,
            session.flow(),
            profile,
            self.images,
          )
          self.layout = Some(result)
          self.layout_id += 1
          let json = result.to_json()
          if json is Object(fields) {
            fields["id"] = self.layout_id.to_json()
          }
          json
        }
        "exportPdf" => {
          if request is Object(fields) && fields.get("layoutId") is Some(_) {
            guard field_int(request, "layoutId") == self.layout_id else {
              @failure.reject(
                "stale-layout", "PDF export requires the displayed layout",
              )
            }
          }
          guard self.layout is Some(layout) else {
            @failure.reject(
              "layout-required", "Create a current layout before PDF export",
            )
          }
          {
            "bytes": @base64.encode(
              @pdf.write(
                layout,
                self.probe,
                self.images,
                field_int(request, "outputBytes"),
              ),
            ),
          }
        }
        "replaceNode" => {
          let revision = session.replace(
            field_int(request, "node"),
            field_int(request, "revision"),
            field_string(request, "text"),
          )
          self.layout = None
          { "revision": revision }
        }
        _ => { "bytes": @base64.encode(session.save()) }
      }
    }
    _ => @failure.reject("invalid-operation", "Unknown foundation operation")
  }
}

///|
pub fn foundation_call(context : Foundation, input : String) -> String {
  let result : Json = try {
    guard input.length() <= 50000000 else {
      @failure.reject("limit-exceeded", "ABI input exceeds budget")
    }
    let request = @json.parse(input) catch {
      _ => @failure.reject("invalid-operation", "Invalid request JSON")
    }
    { "ok": true, "value": context.dispatch(request) }
  } catch {
    @failure.Failure(code~, part~, offset~, message~) =>
      {
        "ok": false,
        "error": {
          "code": code,
          "part": part,
          "offset": offset,
          "message": message,
        },
      }
  }
  result.stringify()
}

///|
pub fn foundation_close(context : Foundation) -> Unit {
  context.closed = true
  context.probe.close()
  if context.docx is Some(session) {
    session.close()
  }
  context.docx = None
  context.layout = None
  context.images.clear()
}
