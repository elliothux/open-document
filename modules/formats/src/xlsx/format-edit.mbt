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
  let sheet = self.sheets[self.sheet_index(self.selection.0)]
  let target = sheet.merge_target(self.selection.1)
  if [patch.left, patch.right, patch.top, patch.bottom].any(edge => {
      edge is Some(_)
    }) &&
    sheet.merges.any(range => range.intersects(target)) {
    self.check_revision(revision)
    let reason = self.format_reason(sheet, target)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let pattern : Array[Array[CellFormat]] = []
    for row in target.top..<=target.bottom {
      let line : Array[CellFormat] = []
      for column in target.left..<=target.right {
        let address : Address = { row, column, }
        line.push(patch.for_merged_cell(address, sheet.cell_range(address)))
      }
      pattern.push(line)
    }
    self.format_pattern(revision, pattern, target)
  } else {
    self.format_pattern(revision, [[patch]], target)
  }
}

///|
fn Session::format_pattern(
  self : Session,
  revision : Int,
  pattern : Array[Array[CellFormat]],
  target : Range,
  merges~ : Array[Range]? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let patches : Array[CellFormat] = []
  let positions : Array[Int] = []
  let pool : Map[CellFormat, Int] = Map([])
  for row in pattern {
    for patch in row {
      patch.validate()
      let id = if pool.get(patch) is Some(id) {
        id
      } else {
        let id = patches.length()
        patches.push(patch)
        pool[patch] = id
        id
      }
      positions.push(id)
    }
  }
  let sheet = self.selection.0
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.format_reason(current, target)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let originals : Map[String, (Int, Int)] = Map([])
  for row in target.top..<=target.bottom {
    for column in target.left..<=target.right {
      let address : Address = { row, column, }
      let style = current.style_at(address)
      let id = positions[(row - target.top) %
        pattern.length() *
        pattern[0].length() +
        (column - target.left) % pattern[0].length()]
      let patch = patches[id]
      if patch.applied(self.styles[style]) != self.styles[style] {
        originals[address.name()] = (style, id)
      }
    }
  }
  if originals.is_empty() && merges.unwrap_or(current.merges) == current.merges {
    return if target.name() == self.selection.1.name() {
      self.query()
    } else {
      self.select(revision, sheet, target.name())
    }
  }
  let plan = if originals.is_empty() {
    None
  } else {
    Some(self.derive_formats(originals, patches))
  }
  let updates : Map[String, CellContent] = Map([])
  for name in originals.keys() {
    updates[name] = { value: Blank, formula: None, keep_shared: true, }
  }
  let edits = plan.map(plan => plan.edits.copy()).unwrap_or([])
  let mut document = current.document
  if plan is Some(plan) {
    let (next, edit) = current.prepare(
      updates,
      styles=plan.indices,
      preserve_values=true,
    )
    document = next
    edits.push((current.id, edit))
  }
  if merges is Some(ranges) && ranges != current.merges {
    let (next, edit) = fill_merge_changes(document, ranges)
    document = next
    edits.push((current.id, edit))
  }
  let styles = plan.map(plan => plan.styles).unwrap_or(self.styles)
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    styles.length(),
  )
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    (sheet, target),
    parts=plan.map(plan => plan.parts).unwrap_or(self.parts),
    created_parts=plan.map(plan => plan.created_parts).unwrap_or(Map([])),
  )
  self.query()
}
