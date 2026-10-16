///|
fn Session::copied_sheet_name(
  self : Session,
  source : String,
) -> String raise @failure.Failure {
  let length = source.length()
  let numbered = length >= 3 &&
    source[length - 3] == 40 &&
    source[length - 2] >= 48 &&
    source[length - 2] <= 57 &&
    source[length - 1] == 41
  let base = if numbered { source[:length - 3].to_owned() } else { source }
  for index in 1..<=257 {
    let suffix = (if numbered { "(" } else { " (" }) + index.to_string() + ")"
    let mut end = base.length().min(31 - suffix.length())
    if end > 0 && base[end - 1] >= 0xd800 && base[end - 1] <= 0xdbff {
      end -= 1
    }
    let name = base[:end].to_owned() + suffix
    if !self.sheets.any(sheet => sheet.name.to_lower() == name.to_lower()) {
      validate_sheet_name(name)
      return name
    }
  }
  @failure.reject("limit-exceeded", "Copied worksheet name budget exceeded")
}

///|
fn check_sheet_copy_markup(
  document : @xml.Document,
) -> Unit raise @failure.Failure {
  let tree = Tree::new(document)
  for node in document.nodes() {
    guard node.uri == spreadsheet_uri &&
      node.attributes
      .iter()
      .all(a => {
        a.uri.is_empty() ||
        a.uri == "http://www.w3.org/XML/1998/namespace" ||
        a.uri == relationship_uri[:relationship_uri.length() - 1].to_owned()
      }) &&
      (
        node.name != "extLst" ||
        tree.children.get(node.id).unwrap_or([]).is_empty()
      ) else {
      @failure.reject(
        "protected-content", "Worksheet identity extensions require copying support",
      )
    }
  }
}

///|
fn Session::copied_sheet_names(
  self : Session,
  index : Int,
  name : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  guard tree.one(tree.root("workbook").id, "definedNames") is Some(parent) else {
    return []
  }
  let originals = tree
    .all(parent.id, "definedName")
    .filter(node => {
      node
      .attribute("localSheetId")
      .map(value => natural(value, self.sheets.length() - 1) == index)
      .unwrap_or(false)
    })
  if originals.is_empty() {
    return []
  }
  let changes : Array[@xml.SourceChange] = []
  let mut bytes = 0L
  for node in originals {
    guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.attributes
      .iter()
      .all(a => {
        a.uri.is_empty() &&
        [
          "name", "comment", "customMenu", "description", "help", "statusBar", "localSheetId",
          "hidden", "function", "vbProcedure", "xlm", "functionGroupId", "shortcutKey",
          "publishToServer", "workbookParameter",
        ].contains(a.name)
      }) else {
      @failure.reject(
        "protected-content", "Defined name extensions require copying support",
      )
    }
    bytes += (node.end - node.start).to_int64() * 2
    guard bytes <= 4194304L else {
      @failure.reject("limit-exceeded", "Copied names exceed history budget")
    }
    changes.append(
      metadata_changes(node, [("localSheetId", (index + 1).to_string())]),
    )
    let text = sheet_reference_formula(
      node.text,
      self.sheets[index].name,
      Some(name),
    )
    if text != node.text {
      changes.push({
        node: node.id,
        offset: node.opening_end - node.start,
        length: node.closing_start - node.opening_end,
        xml: @xml.escape_text(text),
      })
    }
  }
  let updated = self.workbook.edit_source(changes).0
  let fragments = StringBuilder()
  let mut units = 0
  for node in originals {
    let copied = updated.node(node.id)
    units += copied.end - copied.start
    guard units <= 2097152 else {
      @failure.reject("limit-exceeded", "Copied names exceed history budget")
    }
    fragments.write_view(updated.source()[copied.start:copied.end])
  }
  [insertion(parent, fragments.to_string())]
}

///|
fn Session::copy_sheet_relations(
  self : Session,
  owner : String,
  target : String,
  remapped : Map[String, String],
) -> @xml.Document? raise @failure.Failure {
  let path = workbook_relations(owner)
  guard self.parts.contains(path) || self.opc.names.contains(path.to_lower()) else {
    return None
  }
  let original = self.part_xml(path)
  guard original.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Copied relationships exceed history budget",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  let links = self.relationships()
  for node in original.nodes() {
    if node.parent != original.nodes()[0].id {
      continue
    }
    let id = node.attribute("Id").unwrap_or("")
    let link = links
      .iter()
      .find_first(link => link.owner == owner && link.id == id)
      .unwrap()
    if !link.external {
      changes.append(
        metadata_changes(node, [
          ("Target", "/" + remapped.get(link.target).unwrap_or(link.target)),
        ]),
      )
    }
  }
  let bytes = if changes.is_empty() {
    original.bytes()
  } else {
    original.edit_source(changes).0.bytes()
  }
  Some(
    @xml.Document::parse(
      bytes,
      workbook_relations(target),
      self.budget.xml_depth,
      self.budget.entry_bytes,
    ),
  )
}

///|
fn Session::copied_sheet_parts(
  self : Session,
  source : Sheet,
  target : Sheet,
  number : Int,
) -> (Map[String, @xml.Document], String) raise @failure.Failure {
  let created : Map[String, @xml.Document] = Map([])
  let remapped = Map::from_array([(source.id, target.id)])
  let types = StringBuilder()
  let links = self.relationships()
  let comments = links
    .iter()
    .filter(link => {
      link.owner == source.id && link.kind == relationship_uri + "comments"
    })
    .collect()
  guard comments.length() <= 1 else {
    @failure.reject("protected-content", "Multiple worksheet comment owners")
  }
  if comments.get(0) is Some(link) {
    guard !link.external &&
      links
      .iter()
      .all(child => {
        child.owner != link.target ||
        child.kind == relationship_uri + "hyperlink"
      }) else {
      @failure.reject(
        "protected-content", "Comment resources require copying support",
      )
    }
    let original = self.part_xml(link.target)
    guard (
        original.source().length().to_int64() +
        target.document.source().length().to_int64()
      ) *
      2 <=
      4194304L else {
      @failure.reject("limit-exceeded", "Copied comments exceed history budget")
    }
    check_sheet_copy_markup(original)
    ignore(Tree::new(original).root("comments"))
    let directory = self.main.split("/").map(p => p.to_owned()).to_array()
    ignore(directory.pop())
    let prefix = if directory.is_empty() {
      ""
    } else {
      directory.join("/") + "/"
    }
    let mut sequence = 0
    let mut part = ""
    while true {
      part = prefix + "comments/odSheet\{number}-\{sequence}.xml"
      if !self.opc.names.contains(part.to_lower()) &&
        !self.parts.contains(part) &&
        !self.opc.names.contains(workbook_relations(part).to_lower()) &&
        !self.parts.contains(workbook_relations(part)) {
        break
      }
      sequence += 1
      guard sequence <= self.budget.entries else {
        @failure.reject("limit-exceeded", "Comment identity budget exceeded")
      }
    }
    let changes : Array[@xml.SourceChange] = []
    let text = original.source()
    for node in original.nodes() {
      if node.name != "comment" {
        continue
      }
      for attribute in node.attributes {
        if !attribute.uri.is_empty() ||
          !["guid", "shapeId"].contains(attribute.name) {
          continue
        }
        // New comments use the new part and cell identity, without the source's optional ids.
        let mut end = attribute.start - 1
        while end > node.start && text[end] != 61 {
          end -= 1
        }
        while end > node.start &&
              [32, 9, 10, 13].contains(text[end - 1].to_int()) {
          end -= 1
        }
        let mut start = end
        while start > node.start &&
              ![32, 9, 10, 13, 60].contains(text[start - 1].to_int()) {
          start -= 1
        }
        changes.push({
          node: node.id,
          offset: start - node.start,
          length: attribute.end + 1 - start,
          xml: "",
        })
      }
    }
    let bytes = if changes.is_empty() {
      original.bytes()
    } else {
      original.edit_source(changes).0.bytes()
    }
    created[part] = @xml.Document::parse(
      bytes,
      part,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    remapped[link.target] = part
    types.write_string(
      "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml\"/>",
    )
    if self.copy_sheet_relations(link.target, part, remapped) is Some(document) {
      created[workbook_relations(part)] = document
    }
  }
  if self.copy_sheet_relations(source.id, target.id, remapped) is Some(document) {
    created[workbook_relations(target.id)] = document
  }
  let bytes = created
    .values()
    .fold(init=target.document.source().length().to_int64() * 2, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    })
  guard bytes <= 4194304L else {
    @failure.reject(
      "limit-exceeded", "Copied worksheet parts exceed history budget",
    )
  }
  (created, types.to_string())
}
