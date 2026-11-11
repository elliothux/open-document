///|
#derive(@json.FromJson)
priv struct PrintRequest {
  revision : @common.RequestInt
  sheet : String
  options : PrintOptionsRequest
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct PaperRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
  left : @common.RequestNumber
  right : @common.RequestNumber
  top : @common.RequestNumber
  bottom : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct PdfExportRequest {
  outputBytes : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct SheetPageSetupRequest {
  paper : String
  orientation : String
  left : @common.RequestNumber
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
  scale : @common.RequestInt
  fitWidth : @common.RequestInt
  fitHeight : @common.RequestInt
}

///|
fn xlsx_sheet_page_setup(
  input : Json,
) -> @model.PrintSetup raise @failure.Failure {
  let request : SheetPageSetupRequest = @common.request(input)
  {
    paper: request.paper,
    orientation: request.orientation,
    left: request.left.value,
    top: request.top.value,
    right: request.right.value,
    bottom: request.bottom.value,
    scale: request.scale.value,
    fitWidth: request.fitWidth.value,
    fitHeight: request.fitHeight.value,
  }
}

///|
#derive(@json.FromJson)
priv struct SheetPrintRangeRequest {
  area : String
  rows : String
  columns : String
}

///|
fn xlsx_sheet_print_range(
  input : Json,
) -> @model.PrintRange raise @failure.Failure {
  let request : SheetPrintRangeRequest = @common.request(input)
  { area: request.area, rows: request.rows, columns: request.columns, }
}

///|
#derive(@json.FromJson)
priv struct SheetHeaderFooterRequest {
  oddHeader : String
  oddFooter : String
  evenHeader : String
  evenFooter : String
  firstHeader : String
  firstFooter : String
  differentFirst : Bool
  differentOddEven : Bool
  scaleWithDoc : Bool
  alignWithMargins : Bool
  headerMargin : @common.RequestNumber
  footerMargin : @common.RequestNumber
}

///|
fn xlsx_sheet_header_footer(
  input : Json,
) -> @model.HeaderFooter raise @failure.Failure {
  let request : SheetHeaderFooterRequest = @common.request(input)
  {
    oddHeader: request.oddHeader,
    oddFooter: request.oddFooter,
    evenHeader: request.evenHeader,
    evenFooter: request.evenFooter,
    firstHeader: request.firstHeader,
    firstFooter: request.firstFooter,
    differentFirst: request.differentFirst,
    differentOddEven: request.differentOddEven,
    scaleWithDoc: request.scaleWithDoc,
    alignWithMargins: request.alignWithMargins,
    headerMargin: request.headerMargin.value,
    footerMargin: request.footerMargin.value,
  }
}

///|
#derive(ToJson)
priv struct PrintResponse {
  id : Int32
  revision : Int32
  sheet : String
  regions : Array[@layout.DrawingRegion]
  images : Array[String]
  outlines : Array[@layout.Outline]
}

///|
priv struct PrintOptions {
  setup : @layout.PageSetup?
  sheets : @model.PrintSheets
  range : String?
}

///|
priv struct PrintOptionsRequest {
  // Sheet selection retains its failure code after the request is decoded.
  value : Result[PrintOptions, String]
}

///|
impl @json.FromJson for PrintOptionsRequest with fn from_json(options, path) {
  if options is Null {
    return {
      value: Ok({ setup: None, sheets: @model.CurrentSheet, range: None, }),
    }
  }
  guard options is Object(fields) else {
    raise @json.JsonDecodeError(
      (path, "Print options must be an object or null"),
    )
  }
  let paper_keys = ["width", "height", "left", "right", "top", "bottom"]
  let setup : @layout.PageSetup? = if paper_keys.any(key => fields.contains(key)) {
    let command : PaperRequest = @json.from_json(options, path~)
    Some({
      width: command.width.value,
      height: command.height.value,
      left: command.left.value,
      right: command.right.value,
      top: command.top.value,
      bottom: command.bottom.value,
    })
  } else {
    None
  }
  let sheets = match fields.get("sheets") {
    None => @model.CurrentSheet
    Some(String("visible")) => @model.VisibleSheets
    Some(Array(ids)) => {
      let selected = []
      for value in ids {
        guard value is String(id) else {
          return { value: Err("Printed worksheet identities must be strings"), }
        }
        selected.push(id)
      }
      @model.SelectedSheets(selected)
    }
    Some(_) => return { value: Err("Unknown printed worksheet selection"), }
  }
  let range = if fields.contains("range") {
    let request : SheetRangeRequest = @json.from_json(options, path~)
    Some(request.range)
  } else {
    None
  }
  { value: Ok({ setup, sheets, range, }), }
}

///|
fn PrintOptionsRequest::resolve(
  self : PrintOptionsRequest,
) -> PrintOptions raise @failure.Failure {
  match self.value {
    Ok(value) => value
    Err(message) => @failure.reject("invalid-sheet", message)
  }
}

///|
let print_handlers : Map[
  String,
  (Context, @model.Session, Json) -> Json raise @failure.Failure,
] = {
  "printXlsx": (context, session, input) => {
    let command : PrintRequest = @common.request(input)
    let { setup, sheets, range, } = command.options.resolve()
    let document = session.print_layout(
      command.revision.value,
      command.sheet,
      range,
      context.probe,
      command.profile.value,
      setup?,
      sheets~,
    )
    let regions = document.drawing(
      context.images,
      stroke_raster=CoverageStroke,
      glyph_raster=CoverageGlyphs,
    )
    let outlines = context.probe.outline_resources()
    guard context.layout_id < 2147483647 else {
      @failure.reject("limit-exceeded", "Print identity exhausted")
    }
    context.layout_id += 1
    context.xlsx_print = Some(
      (document, command.revision.value, context.layout_id),
    )
    let result : PrintResponse = {
      id: context.layout_id,
      revision: command.revision.value,
      sheet: command.sheet,
      regions,
      images: document.drawing_images(context.images),
      outlines,
    }
    ToJson::to_json(result)
  },
  "exportXlsxPdf": (context, session, input) => {
    guard context.xlsx_print is Some((document, revision, id)) else {
      @failure.reject(
        "stale-layout", "Create a current print layout before PDF export",
      )
    }
    let layout : LayoutRequest = @common.request(input)
    guard id == layout.layoutId.value && revision == session.current_revision() else {
      @failure.reject(
        "stale-layout", "Create a current print layout before PDF export",
      )
    }
    let command : PdfExportRequest = @common.request(input)
    {
      "bytes": context.output.add(
        @pdf.write(
          document,
          context.probe,
          context.images,
          command.outputBytes.value,
        ),
      ),
    }
  },
}
