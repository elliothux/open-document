///|
/// Creates an editable blank DOCX with explicit package resource limits.
pub fn Session::create(
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  let parts = Map::from_array([
    (
      "[Content_Types].xml", b"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/></Types>",
    ),
    (
      "_rels/.rels", b"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"officeDocument\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
    ),
    (
      "word/document.xml", b"<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p/><w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>",
    ),
    (
      "word/_rels/document.xml.rels", b"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"styles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"settings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/></Relationships>",
    ),
    ("word/styles.xml", @utf8.encode(default_docx_styles())),
    (
      "word/settings.xml", b"<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"/>",
    ),
  ])
  Session::from_package(@opc.Package::create(parts, budget))
}

///|
fn default_docx_styles() -> String {
  let base = "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:eastAsia=\"Times New Roman\" w:cs=\"Times New Roman\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style><w:style w:type=\"character\" w:default=\"1\" w:styleId=\"DefaultParagraphFont\"><w:name w:val=\"Default Paragraph Font\"/></w:style><w:style w:type=\"character\" w:styleId=\"Emphasis\"><w:name w:val=\"Emphasis\"/><w:basedOn w:val=\"DefaultParagraphFont\"/><w:rPr><w:i/><w:iCs/></w:rPr></w:style><w:style w:type=\"character\" w:styleId=\"Strong\"><w:name w:val=\"Strong\"/><w:basedOn w:val=\"DefaultParagraphFont\"/><w:rPr><w:b/><w:bCs/></w:rPr></w:style></w:styles>"
  let headings = StringBuilder()
  for level in 1..<=9 {
    let (paragraph, character) = heading_style_properties(level)
    headings <+
      "<w:style w:type=\"paragraph\" w:styleId=\"Heading\{level}\"><w:name w:val=\"Heading \{level}\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/>\{paragraph}\{character}</w:style>"
  }
  base.replace_all(old="</w:styles>", new=headings.to_string() + "</w:styles>")
}
