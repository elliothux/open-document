///|
priv struct PdfPages {
  value : Array[String]
}

///|
impl @json.FromJson for PdfPages with fn from_json(input, path) {
  guard input is Array(values) && values.length() <= @model.PageOperationCount else {
    raise @json.JsonDecodeError(
      (path, "Bounded PDF page identities are required"),
    )
  }
  { value: @json.from_json(input, path~), }
}

///|
priv struct PdfPageGroups {
  value : Array[PdfPages]
}

///|
impl @json.FromJson for PdfPageGroups with fn from_json(input, path) {
  guard input is Array(groups) && groups.length() <= @model.PageOperationCount else {
    raise @json.JsonDecodeError((path, "Bounded PDF split groups are required"))
  }
  { value: @json.from_json(input, path~), }
}

///|
priv struct PdfSplitRegions {
  value : Array[@model.PdfPlacement]
}

///|
impl @json.FromJson for PdfSplitRegions with fn from_json(input, path) {
  guard input is Array(regions) && regions.length() <= @model.PageOperationCount else {
    raise @json.JsonDecodeError((path, "Bounded split regions are required"))
  }
  let value = regions.map(region => {
    let parsed : PlacementRequest = @json.from_json(region, path~)
    parsed.placement()
  })
  { value, }
}

///|
priv struct PageOrderRequest {
  revision : @common.RequestInt
  pages : PdfPages
} derive(@json.FromJson)

///|
priv struct RotatePagesRequest {
  revision : @common.RequestInt
  pages : PdfPages
  degrees : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct CropPageRequest {
  revision : @common.RequestInt
  page : String
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct ResizePageRequest {
  revision : @common.RequestInt
  page : String
  width : @common.RequestNumber
  height : @common.RequestNumber
  scaleContent : Bool
  anchor : String
} derive(@json.FromJson)

///|
priv struct ImportPagesRequest {
  bytes : String
  revision : @common.RequestInt
  pages : PdfPages
  index : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct ReplacePagesRequest {
  bytes : String
  revision : @common.RequestInt
  pages : PdfPages
  index : @common.RequestInt
  replace : PdfPages
} derive(@json.FromJson)

///|
priv struct BlankPageRequest {
  revision : @common.RequestInt
  index : @common.RequestInt
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct SplitFilesRequest {
  revision : @common.RequestInt
  groups : PdfPageGroups
} derive(@json.FromJson)

///|
priv struct ExportTextRequest {
  revision : @common.RequestInt
  pages : PdfPages
  format : String
  profile : @common.RequestProfile
} derive(@json.FromJson)

///|
priv struct MetadataRequest {
  revision : @common.RequestInt
  fields : Map[String, String]
} derive(@json.FromJson)

///|
priv struct SplitPageRequest {
  revision : @common.RequestInt
  page : Json?
  regions : PdfSplitRegions
} derive(@json.FromJson)

///|
priv struct SplitGridRequest {
  revision : @common.RequestInt
  page : Json?
  columns : @common.RequestInt
  rows : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct NupPagesRequest {
  revision : @common.RequestInt
  pages : PdfPages
  columns : @common.RequestInt
  rows : @common.RequestInt
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct RenderPageRequest {
  revision : @common.RequestInt
  page : String
  profile : @common.RequestProfile
  activate : Bool?
  reuse : Bool?
} derive(@json.FromJson)

///|
priv struct ImageSizeRequest {
  width : @common.RequestInt
  height : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct ImageReadRequest {
  layoutId : @common.RequestInt
  key : String
  size : ImageSizeRequest?
} derive(@json.FromJson)

///|
priv struct ImageDecodeRequest {
  bytes : String
  layoutId : @common.RequestInt
  key : String
  width : @common.RequestInt
  height : @common.RequestInt
} derive(@json.FromJson)

///|
fn split_page_key(input : Json?) -> String {
  // Keep the model's invalid-page result for missing or malformed identities.
  match input {
    Some(String(page)) => page
    _ => ""
  }
}
