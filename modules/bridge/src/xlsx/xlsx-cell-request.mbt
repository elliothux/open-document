///|
#derive(@json.FromJson)
priv struct QueryRequest {
  sheet : String?
  range : String?
}

///|
#derive(@json.FromJson)
priv struct CellRangeRequest {
  revision : @common.RequestInt
  sheet : String
  range : String
}

///|
#derive(@json.FromJson)
priv struct ReplaceCellsRequest {
  revision : @common.RequestInt
  sheet : String
  range : String
  values : Json
  literal : Bool
  acceptWarnings : Bool
}

///|
fn xlsx_replacement_values(
  input : Json,
) -> Array[Array[String]] raise @failure.Failure {
  guard input is Array(rows) && rows.length() <= @model.RectangularEditCells else {
    @failure.reject(
      "invalid-operation", "Explicit rectangular values are required",
    )
  }
  let mut count = 0
  rows.map(row => {
    guard row is Array(fields) else {
      @failure.reject("invalid-operation", "Expected value row")
    }
    guard fields.length() <= @model.RectangularEditCells - count else {
      @failure.reject("limit-exceeded", "Edit cell count exceeds budget")
    }
    count += fields.length()
    @common.request(row)
  })
}

///|
#derive(@json.FromJson)
priv struct LayoutRequest {
  layoutId : @common.RequestInt
}

///|
#derive(@json.FromJson)
priv struct FormulaAssistanceRequest {
  revision : @common.RequestInt
  sheet : String
  source : String
  caret : @common.RequestInt
  layoutId : @common.RequestInt?
}

///|
#derive(@json.FromJson)
priv struct NumberFormatSamplesRequest {
  formats : Array[String]
}

///|
#derive(@json.FromJson)
priv struct ViewportRequest {
  sheet : String
  scrollX : @common.RequestNumber
  scrollY : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
  profile : @common.RequestProfile
  reveal : Bool
  screenScale : @common.RequestNumber?
  compactCells : Bool?
}

///|
#derive(@json.FromJson)
priv struct HitRequest {
  layoutId : @common.RequestInt
  x : @common.RequestNumber
  y : @common.RequestNumber
}

///|
#derive(@json.FromJson(fields(extend_flag(rename="extend"))))
priv struct NavigateRequest {
  revision : @common.RequestInt
  direction : String
  extend_flag : Bool
}

///|
#derive(@json.FromJson)
priv struct PasteCellsRequest {
  revision : @common.RequestInt
  copied : Json
  mode : String
  transpose : Bool
  acceptWarnings : Bool
}

///|
#derive(@json.FromJson)
priv struct PasteTextRequest {
  revision : @common.RequestInt
  text : String
  acceptWarnings : Bool
}

///|
#derive(@json.FromJson)
priv struct ClearRequest {
  revision : @common.RequestInt
  mode : String
}

///|
#derive(@json.FromJson)
priv struct ExportCsvRequest {
  revision : @common.RequestInt
  selection : Bool
}

///|
#derive(@json.FromJson)
priv struct FindOptionsRequest {
  matchCase : Bool
  wholeCell : Bool
  formulas : Bool
  workbook : Bool
}

///|
fn FindOptionsRequest::options(self : FindOptionsRequest) -> @model.FindOptions {
  @model.FindOptions::new(
    matchCase=self.matchCase,
    wholeCell=self.wholeCell,
    formulas=self.formulas,
    workbook=self.workbook,
  )
}

///|
#derive(@json.FromJson)
priv struct FindRequest {
  revision : @common.RequestInt
  sheet : String
  text : String
  options : FindOptionsRequest
}

///|
#derive(@json.FromJson)
priv struct ReplaceMatchesRequest {
  revision : @common.RequestInt
  sheet : String
  text : String
  options : FindOptionsRequest
  replacement : String
  index : @common.RequiredNullable[@common.RequestInt]?
}

///|
#derive(@json.FromJson)
priv struct AutoFitRequest {
  revision : @common.RequestInt
  sheet : String
  axis : String
  first : @common.RequestInt
  last : @common.RequestInt
  profile : @common.RequestProfile
}

///|
#derive(@json.FromJson)
priv struct ApplyFormatRequest {
  revision : @common.RequestInt
  format : Json
}

///|
#derive(@json.FromJson)
priv struct FormatCellsRequest {
  revision : @common.RequestInt
  patch : CellFormatRequest
}

///|
#derive(@json.FromJson)
priv struct FillPointRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct FillDirectionRequest {
  direction : String
}

///|
#derive(@json.FromJson)
priv struct FillModifierRequest {
  kind : String
  ctrl : Bool?
}

///|
priv struct FillTargetRequest {
  target : @model.FillTarget
  ctrl : Bool
}

///|
#derive(@json.FromJson)
priv struct FillPreviewRequest {
  layoutId : @common.RequestInt
  target : FillTargetRequest
}

///|
impl @json.FromJson for FillTargetRequest with fn from_json(input, path) {
  if input is { "ctrl": Null, .. } {
    raise @json.JsonDecodeError((path, "Fill control modifier must be boolean"))
  }
  let command : FillModifierRequest = @json.from_json(input, path~)
  let target = match command.kind {
    "point" => {
      let point : FillPointRequest = @json.from_json(input, path~)
      @model.FillPoint(point.x.value, point.y.value)
    }
    "direction" => {
      let direction : FillDirectionRequest = @json.from_json(input, path~)
      @model.FillDirection(direction.direction)
    }
    "adjacent" => @model.FillAdjacent
    _ => raise @json.JsonDecodeError((path, "Invalid fill target"))
  }
  { target, ctrl: command.ctrl.unwrap_or(false), }
}
