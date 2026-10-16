///|
fn workbook_relations(main : String) -> String {
  let segments = main.split("/").map(segment => segment.to_owned()).to_array()
  let leaf = segments.pop().unwrap()
  segments.push("_rels")
  segments.push(leaf + ".rels")
  segments.join("/")
}

///|
fn Session::prepare_sheet_add(
  self : Session,
) -> (Sheet, Int, String, Array[(String, @xml.Document, @xml.Edit)]) raise @failure.Failure {
  guard self.sheets.length() < 256 else {
    @failure.reject("limit-exceeded", "Worksheet count exceeds budget")
  }
  let tree = Tree::new(self.workbook)
  let parent = tree.one(tree.root("workbook").id, "sheets").unwrap()
  let nodes = tree.all(parent.id, "sheet")
  let relations = self.relationships()
  let segments = self.main
    .split("/")
    .map(segment => segment.to_owned())
    .to_array()
  ignore(segments.pop())
  let directory = if segments.is_empty() {
    ""
  } else {
    segments.join("/") + "/"
  }
  let mut number = self.next_sheet
  let mut part = ""
  let mut relation = ""
  let mut name = ""
  while true {
    guard number < 2147483647 else {
      @failure.reject("limit-exceeded", "Worksheet identity exhausted")
    }
    part = directory + "worksheets/sheet\{number}.xml"
    relation = "odSheet\{number}"
    name = "Sheet\{number}"
    if !self.opc.names.contains(part.to_lower()) &&
      !self.sheets.any(sheet => {
        sheet.id.to_lower() == part.to_lower() ||
        sheet.name.to_lower() == name.to_lower()
      }) &&
      !nodes.any(node => {
        natural(node.attribute("sheetId").unwrap_or("0"), 2147483647) == number
      }) &&
      !relations.iter().any(rel => rel.owner == self.main && rel.id == relation) {
      break
    }
    number += 1
  }
  let document = @xml.Document::parse(
    empty_worksheet(),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  let sheet = Sheet::read(
    part,
    name,
    "visible",
    document,
    self.strings,
    self.style_count,
  )
  let metadata : Array[(String, @xml.Document, @xml.Edit)] = []
  for
    (path, markup) in [
      (
        workbook_relations(self.main),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{relation}\" Type=\"\{relationship_uri}worksheet\" Target=\"worksheets/sheet\{number}.xml\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>",
      ),
    ] {
    let original = self.part_xml(path)
    let (updated, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    metadata.push((path, updated, edit))
  }
  let markup = "<od:sheet xmlns:od=\"\{spreadsheet_uri}\" xmlns:r=\"\{relationship_uri[:relationship_uri.length() - 1]}\" name=\"\{name}\" sheetId=\"\{number}\" r:id=\"\{relation}\"/>"
  (sheet, number, markup, metadata)
}
