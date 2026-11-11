///|
#derive(ToJson)
priv struct PdfBytesOutput {
  revision : Int32
  bytes : Int32
}

///|
#derive(ToJson)
priv struct PdfExportOutput {
  revision : Int32
  bytes : Int32
  warnings : Array[String]
}

///|
#derive(ToJson)
priv struct PdfSplitFileOutput {
  name : String
  bytes : Int32
}

///|
#derive(ToJson)
priv struct PdfSplitOutput {
  revision : Int32
  files : Array[PdfSplitFileOutput]
}

///|
#derive(ToJson)
priv struct PdfRasterOutput {
  width : Int32
  height : Int32
  bytes : Int32
}

///|
#derive(ToJson)
priv struct PdfImageOutput {
  kind : String
  bytes : Int32
  width : Int32
  height : Int32
  header : @common.ImageHeader?
}

///|
#derive(ToJson)
priv struct PdfSelectedTextOutput {
  text : String
}
