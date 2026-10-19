///|
fn blank_layout() -> String {
  "<p:sldLayout xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\">\{empty_shape_tree()}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
}

///|
fn blank_master(layouts : String) -> String {
  "<p:sldMaster xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\"><p:cSld>\{empty_shape_tree()}</p:cSld><p:clrMap accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" bg1=\"lt1\" bg2=\"lt2\" folHlink=\"folHlink\" hlink=\"hlink\" tx1=\"dk1\" tx2=\"dk2\"/><p:sldLayoutIdLst>\{layouts}</p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>"
}

///|
fn empty_shape_tree() -> String {
  "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr></p:spTree>"
}

///|
fn empty_slide() -> String {
  "<p:sld xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:cSld>\{empty_shape_tree()}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>"
}

///|
/// Creates a 16:9 presentation with one blank slide and its layout, master and theme.
pub fn Session::create(
  budget : @archive.Budget,
  date_time? : String,
) -> Session raise @failure.Failure {
  let p = presentation_uri
  let r = relationship_uri
  let parts : Map[String, Bytes] = Map([])
  let types = StringBuilder()
  types.write_string(
    "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
  )
  for
    (name, kind) in [
      ("presentation.xml", "presentation.main"),
      ("slides/slide1.xml", "slide"),
      ("slideLayouts/slideLayout1.xml", "slideLayout"),
      ("slideMasters/slideMaster1.xml", "slideMaster"),
    ] {
    types.write_string(
      "<Override PartName=\"/ppt/\{name}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.\{kind}+xml\"/>",
    )
  }
  types.write_string(
    "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/></Types>",
  )
  parts["[Content_Types].xml"] = @utf8.encode(types.to_string())
  let rel_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
  for
    (path, links) in [
      (
        "_rels/.rels",
        [("officeDocument", "officeDocument", "ppt/presentation.xml")],
      ),
      (
        "ppt/_rels/presentation.xml.rels",
        [
          ("slide1", "slide", "slides/slide1.xml"),
          ("master1", "slideMaster", "slideMasters/slideMaster1.xml"),
        ],
      ),
      (
        "ppt/slides/_rels/slide1.xml.rels",
        [("layout1", "slideLayout", "../slideLayouts/slideLayout1.xml")],
      ),
      (
        "ppt/slideLayouts/_rels/slideLayout1.xml.rels",
        [("master1", "slideMaster", "../slideMasters/slideMaster1.xml")],
      ),
      (
        "ppt/slideMasters/_rels/slideMaster1.xml.rels",
        [
          ("layout1", "slideLayout", "../slideLayouts/slideLayout1.xml"),
          ("theme1", "theme", "../theme/theme1.xml"),
        ],
      ),
    ] {
    let out = StringBuilder()
    out.write_string("<Relationships xmlns=\"\{rel_ns}\">")
    for (id, kind, target) in links {
      out.write_string(
        "<Relationship Id=\"\{id}\" Type=\"\{r}/\{kind}\" Target=\"\{target}\"/>",
      )
    }
    out.write_string("</Relationships>")
    parts[path] = @utf8.encode(out.to_string())
  }
  for
    (name, source) in [
      (
        "presentation.xml",
        "<p:presentation xmlns:p=\"\{p}\" xmlns:r=\"\{r}\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"master1\"/></p:sldMasterIdLst><p:sldIdLst><p:sldId id=\"256\" r:id=\"slide1\"/></p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>",
      ),
      ("slides/slide1.xml", empty_slide()),
      ("slideLayouts/slideLayout1.xml", blank_layout()),
      (
        "slideMasters/slideMaster1.xml",
        blank_master("<p:sldLayoutId id=\"2147483649\" r:id=\"layout1\"/>"),
      ),
      ("theme/theme1.xml", blank_theme()),
    ] {
    parts["ppt/" + name] = @utf8.encode(source)
  }
  Session::from_package(@opc.Package::create(parts, budget), budget, date_time~)
}

///|
fn blank_theme() -> String {
  let out = StringBuilder()
  out.write_string(
    "<a:theme xmlns:a=\"\{drawing_uri}\" name=\"Open Document\"><a:themeElements><a:clrScheme name=\"Default\">",
  )
  for
    (name, color) in [
      ("dk1", "000000"),
      ("lt1", "FFFFFF"),
      ("dk2", "1F497D"),
      ("lt2", "EEECE1"),
      ("accent1", "4F81BD"),
      ("accent2", "C0504D"),
      ("accent3", "9BBB59"),
      ("accent4", "8064A2"),
      ("accent5", "4BACC6"),
      ("accent6", "F79646"),
      ("hlink", "0000FF"),
      ("folHlink", "800080"),
    ] {
    out.write_string("<a:\{name}><a:srgbClr val=\"\{color}\"/></a:\{name}>")
  }
  out.write_string("</a:clrScheme><a:fontScheme name=\"Default\">")
  for kind in ["majorFont", "minorFont"] {
    out.write_string(
      "<a:\{kind}><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:\{kind}>",
    )
  }
  out.write_string(
    "</a:fontScheme><a:fmtScheme name=\"Default\"><a:fillStyleLst>",
  )
  let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
  for _ in 0..<3 {
    out.write_string(fill)
  }
  out.write_string("</a:fillStyleLst><a:lnStyleLst>")
  for width in [6350, 12700, 19050] {
    out.write_string(
      "<a:ln w=\"\{width}\">\{fill}<a:prstDash val=\"solid\"/></a:ln>",
    )
  }
  out.write_string("</a:lnStyleLst><a:effectStyleLst>")
  for _ in 0..<3 {
    out.write_string("<a:effectStyle><a:effectLst/></a:effectStyle>")
  }
  out.write_string("</a:effectStyleLst><a:bgFillStyleLst>")
  for _ in 0..<3 {
    out.write_string(fill)
  }
  out.write_string(
    "</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>",
  )
  out.to_string()
}
