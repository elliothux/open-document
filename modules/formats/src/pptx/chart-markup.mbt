///|
fn chart_cache(
  values : Array[String],
  numeric : Bool,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  out <+ "<c:\{if numeric {"numCache"} else {"strCache"}}>"
  if numeric {
    out <+ "<c:formatCode>General</c:formatCode>"
  }
  out <+ "<c:ptCount val=\"\{values.length()}\"/>"
  for i, value in values {
    if numeric && value.is_empty() {
      continue
    }
    out <+ "<c:pt idx=\"\{i}\"><c:v>\{@xml.escape_text(value)}</c:v></c:pt>"
  }
  out <+ "</c:\{if numeric {"numCache"} else {"strCache"}}>"
  out.to_string()
}

///|
fn chart_reference(
  formula : String,
  values : Array[String],
  numeric : Bool,
) -> String raise @failure.Failure {
  let kind = if numeric { "numRef" } else { "strRef" }
  "<c:" +
  kind +
  "><c:f>" +
  @xml.escape_text(formula) +
  "</c:f>" +
  chart_cache(values, numeric) +
  "</c:" +
  kind +
  ">"
}

///|
fn chart_title(
  text : String,
  subtitle? : String,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  out <+ "<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/>"
  for paragraph in [text] + subtitle.map(value => [value]).unwrap_or([]) {
    out <+
      "<a:p><a:r><a:rPr lang=\"en-US\" sz=\"1200\"><a:solidFill><a:srgbClr val=\"222222\"/></a:solidFill><a:latin typeface=\"Arial\"/></a:rPr><a:t>\{@xml.escape_text(paragraph)}</a:t></a:r></a:p>"
  }
  out <+ "</c:rich></c:tx><c:overlay val=\"0\"/></c:title>"
  out.to_string()
}

///|
fn ChartData::markup(
  self : ChartData,
  workbook_link : String,
) -> String raise @failure.Failure {
  if self.kind == "pie" {
    return self.pie_markup(workbook_link)
  }
  let (low, high, step) = self.axis()
  let horizontal = self.kind == "bar"
  let line = self.kind == "line"
  let last = self.categories.length() + 1
  let categories = chart_reference(
    "Sheet1!$A$2:$A$" + last.to_string(),
    self.categories,
    false,
  )
  let out = StringBuilder()
  out <+
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><c:chartSpace xmlns:c=\"\{chart_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><c:chart>\{chart_title(self.title)}<c:autoTitleDeleted val=\"0\"/><c:plotArea><c:layout/>"
  out.write_string(
    if line {
      "<c:lineChart><c:grouping val=\"standard\"/><c:varyColors val=\"0\"/>"
    } else {
      "<c:barChart><c:barDir val=\"\{if horizontal {"bar"} else {"col"}}\"/><c:grouping val=\"clustered\"/><c:varyColors val=\"0\"/>"
    },
  )
  for index, series in self.series {
    let column = ["B", "C", "D", "E", "F", "G", "H", "I"][index]
    let title = chart_reference(
      "Sheet1!$" + column + "$1",
      [series.name],
      false,
    )
    let values = chart_reference(
      "Sheet1!$" + column + "$2:$" + column + "$" + last.to_string(),
      series.values.map(v => v.map(v => v.to_string()).unwrap_or("")),
      true,
    )
    let color = chart_color(index)
    out <+
      "<c:ser><c:idx val=\"\{index}\"/><c:order val=\"\{index}\"/><c:tx>\{title}</c:tx>"
    out.write_string(
      if line {
        "<c:spPr><a:noFill/><a:ln w=\"19050\"><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/><c:spPr><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr></c:marker>"
      } else {
        "<c:spPr><a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:ln><a:noFill/></a:ln></c:spPr><c:invertIfNegative val=\"0\"/>"
      },
    )
    out <+ "<c:cat>\{categories}</c:cat><c:val>\{values}</c:val>"
    if line {
      out <+ "<c:smooth val=\"0\"/>"
    }
    out <+ "</c:ser>"
  }
  out.write_string(
    if line {
      "<c:marker val=\"1\"/><c:smooth val=\"0\"/><c:axId val=\"1\"/><c:axId val=\"2\"/></c:lineChart>"
    } else {
      "<c:gapWidth val=\"150\"/><c:overlap val=\"0\"/><c:axId val=\"1\"/><c:axId val=\"2\"/></c:barChart>"
    },
  )
  out <+
    "<c:catAx><c:axId val=\"1\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\{if horizontal {"l"} else {"b"}}\"/>\{chart_title(self.label)}<c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"2\"/><c:crosses val=\"autoZero\"/><c:auto val=\"1\"/><c:lblAlgn val=\"ctr\"/><c:lblOffset val=\"100\"/></c:catAx><c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"\{if horizontal {"b"} else {"l"}}\"/><c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"0\"/><c:tickLblPos val=\"nextTo\"/><c:crossAx val=\"1\"/><c:crosses val=\"autoZero\"/><c:crossBetween val=\"between\"/></c:valAx></c:plotArea><c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend><c:plotVisOnly val=\"1\"/><c:dispBlanksAs val=\"gap\"/><c:showDLblsOverMax val=\"0\"/></c:chart><c:externalData r:id=\"\{workbook_link}\"><c:autoUpdate val=\"0\"/></c:externalData></c:chartSpace>"
  out
  .to_string()
  .replace(
    old="<c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling>",
    new="<c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/><c:max val=\"\{high}\"/><c:min val=\"\{low}\"/></c:scaling>",
  )
  .replace(
    old="<c:crossBetween val=\"between\"/>",
    new="<c:crossBetween val=\"between\"/><c:majorUnit val=\"\{step}\"/>",
  )
}

///|
fn chart_frame(
  id : String,
  link : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> String {
  "<p:graphicFrame xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:c=\"\{chart_uri}\" xmlns:r=\"\{relationship_uri}\"><p:nvGraphicFramePr><p:cNvPr id=\"\{id}\" name=\"Chart \{id}\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"\{(x*12700).round().to_int64()}\" y=\"\{(y*12700).round().to_int64()}\"/><a:ext cx=\"\{(width*12700).round().to_int64()}\" cy=\"\{(height*12700).round().to_int64()}\"/></p:xfrm><a:graphic><a:graphicData uri=\"\{chart_uri}\"><c:chart r:id=\"\{link}\"/></a:graphicData></a:graphic></p:graphicFrame>"
}
