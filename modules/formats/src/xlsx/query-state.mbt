///|
#derive(ToJson(fields(locked(rename="protected"))))
priv struct QuerySheet {
  id : String
  name : String
  state : String
  kind : String
  locked : Bool
}

///|
#derive(ToJson)
priv struct QueryTableStyle {
  name : String
  readOnlyReason : String
  elements : Array[TableStyleElement]
}

///|
#derive(ToJson)
priv struct QueryView {
  gridLines : Bool
  headings : Bool
  rtl : Bool
  formulas : Bool
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QuerySelection {
  sheet : String
  range : Range
  address : String
}

///|
#derive(ToJson)
priv struct QueryFrozen {
  rows : Int32
  columns : Int32
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryNote {
  address : String
  text : String
  author : String
  exists : Bool
  reason : String
}

///|
// Keep nullable fields present in worksheet and viewport responses.
priv struct QueryNullable[T] {
  value : T?
}

///|
impl[T : ToJson] ToJson for QueryNullable[T] with fn to_json(self) {
  self.value.map(value => ToJson::to_json(value)).unwrap_or(Json::null())
}

///|
#derive(ToJson)
priv struct QueryCell {
  address : String
  row : Int32
  column : Int32
  style : Int32
  value : Value
  input : String
  formula : QueryNullable[String]
  cached : QueryNullable[Value]
  calculated : QueryNullable[Value]
  calculation : String
  calculationReason : String
  mut display : String
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryDimensions {
  rowHeight : QueryNullable[Double]
  columnWidth : QueryNullable[Double]
  readOnlyReason : String
}

///|
#derive(ToJson(fields(locked(rename="protected"))))
priv struct QueryProtection {
  locked : Bool
  passwordRequired : Bool
  reason : String
}

///|
priv struct QueryPrintSettings[T] {
  settings : T
  readOnlyReason : String
}

///|
impl[T : ToJson] ToJson for QueryPrintSettings[T] with fn to_json(self) {
  // The print settings and the read-only reason share the same wire object.
  let json = ToJson::to_json(self.settings)
  if json is Object(fields) {
    fields["readOnlyReason"] = Json(self.readOnlyReason)
  }
  json
}

///|
#derive(ToJson)
priv struct QueryHyperlink {
  target : QueryNullable[String]
  mixed : Bool
  readOnlyReason : String
  navigationReason : String
}

///|
#derive(ToJson)
priv struct QueryMerging {
  range : String
  merged : Bool
  discarded : Int32
  discardedNotes : Int32
  mergeReason : String
  unmergeReason : String
}

///|
#derive(ToJson)
priv struct QueryStatistics {
  range : String
  count : Int32
  countNumbers : Int32
  sum : QueryNullable[Double]
  average : QueryNullable[Double]
  min : QueryNullable[Double]
  max : QueryNullable[Double]
  reason : String
}

///|
#derive(ToJson)
priv struct QueryValidation {
  rule : QueryNullable[DataValidation]
  mixed : Bool
  readOnlyReason : String
  options : Array[String]
  optionsReason : String
  promptVisible : Bool
}

///|
#derive(ToJson)
priv struct QueryConditionalRule {
  priority : Int32
  ranges : String
  rule : ConditionalFormat
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryConditionalFormats {
  rules : Array[QueryConditionalRule]
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryName {
  name : String
  scope : QueryNullable[String]
  formula : String
  hidden : Bool
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryNames {
  entries : Array[QueryName]
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryOutlineAxis {
  summaryAfter : Bool
  groups : Array[OutlineGroup]
}

///|
#derive(ToJson)
priv struct QueryOutline {
  rows : QueryOutlineAxis
  columns : QueryOutlineAxis
  reason : String
}

///|
#derive(ToJson)
priv struct QuerySparkline {
  cell : String
  source : String
  kind : String
}

///|
#derive(ToJson)
priv struct QuerySparklines {
  items : Array[QuerySparkline]
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct QueryFilterValue {
  value : String
  count : Int32
  selected : Bool
}

///|
#derive(ToJson)
priv struct QueryFilterColumn {
  column : Int32
  title : String
  blank : Int32
  blankSelected : Bool
  values : Array[QueryFilterValue]
}

///|
#derive(ToJson)
priv struct QueryFilter {
  range : String
  columns : Array[Json]
  catalog : Array[QueryFilterColumn]
  reason : String
}

///|
#derive(ToJson)
priv struct QueryTable {
  id : Int32
  name : String
  range : String
  headerRow : Bool
  totalRow : Bool
  columns : Array[TableColumn]
  style : QueryNullable[String]
  firstColumn : Bool
  lastColumn : Bool
  rowStripes : Bool
  columnStripes : Bool
  filter : QueryFilter
  readOnlyReason : String
}

///|
priv struct QueryFormatting {
  format : CellFormat
  readOnlyReason : String
  fontKeys : Array[String]
}

///|
#derive(ToJson)
priv struct QueryState {
  revision : Int32
  sheets : Array[QuerySheet]
  mainPart : String
  fontKeys : Array[String]
  sheet : String
  outline : QueryOutline
  tables : Array[QueryTable]
  tableStyles : Array[QueryTableStyle]
  view : QueryView
  statistics : QueryStatistics
  filter : QueryFilter
  sparklines : QuerySparklines
  names : QueryNames
  hyperlink : QueryHyperlink
  cells : Array[QueryCell]
  selection : QuerySelection
  canUndo : Bool
  canRedo : Bool
  historyBytes : Int32
  readOnlyReason : String
  note : QueryNote
  sheetEditReason : String
  protection : QueryProtection
  workbookProtection : QueryProtection
  sheetRenameReason : String
  sheetCopyReason : String
  sheetDeleteReason : String
  frozen : QueryFrozen
  printSetup : QueryPrintSettings[PrintSetup]
  dataValidation : QueryValidation
  conditionalFormats : QueryConditionalFormats
  printRange : QueryPrintSettings[PrintRange]
  headerFooter : QueryPrintSettings[HeaderFooter]
  dimensions : QueryDimensions
  formatting : QueryFormatting
  normalFont : String
  merging : QueryMerging
  diagnostics : Array[String]
  date1904 : Bool
}
