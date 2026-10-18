///|
fn builtin_table_styles() -> Tree raise @failure.Failure {
  let styles = StringBuilder()
  for
    (id, name, grid) in [
      ("{2D5ABB26-0587-4C30-8999-92F81FD0307C}", "No Style, No Grid", false),
      ("{5940675A-B579-460E-94D1-54222C63F5DA}", "No Style, Table Grid", true),
    ] {
    let edges = ["left", "right", "top", "bottom", "insideH", "insideV"]
      .map(side => {
        "<a:\{side}><a:ln w=\"12700\">\{if grid {"<a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill>"}else{"<a:noFill/>"}}</a:ln></a:\{side}>"
      })
      .join("")
    styles <+
      "<a:tblStyle styleId=\"\{id}\" styleName=\"\{name}\"><a:wholeTbl><a:tcTxStyle><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></a:tcTxStyle><a:tcStyle><a:tcBdr>\{edges}</a:tcBdr><a:fill><a:solidFill><a:schemeClr val=\"bg1\"/></a:solidFill></a:fill></a:tcStyle></a:wholeTbl></a:tblStyle>"
  }
  for
    index, id in [
      "{3C2FFA5D-87B4-456A-9821-1D502468CF0F}", "{284E427A-3D55-4303-BF80-6455036E1DE7}",
      "{69C7853C-536D-4A76-A0AE-DD22124D55A5}", "{775DCB02-9BB8-47FD-8907-85C794F793BA}",
      "{35758FB7-9AC5-4552-8A53-C91805E547FA}", "{08FB837D-C827-4EFA-A057-4D05807E0F7C}",
    ] {
    let accent = "accent\{index+1}"
    let edges = ["left", "right", "top", "bottom", "insideH", "insideV"]
      .map(side => {
        "<a:\{side}><a:ln w=\"12700\">\{if ["top","insideH","insideV"].contains(side) {"<a:solidFill><a:schemeClr val=\"\{accent}\"/></a:solidFill>"}else{"<a:noFill/>"}}</a:ln></a:\{side}>"
      })
      .join("")
    let text = "<a:tcTxStyle b=\"on\"><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></a:tcTxStyle>"
    let band = "<a:tcStyle><a:fill><a:solidFill><a:schemeClr val=\"\{accent}\"><a:tint val=\"80000\"/></a:schemeClr></a:solidFill></a:fill></a:tcStyle>"
    styles <+
      "<a:tblStyle styleId=\"\{id}\" styleName=\"Themed Style 1 - Accent \{index+1}\"><a:wholeTbl><a:tcTxStyle><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></a:tcTxStyle><a:tcStyle><a:tcBdr>\{edges}</a:tcBdr><a:fill><a:solidFill><a:schemeClr val=\"\{accent}\"><a:tint val=\"60000\"/></a:schemeClr></a:solidFill></a:fill></a:tcStyle></a:wholeTbl><a:band1H>\{band}</a:band1H><a:band1V>\{band}</a:band1V><a:firstCol>\{text}</a:firstCol><a:lastCol>\{text}</a:lastCol><a:lastRow>\{text}<a:tcStyle><a:tcBdr><a:left><a:ln><a:noFill/></a:ln></a:left><a:right><a:ln><a:noFill/></a:ln></a:right></a:tcBdr></a:tcStyle></a:lastRow><a:firstRow><a:tcTxStyle b=\"on\"><a:fontRef idx=\"minor\"><a:schemeClr val=\"bg1\"/></a:fontRef></a:tcTxStyle><a:tcStyle><a:tcBdr><a:bottom><a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"bg1\"/></a:solidFill></a:ln></a:bottom></a:tcBdr><a:fill><a:solidFill><a:schemeClr val=\"\{accent}\"/></a:solidFill></a:fill></a:tcStyle></a:firstRow></a:tblStyle>"
  }
  for
    index, id in [
      "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}", "{21E4AEA4-8DFA-4A89-87EB-49C32662AFE0}",
      "{F5AB1C69-6EDB-4FF4-983F-18BD219EF322}", "{00A15C55-8517-42AA-B614-E9B94910E393}",
      "{7DF18680-E054-41AD-8BC1-D1AEF772440D}", "{93296810-A885-4BE3-A3E7-6D5BEEA58F35}",
    ] {
    let accent = "accent\{index+1}"
    let edges = ["left", "right", "top", "bottom", "insideH", "insideV"]
      .map(side => {
        "<a:\{side}><a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"bg1\"/></a:solidFill></a:ln></a:\{side}>"
      })
      .join("")
    let text = "<a:tcTxStyle b=\"on\"><a:fontRef idx=\"minor\"><a:schemeClr val=\"bg1\"/></a:fontRef></a:tcTxStyle>"
    let fill = "<a:fill><a:solidFill><a:schemeClr val=\"\{accent}\"/></a:solidFill></a:fill>"
    let band = "<a:tcStyle><a:fill><a:solidFill><a:schemeClr val=\"\{accent}\"><a:tint val=\"40000\"/></a:schemeClr></a:solidFill></a:fill></a:tcStyle>"
    let first = "\{text}<a:tcStyle>\{fill}</a:tcStyle>"
    let top = "<a:top><a:ln w=\"38100\"><a:solidFill><a:schemeClr val=\"bg1\"/></a:solidFill></a:ln></a:top>"
    let bottom = top
      .replace(old="a:top", new="a:bottom")
      .replace(old="</a:top", new="</a:bottom")
    styles <+
      "<a:tblStyle styleId=\"\{id}\" styleName=\"Medium Style 2 - Accent \{index+1}\"><a:wholeTbl><a:tcTxStyle><a:fontRef idx=\"minor\"><a:schemeClr val=\"tx1\"/></a:fontRef></a:tcTxStyle><a:tcStyle><a:tcBdr>\{edges}</a:tcBdr><a:fill><a:solidFill><a:schemeClr val=\"\{accent}\"><a:tint val=\"20000\"/></a:schemeClr></a:solidFill></a:fill></a:tcStyle></a:wholeTbl><a:band1H>\{band}</a:band1H><a:band1V>\{band}</a:band1V><a:firstCol>\{first}</a:firstCol><a:lastCol>\{first}</a:lastCol><a:firstRow>\{text}<a:tcStyle>\{fill}<a:tcBdr>\{bottom}</a:tcBdr></a:tcStyle></a:firstRow><a:lastRow>\{text}<a:tcStyle>\{fill}<a:tcBdr>\{top}</a:tcBdr></a:tcStyle></a:lastRow></a:tblStyle>"
  }
  let document = @xml.Document::parse(
    @utf8.encode(
      "<a:tblStyleLst xmlns:a=\"\{drawing_uri}\" def=\"{5940675A-B579-460E-94D1-54222C63F5DA}\">\{styles}</a:tblStyleLst>",
    ),
    "builtin-table-styles",
    64,
    1048576,
  )
  Tree::new("builtin-table-styles", document)
}
