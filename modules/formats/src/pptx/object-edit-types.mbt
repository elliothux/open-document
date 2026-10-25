///|
pub(all) enum ObjectEdit {
  InsertMath(String, @layout.TextStyle, Double, Double, Double, Double)
  AppendMath(String, @layout.TextStyle, Bool)
  UpdateMath(MathTarget, String, @layout.TextStyle)
  DeleteMath(MathTarget)
  InsertWordArt(String, String)
  InsertDiagram(DiagramSettings)
  InsertConnector(String, ConnectorEnd, ConnectorEnd)
  ConnectorEndpoints(String, ConnectorEnd, ConnectorEnd)
  Insert(String, Double, Double, Double, Double, String)
  InsertPlaceholder(String, Double, Double, Double, Double, String)
  Placeholder(String?, Double)
  InsertImage(Bytes, Double, Double, Double, Double)
  InsertMedia(String, String, Bytes, Bytes, Double, Double, Double, Double)
  FillMedia(String, String, Bytes, Bytes)
  MediaPlayback(MediaPlaybackSettings)
  InsertTable(Int, Int, Double, Double, Double, Double)
  InsertChart(
    String,
    String,
    String,
    Double,
    Double,
    Double,
    Double,
    Int?,
    String?
  )
  ChartData(String, String, String, Int?, String?)
  FillChart(String, String, String, Int?, String?)
  FillTable(Int, Int)
  TableStructure(String)
  SplitTableCell(Int, Int)
  TableRowHeight(Double)
  TableColumnWidth(Double)
  TableStyle(TableStyleSettings)
  TableDirection(Bool)
  ReplaceImage(String, Bytes)
  ImageFill(Array[String], Bytes, String)
  ImageFillMode(String)
  ImageMode(String)
  ImageInsets(Array[Double])
  ImageCrop(Double, Double, Double, Double)
  ImageOpacity(Double)
  Hyperlink(String, String)
  Remove
  Duplicate(Double, Double)
  Rotate(Double)
  Flip(Bool)
  Layer(String)
  Align(String, String)
  Distribute(String, String)
  Group
  Ungroup
  Fill(String?)
  GradientFill(Array[@layout.GradientStop], Double, Bool)
  RadialGradientFill(Array[@layout.GradientStop])
  FillOpacity(Double)
  StrokeOpacity(Double)
  Stroke(String?, Double)
  StrokeDash(String?)
  StrokeCap(String?)
  StrokeJoin(String?, Double)
  StrokeEnd(Bool, LineEnd?)
  ShapeAdjustment(String, Double?)
  ShapeType(String)
  TextInsets(Double, Double, Double, Double)
  TextAnchor(String)
  TextWrap(Bool)
  TextFit(String)
  TextColumns(Int, Double, Bool)
  TextDirection(String)
  TextRotation(Double)
  TextUpright(Bool)
  TextFormat(TextFormat)
  TextAlign(String)
  TextParagraph(ParagraphFormat)
  ClearTextFormat
  ClearParagraphFormat
}
