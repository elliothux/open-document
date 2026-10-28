///|
pub(all) struct PageMap {
  source : String
  target : Int32
}

///|
pub(all) struct ConversionResult {
  revision : Int32
  format : String
  status : String
  reason : String
  warnings : Array[String]
  pages : Array[PageMap]
  bytes : Bytes?
}

///|
priv struct Page {
  source : String
  width : Double
  height : Double
  lines : Array[@pdf.PdfReadLine]
  tables : Array[@pdf.PdfReadTable]
  images : Array[@pdf.PdfExtractedImage]
  paths : Array[@pdf.PdfExtractedPath]
}
