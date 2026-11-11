///|
priv struct QueryNullable[T] {
  value : T?
}

///|
impl[T : ToJson] ToJson for QueryNullable[T] with fn to_json(self) {
  nullable_json(self.value)
}

///|
priv struct QueryPicture {
  mode : String
  modeReason : String
  opacity : Double
  opacityReason : String
  left : Double
  top : Double
  right : Double
  bottom : Double
  replaceReason : String
  cropReason : String
} derive(ToJson)

///|
priv struct QueryAppearance {
  imageFill : QueryNullable[String]
  imageFillReason : String
  imageFillMode : QueryNullable[String]
  gradient : QueryNullable[BackgroundFill]
  fillOpacity : Double
  strokeOpacity : Double
  fillOpacityReason : String
  strokeOpacityReason : String
  fill : QueryNullable[String]
  stroke : QueryNullable[String]
  width : Double
  dash : String
  dashReason : String
  cap : String
  join : String
  miterLimit : Double
  penReason : String
  headEnd : LineEnd
  tailEnd : LineEnd
  lineEndReason : String
  reason : String
} derive(ToJson)

///|
priv struct QueryTextFrame {
  left : Double
  top : Double
  right : Double
  bottom : Double
  anchor : String
  wrap : Bool
  fit : String
  columns : Int32
  columnGap : Double
  rtlColumns : Bool
  direction : String
  rotation : Double
  upright : Bool
  reason : String
} derive(ToJson)

///|
priv struct QueryObject {
  id : String
  parent : String
  name : String
  kind : String
  chart : Json
  media : Json
  text : String
  equations : Array[Json]
  readOnlyReason : String
  textReadOnlyReason : String
  deleteReason : String
  duplicateReason : String
  rotateReason : String
  arrangeReason : String
  transformReason : String
  tableFillReason : String
  chartFillReason : String
  mediaFillReason : String
  chartDataReason : String
  hyperlink : Json
  shapeAdjustments : Json
  shapeTypeReason : String
  connector : Json
  connectionSiteCount : Int32
  placeholder : Json
  imageInsets : Array[Double]
  imageInsetsReason : String
  picture : QueryPicture
  appearance : QueryAppearance
  textFrame : QueryTextFrame
  geometry : QueryNullable[Geometry]
} derive(ToJson)

///|
fn Session::query_object(
  self : Session,
  object : Object,
  links : ReadOnlyArray[@opc.Relationship],
  deletion_reason : String,
) -> QueryObject raise @failure.Failure {
  let mode = if object.tile is Some(_) { "tile" } else { "stretch" }
  let image = if object.kind == "shape" { object.image } else { None }
  let body = object.body
  {
    id: object.id,
    parent: object.parent,
    name: object.name,
    kind: object.kind,
    chart: object.chart.map(chart => chart.data.query()).unwrap_or(Json::null()),
    media: object.media_query(),
    text: object.accessible_text(),
    equations: self.math_items(object),
    readOnlyReason: object.read_only,
    textReadOnlyReason: object.text_reason,
    deleteReason: if self.selection.objects.contains(object.id) &&
      !deletion_reason.is_empty() {
      deletion_reason
    } else {
      self.object_edit_reason(object, "delete")
    },
    duplicateReason: self.object_edit_reason(object, "duplicate"),
    rotateReason: self.object_edit_reason(object, "rotate"),
    arrangeReason: self.object_edit_reason(object, "arrange"),
    transformReason: self.object_edit_reason(object, "transform"),
    tableFillReason: self.table_fill_reason(object),
    chartFillReason: self.chart_fill_reason(object),
    mediaFillReason: self.media_fill_reason(object),
    chartDataReason: self.chart_data_reason(object),
    hyperlink: self.hyperlink_query(object, links),
    shapeAdjustments: self.shape_adjustments(object),
    shapeTypeReason: self.shape_type_reason(object),
    connector: self.connector_query(object),
    connectionSiteCount: object.connection_site_count(),
    placeholder: self.placeholder_query(object),
    imageInsets: object.insets,
    imageInsetsReason: self.image_insets_reason(object),
    picture: {
      mode,
      modeReason: self.image_mode_reason(object),
      opacity: object.opacity,
      opacityReason: self.opacity_reason(object),
      left: object.crop[0],
      top: object.crop[1],
      right: object.crop[2],
      bottom: object.crop[3],
      replaceReason: self.image_replacement_reason(object),
      cropReason: self.image_reason(object, true),
    },
    appearance: {
      imageFill: { value: image, },
      imageFillReason: self.image_fill_reason(object),
      imageFillMode: { value: image.map(_ => mode), },
      gradient: { value: object.gradient, },
      fillOpacity: object.fill_alpha,
      strokeOpacity: object.stroke_alpha,
      fillOpacityReason: self.paint_opacity_reason(object, false),
      strokeOpacityReason: self.paint_opacity_reason(object, true),
      fill: {
        value: if object.fill.is_empty() {
          None
        } else {
          Some(object.fill)
        },
      },
      stroke: {
        value: if object.stroke.is_empty() {
          None
        } else {
          Some(object.stroke)
        },
      },
      width: object.line_width,
      dash: object.dash,
      dashReason: self.dash_reason(object),
      cap: object.cap,
      join: object.join,
      miterLimit: object.miter,
      penReason: self.pen_reason(object),
      headEnd: object.ends.0,
      tailEnd: object.ends.1,
      lineEndReason: self.line_end_reason(object),
      reason: self.paint_reason(object),
    },
    textFrame: {
      left: body.left,
      top: body.top,
      right: body.right,
      bottom: body.bottom,
      anchor: body.anchor,
      wrap: body.wrap,
      fit: body.fit,
      columns: body.columns,
      columnGap: body.columnGap,
      rtlColumns: body.rtlColumns,
      direction: body.direction,
      rotation: body.rotation,
      upright: body.upright,
      reason: self.text_frame_reason(object),
    },
    geometry: { value: object.geometry, },
  }
}
