///|
priv struct TextFormatEditRequest[T] {
  format : T
} derive(@json.FromJson)

///|
priv struct TextAlignmentRequest {
  alignment : String
} derive(@json.FromJson)

///|
priv struct TextFormatRequest {
  font : String?
  size : @common.RequestNumber?
  bold : Bool?
  italic : Bool?
  color : String?
  underline : Bool?
  strike : Bool?
  highlight : String?
  script : String?
  spacing : @common.RequestNumber?
} derive(@json.FromJson)

///|
priv struct TextSpacingRequest {
  unit : String
  value : @common.RequestNumber
} derive(@json.FromJson)

///|
fn TextSpacingRequest::spacing(
  input : TextSpacingRequest,
) -> @model.TextSpacing {
  { unit: input.unit, value: input.value.value, }
}

///|
priv struct ParagraphFormatRequest {
  left : @common.RequestNumber?
  right : @common.RequestNumber?
  first : @common.RequestNumber?
  before : TextSpacingRequest?
  after : TextSpacingRequest?
  line : TextSpacingRequest?
  list : ListFormatInput?
  level : @common.RequestInt?
  rtl : Bool?
  tabs : @common.RequiredNullable[Array[ParagraphTabRequest]]?
  defaultTab : @common.RequiredNullable[@common.RequestNumber]?
  listFont : @common.RequiredNullable[String]?
  listSize : @common.RequiredNullable[TextSpacingRequest]?
  listColor : @common.RequiredNullable[String]?
} derive(@json.FromJson)

///|
priv struct ParagraphTabRequest {
  position : @common.RequestNumber
  align : String
} derive(@json.FromJson)

///|
priv struct BulletRequest {
  value : String
} derive(@json.FromJson)

///|
priv struct NumberedListRequest {
  value : String
  start : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct TextFormatInput {
  value : @model.TextFormat
}

///|
impl @json.FromJson for TextFormatInput with fn from_json(value, path) {
  guard value is Object(fields) &&
    fields
    .iter()
    .all(pair => {
      [
        "font", "size", "bold", "italic", "color", "underline", "strike", "highlight",
        "script", "spacing",
      ].contains(pair.0) &&
      !(pair.1 is Null)
    }) else {
    raise @json.JsonDecodeError((path, "Invalid text format fields"))
  }
  let request : TextFormatRequest = @json.from_json(value, path~)
  {
    value: @model.TextFormat::new(
      font?=request.font,
      size?=request.size.map(value => value.value),
      spacing?=request.spacing.map(value => value.value),
      bold?=request.bold,
      italic?=request.italic,
      color?=request.color,
      underline?=request.underline,
      strike?=request.strike,
      highlight?=request.highlight,
      script?=request.script,
    ),
  }
}

///|
priv struct ParagraphFormatInput {
  value : @model.ParagraphFormat
}

///|
impl @json.FromJson for ParagraphFormatInput with fn from_json(value, path) {
  guard value is Object(fields) &&
    fields
    .iter()
    .all(pair => {
      match pair.0 {
        "tabs" | "defaultTab" | "listFont" | "listSize" | "listColor" => true
        "left"
        | "right"
        | "first"
        | "before"
        | "after"
        | "line"
        | "list"
        | "level"
        | "rtl" => !(pair.1 is Null)
        _ => false
      }
    }) else {
    raise @json.JsonDecodeError((path, "Invalid paragraph format fields"))
  }
  if fields.get("tabs") is Some(value) && !(value is Null) {
    guard value is Array(tabs) && tabs.length() <= @model.ParagraphTabCount else {
      raise @json.JsonDecodeError(
        (path.add_key("tabs"), "Invalid paragraph tabs"),
      )
    }
    guard tabs.all(tab => tab is Object(fields) && fields.length() == 2) else {
      raise @json.JsonDecodeError(
        (path.add_key("tabs"), "Invalid paragraph tab fields"),
      )
    }
  }
  for key in ["before", "after", "line", "listSize"] {
    if fields.get(key) is Some(value) && !(value is Null) {
      guard value is Object(fields) && fields.length() == 2 else {
        raise @json.JsonDecodeError(
          (path.add_key(key), "Invalid paragraph spacing fields"),
        )
      }
    }
  }
  let request : ParagraphFormatRequest = @json.from_json(value, path~)
  {
    value: @model.ParagraphFormat::new(
      tabs?=request.tabs.map(value => {
        value.value.map(tabs => {
          tabs.map(tab => @model.ParagraphTab::{
            position: tab.position.value,
            align: tab.align,
          })
        })
      }),
      default_tab?=request.defaultTab.map(value => {
        value.value.map(number => number.value)
      }),
      rtl?=request.rtl,
      left?=request.left.map(value => value.value),
      right?=request.right.map(value => value.value),
      first?=request.first.map(value => value.value),
      before?=request.before.map(TextSpacingRequest::spacing),
      after?=request.after.map(TextSpacingRequest::spacing),
      line?=request.line.map(TextSpacingRequest::spacing),
      level?=request.level.map(value => value.value),
      list?=request.list.map(value => value.value),
      list_font?=request.listFont.map(value => value.value),
      list_size?=request.listSize.map(value => {
        value.value.map(TextSpacingRequest::spacing)
      }),
      list_color?=request.listColor.map(value => value.value),
    ),
  }
}

///|
fn pptx_paragraph_format(
  value : Json,
) -> @model.ParagraphFormat raise @failure.Failure {
  let request : ParagraphFormatInput = @common.request(value)
  request.value
}

///|
priv struct ListFormatInput {
  value : @model.ListFormat
}

///|
impl @json.FromJson for ListFormatInput with fn from_json(value, path) {
  guard value is Object(fields) else {
    raise @json.JsonDecodeError((path, "List format is required"))
  }
  guard value is { "kind": String(kind), .. } else {
    raise @json.JsonDecodeError((path, "List kind is required"))
  }
  let value = match kind {
    "none" if fields.length() == 1 => @model.NoList
    "bullet" if fields.length() == 2 => {
      let request : BulletRequest = @json.from_json(value, path~)
      @model.Bullet(request.value)
    }
    "number" if fields.length() == 3 => {
      let request : NumberedListRequest = @json.from_json(value, path~)
      @model.Numbered(request.value, request.start.value)
    }
    _ => raise @json.JsonDecodeError((path, "Invalid list format fields"))
  }
  { value, }
}

///|
priv struct GradientStopRequest {
  position : @common.RequestNumber
  color : String
  opacity : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct LinearGradientRequest {
  angle : @common.RequestNumber
  scaled : Bool
} derive(@json.FromJson)

///|
fn pptx_gradient_stops(
  value : Json,
) -> Array[@layout.GradientStop] raise @failure.Failure {
  guard value is { "stops": Array(stops), .. } &&
    stops.length() >= 2 &&
    stops.length() <= @layout.GradientStopCount else {
    @failure.reject("invalid-operation", "Gradients require 2..32 stops")
  }
  stops.map(stop => {
    guard stop is Object(fields) && fields.length() == 3 else {
      @failure.reject(
        "invalid-operation", "Gradient stops require position, color and opacity",
      )
    }
    let stop : GradientStopRequest = @common.request(stop)
    {
      position: stop.position.value,
      color: stop.color,
      opacity: stop.opacity.value,
    }
  })
}

///|
fn pptx_gradient_edit(
  action : String,
  value : Json,
) -> @model.ObjectEdit raise @failure.Failure {
  if action == "radialGradientFill" {
    @model.RadialGradientFill(pptx_gradient_stops(value))
  } else {
    let stops = pptx_gradient_stops(value)
    let gradient : LinearGradientRequest = @common.request(value)
    @model.GradientFill(stops, gradient.angle.value, gradient.scaled)
  }
}
