///|
fn check_comment_date(value : String) -> Unit raise @failure.Failure {
  guard [20, 24].contains(value.length()) &&
    value[4:5] == "-" &&
    value[7:8] == "-" &&
    value[10:11] == "T" &&
    value[13:14] == ":" &&
    value[16:17] == ":" &&
    value[value.length() - 1:] == "Z" &&
    (value.length() == 20 || value[19:20] == ".") else {
    @failure.reject(
      "invalid-operation", "Comments require an explicit UTC date",
    )
  }
  for i in 0..<value.length() {
    if [4, 7, 10, 13, 16, value.length() - 1].contains(i) ||
      (value.length() == 24 && i == 19) {
      continue
    }
    guard value[i] >= 48 && value[i] <= 57 else {
      @failure.reject("invalid-operation", "Invalid comment date")
    }
  }
  let digits = fn(start : Int32, end : Int32) -> Int32 {
    for i in start..<end; total = 0 {
      continue total * 10 + value[i].to_int() - 48
    } nobreak {
      total
    }
  }
  let year = digits(0, 4)
  let month = digits(5, 7)
  let day = digits(8, 10)
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let days = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  guard year >= 1 &&
    month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= days[month - 1] &&
    digits(11, 13) <= 23 &&
    digits(14, 16) <= 59 &&
    digits(17, 19) <= 59 else {
    @failure.reject("invalid-operation", "Invalid comment date")
  }
}

///|
fn comment_body(
  document : @xml.Document?,
  node : Int32?,
  text : String,
  para~ : String = "",
) -> String raise @failure.Failure {
  let (ppr, rpr) = if document is Some(document) && node is Some(node) {
    let tree = WordTree::new(document)
    let first = tree.children[node].get(0)
    let ppr = first
      .bind(p => tree.child(p, "pPr"))
      .map(id => tree.standalone_markup(document, id))
      .unwrap_or("")
    let rpr = first
      .bind(p => tree.child(p, "r"))
      .bind(r => tree.child(r, "rPr"))
      .map(id => tree.standalone_markup(document, id))
      .unwrap_or("")
    (ppr, rpr)
  } else {
    ("", "")
  }
  let identity = if para.is_empty() {
    ""
  } else {
    " xmlns:odcp=\"\{comment_para_uri}\" odcp:paraId=\"\{para}\""
  }
  "<od:p xmlns:od=\"\{word_uri}\"\{identity}>\{ppr}<od:r>\{rpr}\{inline_markup(text, history_byte_limit / 2)}</od:r></od:p>"
}

///|
fn Session::create_comments_part(
  self : Session,
  markup : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  extended~ : Bool = false,
) -> String raise @failure.Failure {
  let segments = self.main.split("/").map(s => s.to_owned()).to_array()
  let name = segments.pop().unwrap()
  let prefix = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  let links = self.relationships()
  let stem = if extended { "odCommentsExt" } else { "odComments" }
  let uri = if extended { comment_extended_uri } else { word_uri }
  let root_name = if extended { "commentsEx" } else { "comments" }
  let kind = if extended {
    comment_extended_kind
  } else {
    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"
  }
  let content = if extended { "commentsExtended" } else { "comments" }
  let (path, identity) = for i in 1..<=16384 {
    let path = prefix + "\{stem}\{i}.xml"
    let identity = "\{stem}\{i}"
    if !self.opc.names.contains(path.to_lower()) &&
      !parts.keys().any(p => p.to_lower() == path.to_lower()) &&
      !links.any(l => l.owner == self.main && l.id == identity) {
      break (path, identity)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Comment part identities exhausted")
  }
  let document = @xml.Document::parse(
    @utf8.encode(
      "<od:\{root_name} xmlns:od=\"\{uri}\">\{markup}</od:\{root_name}>",
    ),
    path,
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  parts[path] = document
  created[path] = document
  let rel_path = prefix + "_rels/" + name + ".rels"
  let rel_path = self.opc.names.get(rel_path.to_lower()).unwrap_or(rel_path)
  let rel = "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{identity}\" Type=\"\{kind}\" Target=\"/\{property_attribute(path)}\"/>"
  if parts.contains(rel_path) || self.opc.names.contains(rel_path.to_lower()) {
    let (next, edit) = append_part_xml(self.part_xml(rel_path), rel)
    parts[rel_path] = next
    edits[rel_path] = [edit]
  } else {
    let next = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{rel}</Relationships>",
      ),
      rel_path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[rel_path] = next
    created[rel_path] = next
  }
  let types = self.opc.names["[content_types].xml"]
  let (next, edit) = append_part_xml(
    self.part_xml(types),
    "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{property_attribute(path)}\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\{content}+xml\"/>",
  )
  parts[types] = next
  edits[types] = [edit]
  path
}
