///|
priv struct PageSetupInput {
  section : @common.RequestInt
  width : @common.RequestNumber
  height : @common.RequestNumber
  top : @common.RequestNumber
  right : @common.RequestNumber
  bottom : @common.RequestNumber
  left : @common.RequestNumber
  orientation : String?
  startType : String?
  footnotesAt : String?
} derive(@json.FromJson)

///|
fn check_page_setup_fields(value : Json) -> Unit raise @failure.Failure {
  guard value is Object(fields) &&
    fields
    .iter()
    .all(pair => {
      match pair {
        ("section" | "width" | "height" | "top" | "right" | "bottom" | "left", _
        ) => true
        ("orientation" | "startType" | "footnotesAt", String(_)) => true
        _ => false
      }
    }) else {
    @failure.reject("invalid-operation", "Invalid page setup fields")
  }
}

///|
priv struct PageBorderInput {
  side : String
  style : String
  color : String
  themeColor : @common.RequiredNullable[String]
  width : @common.RequestNumber
  space : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct PageBordersInput {
  offsetFrom : String
  display : String
  zOrder : String
  sides : Array[PageBorderInput]
} derive(@json.FromJson)

///|
fn check_page_border_fields(value : Json) -> Unit raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.get("sides") is Some(Array(sides)) &&
    sides.length() <= @layout.PageBorderSideCount &&
    sides.iter().all(side => side is Object(fields) && fields.length() == 6) else {
    @failure.reject("invalid-operation", "Invalid page border fields")
  }
}

///|
fn PageBordersInput::borders(input : PageBordersInput) -> @layout.PageBorders {
  {
    offsetFrom: input.offsetFrom,
    display: input.display,
    zOrder: input.zOrder,
    sides: input.sides.map(side => {
      side: side.side,
      style: side.style,
      color: side.color,
      themeColor: side.themeColor.value,
      width: side.width.value,
      space: side.space.value,
    }),
  }
}

///|
priv struct ColumnInput {
  width : @common.RequestNumber
  gap : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct PageColumnsInput {
  count : @common.RequestInt
  gap : @common.RequestNumber
  separator : Bool
  custom : Array[ColumnInput]
} derive(@json.FromJson)

///|
fn check_page_columns_fields(value : Json) -> Unit raise @failure.Failure {
  guard value is Object(fields) &&
    fields.length() == 4 &&
    fields.get("custom") is Some(Array(items)) &&
    items.length() <= @layout.PageColumnCount &&
    items.iter().all(item => item is Object(fields) && fields.length() == 2) else {
    @failure.reject("invalid-operation", "Invalid column settings")
  }
}

///|
fn PageColumnsInput::columns(input : PageColumnsInput) -> @layout.Columns {
  @layout.Columns::new(
    count=input.count.value,
    gap=input.gap.value,
    separator=input.separator,
    custom=input.custom.map(item => @layout.Column::{
      width: item.width.value,
      gap: item.gap.value,
    }),
  )
}

///|
priv struct PageNumberingInput {
  start : @common.RequiredNullable[@common.RequestNumber]
  format : String
} derive(@json.FromJson)

///|
fn PageNumberingInput::numbering(
  input : PageNumberingInput,
) -> @model.SectionNumbering raise @failure.Failure {
  let start = input.start.value.map(number => {
    let start = number.value
    guard start >= 0 &&
      start <= @layout.NumberingStartMax.to_double() &&
      start.floor() == start else {
      @failure.reject("invalid-operation", "Invalid page numbering start")
    }
    start.to_int64()
  })
  { start, format: input.format, }
}

///|
priv struct RunningContentRequest {
  value : Array[@model.RunningContent]
}

///|
impl @json.FromJson for RunningContentRequest with fn from_json(value, path) {
  guard value is Array(content) &&
    content.length() <= @model.RunningContentItems else {
    raise @json.JsonDecodeError(
      (
        path,
        "Running content requires at most \{@model.RunningContentItems} items",
      ),
    )
  }
  {
    value: content.mapi((index, item) => {
      running_content_item(item, path.add_index(index))
    }),
  }
}

///|
fn running_content_item(
  item : Json,
  path : @json.JsonPath,
) -> @model.RunningContent raise @json.JsonDecodeError {
  guard item is Object(fields) else {
    raise @json.JsonDecodeError((path, "Invalid running content item"))
  }
  match item {
    { "text": String(text), "target": String(target), .. } if fields.length() ==
      2 => @model.RunningContent::Link(text, target)
    { "field": String(code), "format": String(format), .. } if fields.length() ==
      2 => @model.RunningContent::FormattedField(code, format)
    { "text": String(text), .. } if fields.length() == 1 =>
      @model.RunningContent::Text(text)
    { "field": String(code), .. } if fields.length() == 1 =>
      @model.RunningContent::Field(code)
    _ => raise @json.JsonDecodeError((path, "Invalid running content item"))
  }
}
