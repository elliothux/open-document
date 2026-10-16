///|
fn Session::format_reason(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> String {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  if sheet.locked {
    return "Worksheet is protected"
  }
  if (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() >
    4096L {
    return "Formatting exceeds 4096 cells"
  }
  for merge in sheet.merges {
    if merge.intersects(range) &&
      !(range.top <= merge.top &&
      range.left <= merge.left &&
      range.bottom >= merge.bottom &&
      range.right >= merge.right) {
      return "Formatting must include complete merged cells"
    }
  }
  try {
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        let address : Address = { row, column, }
        if sheet.cells.get(address.name()) is Some(cell) &&
          !cell.read_only.is_empty() {
          return cell.read_only
        }
        let style = self.styles[sheet.style_at(address)]
        if !style.diagnostic.is_empty() {
          return style.diagnostic
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::new_styles_part(
  self : Session,
) -> (String, Array[(String, @xml.Document, @xml.Edit)]) raise @failure.Failure {
  let directory = self.main.split("/").map(v => v.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let links = self.relationships()
  let mut index = 0
  let mut part = ""
  let mut id = ""
  while true {
    part = prefix +
      "styles" +
      (if index == 0 { "" } else { index.to_string() }) +
      ".xml"
    id = "odStyles\{index}"
    if !self.opc.names.contains(part.to_lower()) &&
      !self.parts.contains(part) &&
      !links.iter().any(link => link.owner == self.main && link.id == id) {
      break
    }
    index += 1
    guard index <= self.budget.entries else {
      @failure.reject("limit-exceeded", "Cell style identity budget exceeded")
    }
  }
  let edits : Array[(String, @xml.Document, @xml.Edit)] = []
  for
    (path, markup) in [
      (
        workbook_relations(self.main),
        "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{id}\" Type=\"\{relationship_uri}styles\" Target=\"/\{escaped_attribute(part)}\"/>",
      ),
      (
        "[Content_Types].xml",
        "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>",
      ),
    ] {
    let document = self.part_xml(path)
    let (updated, edit) = document.edit_source([
      insertion(document.nodes()[0], markup),
    ])
    edits.push((path, updated, edit))
  }
  (part, edits)
}

///|
/// Applies only the specified cell properties, keeping values and shared source styles intact.
pub fn Session::format_cells(
  self : Session,
  revision : Int,
  patch : CellFormat,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  patch.validate()
  let (sheet, target) = self.selection
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.format_reason(current, target)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let originals : Map[String, Int] = Map([])
  let bases : Map[Int, Bool] = Map([])
  for row in target.top..<=target.bottom {
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let style = current.style_at(address)
      if patch.applied(self.styles[style]) != self.styles[style] {
        originals[address.name()] = style
        bases[style] = true
      }
    }
  }
  if originals.is_empty() {
    return self.query()
  }
  let parts = self.parts.copy()
  let existing = self.styles_part(parts)
  let (path, metadata) = if existing is Some(path) {
    (path, [])
  } else {
    self.new_styles_part()
  }
  let original = if existing is Some(_) {
    self.part_xml(path)
  } else {
    @xml.Document::parse(
      empty_cell_styles(),
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
  }
  guard original.source().length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Cell styles exceed history budget")
  }
  let tree = Tree::new(original)
  let fonts = StylePool::new(tree, "fonts", "font")
  let fills = StylePool::new(tree, "fills", "fill")
  let borders = StylePool::new(tree, "borders", "border")
  let formats = StylePool::new(tree, "cellXfs", "xf")
  let mappings : Map[Int, Int] = Map([])
  let new_formats : Array[String] = []
  let mut number_id : Int? = None
  if patch.numberFormat is Some(code) {
    let container = tree.one(tree.root("styleSheet").id, "numFmts")
    let nodes = container.map(node => tree.all(node.id, "numFmt")).unwrap_or([])
    let previous = nodes
      .iter()
      .find_first(node => node.attribute("formatCode") == Some(code))
    if previous is Some(node) {
      number_id = Some(natural(node.attribute("numFmtId").unwrap_or(""), 65535))
    } else {
      let mut id = 164
      while nodes.any(node => node.attribute("numFmtId") == Some(id.to_string())) {
        id += 1
      }
      guard id <= 65535 else {
        @failure.reject("limit-exceeded", "Number format identity exhausted")
      }
      number_id = Some(id)
      new_formats.push(
        "<od:numFmt xmlns:od=\"\{spreadsheet_uri}\" numFmtId=\"\{id}\" formatCode=\"\{escaped_attribute(code)}\"/>",
      )
    }
  }
  let mut units = 0
  for base in bases.keys() {
    let xf = formats.nodes[base]
    let font = natural(xf.attribute("fontId").unwrap_or("0"), 4095)
    let fill = natural(xf.attribute("fillId").unwrap_or("0"), 4095)
    let border = natural(xf.attribute("borderId").unwrap_or("0"), 4095)
    let derived_font = if patch.family is Some(_) ||
      patch.size is Some(_) ||
      patch.bold is Some(_) ||
      patch.italic is Some(_) ||
      patch.color is Some(_) {
      fonts.intern(patch.font_markup(tree, fonts.nodes[font]))
    } else {
      font
    }
    let derived_fill = if patch.fill is Some(color) {
      fills.intern(
        if color.is_empty() {
          "<od:fill xmlns:od=\"\{spreadsheet_uri}\"><od:patternFill patternType=\"none\"/></od:fill>"
        } else {
          "<od:fill xmlns:od=\"\{spreadsheet_uri}\"><od:patternFill patternType=\"solid\"><od:fgColor rgb=\"FF\{color.to_upper()}\"/><od:bgColor indexed=\"64\"/></od:patternFill></od:fill>"
        },
      )
    } else {
      fill
    }
    let derived_border = if [patch.left, patch.right, patch.top, patch.bottom].any(v => {
          v is Some(_)
        },
      ) {
      borders.intern(patch.border_markup(tree, borders.nodes[border]))
    } else {
      border
    }
    let markup = patch.xf_markup(
      tree, xf, derived_font, derived_fill, derived_border, number_id,
    )
    units += markup.length() +
      fonts.entries[derived_font].length() +
      fills.entries[derived_fill].length() +
      borders.entries[derived_border].length()
    guard units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Derived cell styles exceed source budget",
      )
    }
    mappings[base] = formats.intern(markup)
  }
  let changes = [
    ..fonts.changes(),
    ..fills.changes(),
    ..borders.changes(),
    ..formats.changes(),
  ]
  if !new_formats.is_empty() {
    let root = tree.root("styleSheet")
    if tree.one(root.id, "numFmts") is Some(container) {
      changes.append(
        metadata_changes(container, [
          (
            "count",
            (tree.all(container.id, "numFmt").length() + new_formats.length()).to_string(),
          ),
        ]),
      )
      changes.push(insertion(container, new_formats.join("")))
    } else {
      changes.push({
        node: root.id,
        offset: fonts.parent.start - root.start,
        length: 0,
        xml: "<od:numFmts xmlns:od=\"\{spreadsheet_uri}\" count=\"\{new_formats.length()}\">\{new_formats.join("")}</od:numFmts>",
      })
    }
  }
  let generated = changes
    .iter()
    .fold(init=0L, (sum, change) => sum + change.xml.length().to_int64())
  guard generated <= 2097152L else {
    @failure.reject(
      "limit-exceeded", "Cell format source exceeds history budget",
    )
  }
  let (document, style_edit) = original.edit_source(changes)
  parts[path] = document
  let edits : Array[(String, @xml.Edit)] = []
  for (name, document, edit) in metadata {
    parts[name] = document
    edits.push((name, edit))
  }
  let created_parts : Map[String, @xml.Document] = Map([])
  if existing is Some(_) {
    edits.push((path, style_edit))
  } else {
    created_parts[path] = document
  }
  let styles = read_styles(document, self.theme)
  let updates : Map[String, CellContent] = Map([])
  let indices : Map[String, Int] = Map([])
  for name, base in originals {
    updates[name] = { value: Blank, formula: None, keep_shared: true, }
    indices[name] = mappings[base]
  }
  let (document, edit) = current.prepare(updates, styles=indices)
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    styles.length(),
  )
  edits.push((current.id, edit))
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    (sheet, target),
    parts~,
    created_parts~,
  )
  self.query()
}
