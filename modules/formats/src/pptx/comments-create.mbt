///|
fn check_comment_date(value : String) -> Unit raise @failure.Failure {
  guard (value.length() == 20 || value.length() == 24) &&
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
  let year = number(value[:4].to_owned(), 1, 9999).to_int()
  let month = number(value[5:7].to_owned(), 1, 12).to_int()
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
  ignore(number(value[8:10].to_owned(), 1, days[month - 1].to_double()))
  ignore(number(value[11:13].to_owned(), 0, 23))
  ignore(number(value[14:16].to_owned(), 0, 59))
  ignore(number(value[17:19].to_owned(), 0, 59))
}

///|
fn Session::create_comment_part(
  self : Session,
  owner : String,
  kind : String,
  root : String,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Tree raise @failure.Failure {
  let directory = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let mut sequence = 1
  let mut part = ""
  while true {
    part = prefix + kind + "/odComments\{sequence}.xml"
    if !self.opc.names.contains(part.to_lower()) &&
      !parts.contains(part) &&
      !self.opc.names.contains(relationship_part(part).to_lower()) &&
      !parts.contains(relationship_part(part)) {
      break
    }
    sequence += 1
    guard sequence <= self.budget.entries else {
      @failure.reject("limit-exceeded", "Comment part identity budget exceeded")
    }
  }
  let document = @xml.Document::parse(
    @utf8.encode("<p:\{root} xmlns:p=\"\{presentation_uri}\"/>"),
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  parts[part] = document
  created[part] = document
  let links = self.relationships()
  let mut id = 1
  while links.any(l => l.owner == owner && l.id == "odComments\{id}") {
    id += 1
    guard id <= 16384 else {
      @failure.reject(
        "limit-exceeded", "Comment relationship identity budget exceeded",
      )
    }
  }
  for
    (path, markup) in [
      (
        relationship_part(owner),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"odComments\{id}\" Type=\"\{relationship_uri}/\{kind}\" Target=\"/\{xml_attribute(part)}\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{xml_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.\{kind}+xml\"/>",
      ),
    ] {
    let original = parts
      .get(path)
      .unwrap_or_else(() => self.part_document(path))
    let (document, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    parts[path] = document
    edits.push((path, edit))
  }
  Tree::new(part, document)
}

///|
fn Session::append_comment(
  self : Session,
  slide : String,
  tree : Tree?,
  author_tree : Tree?,
  authors : Array[CommentAuthor],
  text : String,
  name : String,
  initials : String,
  date : String,
  parent : CommentEntry?,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  guard !name.trim().is_empty() &&
    name.length() <= 255 &&
    initials.length() <= 32 &&
    @xml.valid_text(name) &&
    @xml.valid_text(initials) &&
    (name + initials).iter().all(c => c >= ' ') else {
    @failure.reject(
      "invalid-operation", "Comments require an explicit bounded author",
    )
  }
  check_comment_date(date)
  let matching = authors.filter(a => a.name == name && a.initials == initials)
  guard matching.length() <= 1 else {
    @failure.reject(
      "protected-content", "Ambiguous comment authors are protected",
    )
  }
  let author = matching.get(0)
  let id = if author is Some(author) {
    author.id
  } else {
    guard authors.length() < 4096 else {
      @failure.reject("limit-exceeded", "Comment authors exceed budget")
    }
    let next = authors
      .iter()
      .fold(init=0L, (max, a) => {
        max.max(number(a.id, 0, 4294967295).to_int64() + 1L)
      })
    guard next <= 4294967295L else {
      @failure.reject("limit-exceeded", "Comment author identities exhausted")
    }
    next.to_string()
  }
  let mut last = author.map(a => a.last_index).unwrap_or(0L)
  let mut count = 0
  // Imported lastIdx may lag, so reserve all retained comments before allocating.
  for link in self.relationships() {
    if link.kind != relationship_uri + "/comments" || link.external {
      continue
    }
    for node in self.part_document(link.target).nodes() {
      if node.uri != presentation_uri || node.name != "cm" {
        continue
      }
      count += 1
      guard count <= 16384 else {
        @failure.reject(
          "limit-exceeded", "Presentation comments exceed allocation budget",
        )
      }
      if comment_uint(node.attribute("authorId").unwrap_or("")) == id {
        last = last.max(
          number(
            comment_uint(node.attribute("idx").unwrap_or("")),
            0,
            4294967295,
          ).to_int64(),
        )
      }
    }
  }
  guard last < 4294967295L else {
    @failure.reject("limit-exceeded", "Comment indices exhausted")
  }
  let next = (last + 1L).to_string()
  let authors_tree = author_tree.unwrap_or_else(() => {
    self.create_comment_part(
      self.main.part,
      "commentAuthors",
      "cmAuthorLst",
      parts,
      created,
      edits,
    )
  })
  let changes = if author is Some(author) {
    [
      attribute_change(
        { tree: authors_tree, node: author.node, },
        "lastIdx",
        next,
      ),
    ]
  } else {
    [
      insertion(
        authors_tree.root("cmAuthorLst"),
        "<p:cmAuthor xmlns:p=\"\{presentation_uri}\" id=\"\{id}\" name=\"\{xml_attribute(name)}\" initials=\"\{xml_attribute(initials)}\" lastIdx=\"\{next}\" clrIdx=\"0\"/>",
      ),
    ]
  }
  let (document, edit) = authors_tree.document.edit_source(changes)
  parts[authors_tree.part] = document
  edits.push((authors_tree.part, edit))
  let tree = tree.unwrap_or_else(() => {
    self.create_comment_part(slide, "comments", "cmLst", parts, created, edits)
  })
  let (x, y) = if parent is Some(parent) {
    let pos = tree.required(parent.node.id, "pos", uri=presentation_uri)
    (pos.attribute("x").unwrap(), pos.attribute("y").unwrap())
  } else {
    ("0", "0")
  }
  let thread = parent
    .map(p => {
      "<p:extLst><p:ext uri=\"{C676402C-5697-4E1C-873F-D02D1690AC5C}\"><p15:threadingInfo xmlns:p15=\"\{comment_thread_uri}\"><p15:parentCm authorId=\"\{p.author}\" idx=\"\{p.id.split(":").last().unwrap()}\"/></p15:threadingInfo></p:ext></p:extLst>"
    })
    .unwrap_or("")
  let markup = "<p:cm xmlns:p=\"\{presentation_uri}\" authorId=\"\{id}\" idx=\"\{next}\" dt=\"\{date}\"><p:pos x=\"\{xml_attribute(x)}\" y=\"\{xml_attribute(y)}\"/><p:text xml:space=\"preserve\">\{xml_attribute(text)}</p:text>\{thread}</p:cm>"
  let (document, edit) = tree.document.edit_source([
    insertion(tree.root("cmLst"), markup),
  ])
  // Validate the same source contract used for imported comments before committing.
  ignore(read_comment_entries(Tree::new(tree.part, document)))
  parts[tree.part] = document
  edits.push((tree.part, edit))
}
