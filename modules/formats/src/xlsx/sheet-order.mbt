///|
pub(all) enum SheetEdit {
  Add
  Copy
  Delete
  Move(Int)
  Visibility(String)
  Rename(String)
  RowHeight(Int, Int, Double)
  ColumnWidth(Int, Int, Double)
  InsertRows(Int, Int)
  DeleteRows(Int, Int)
  InsertColumns(Int, Int)
  DeleteColumns(Int, Int)
  InsertCells(String, String)
  DeleteCells(String, String)
  Fill(String, String)
  Merge(String, Bool)
  Unmerge(String)
  Freeze(Int, Int)
  PageSetup(PrintSetup)
  PrintRange(PrintRange)
  HeaderFooter(HeaderFooter)
  Validation(String, DataValidation?)
  ValidationValue(Int, Int)
}

///|
fn Session::ordered_sheets(
  self : Session,
  workbook : @xml.Document,
  available : Array[Sheet],
  parts : Map[String, @xml.Document],
  removed~ : Array[String] = self.removed,
) -> Array[Sheet] raise @failure.Failure {
  let tree = Tree::new(workbook)
  let container = tree.one(tree.root("workbook").id, "sheets").unwrap()
  let paths : Map[String, String] = Map([])
  for
    rel in self.opc.relationships(
      replacements=self.replacements(available, workbook, parts),
      removed~,
    ) {
    if rel.owner == self.main && rel.kind == relationship_uri + "worksheet" {
      paths[rel.id] = rel.target
    }
  }
  let sheets : Map[String, Sheet] = Map([])
  for sheet in available {
    sheets[sheet.id] = sheet
  }
  let result : Array[Sheet] = []
  for node in tree.all(container.id, "sheet") {
    let relation = node
      .attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      .unwrap_or("")
    guard paths.get(relation) is Some(part) && sheets.get(part) is Some(sheet) else {
      @failure.reject("malformed-xlsx", "Worksheet identity changed")
    }
    let state = node.attribute("state").unwrap_or("visible")
    guard ["visible", "hidden", "veryHidden"].contains(state) else {
      @failure.reject("malformed-xlsx", "Invalid worksheet visibility")
    }
    result.push({
      ..sheet,
      state,
      name: node.attribute("name").unwrap_or(sheet.name),
    })
    sheets.remove(part) |> ignore
  }
  guard sheets.is_empty() && result.any(sheet => sheet.state == "visible") else {
    @failure.reject(
      "invalid-sheet", "At least one visible worksheet is required",
    )
  }
  result
}

///|
fn Session::sheet_edit_reason(
  self : Session,
  structure~ : Bool = true,
) -> String {
  try {
    if !self.read_only.is_empty() {
      return self.read_only
    }
    let tree = Tree::new(self.workbook)
    let root = tree.root("workbook")
    if structure &&
      tree
      .one(root.id, "workbookProtection")
      .map(node => flag(node, "lockStructure"))
      .unwrap_or(false) {
      return "Workbook structure is protected"
    }
    for node in tree.children.get(root.id).unwrap_or([]) {
      if node.uri != spreadsheet_uri ||
        (
          ["extLst", "customWorkbookViews"].contains(node.name) &&
          !tree.children.get(node.id).unwrap_or([]).is_empty()
        ) {
        return "Workbook extensions or custom views require sheet structure support"
      }
    }
    if tree.one(root.id, "definedNames") is Some(names) {
      for name in tree.all(names.id, "definedName") {
        if name.attribute("localSheetId") is Some(scope) {
          ignore(natural(scope, self.sheets.length() - 1))
        }
        let tokens = formula_tokens(name.text)
        for index, token in tokens {
          if token is Operator("!") && index > 0 {
            if (tokens[index - 1] is Quoted(value, true) && value.contains(":")) ||
              (index > 1 && tokens[index - 2] is Operator(":")) {
              return "Three-dimensional name references require sheet structure support"
            }
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn visible_sheet(sheets : Array[Sheet], from : Int) -> Int {
  for index in from..<sheets.length() {
    if sheets[index].state == "visible" {
      return index
    }
  }
  for index in 0..<from {
    let index = from - index - 1
    if sheets[index].state == "visible" {
      return index
    }
  }
  abort("Visible worksheet invariant")
}

///|
pub fn Session::edit_sheet(
  self : Session,
  revision : Int,
  sheet : String,
  change : SheetEdit,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  match change {
    Validation(range, settings) =>
      return self.set_validation(sheet, range, settings)
    ValidationValue(index, source_revision) =>
      return self.pick_validation(sheet, index, source_revision)
    Fill(range, direction) => return self.fill_cells(sheet, range, direction)
    InsertRows(first, count) =>
      return self.edit_axes(sheet, {
        rows: true,
        first,
        count,
        insert: true,
        band: None,
      })
    DeleteRows(first, count) =>
      return self.edit_axes(sheet, {
        rows: true,
        first,
        count,
        insert: false,
        band: None,
      })
    InsertColumns(first, count) =>
      return self.edit_axes(sheet, {
        rows: false,
        first,
        count,
        insert: true,
        band: None,
      })
    DeleteColumns(first, count) =>
      return self.edit_axes(sheet, {
        rows: false,
        first,
        count,
        insert: false,
        band: None,
      })
    InsertCells(range, direction) | DeleteCells(range, direction) => {
      let insert = change is InsertCells(_, _)
      guard (if insert { ["down", "right"] } else { ["up", "left"] }).contains(
        direction,
      ) else {
        @failure.reject("invalid-operation", "Invalid cell shift direction")
      }
      let range = Range::parse(range)
      let rows = direction == "down" || direction == "up"
      let height = range.bottom - range.top + 1
      let width = range.right - range.left + 1
      guard height.to_int64() * width.to_int64() <= 4096 else {
        @failure.reject(
          "limit-exceeded", "Cell shift selection exceeds 4096 cells",
        )
      }
      return self.edit_axes(sheet, {
        rows,
        first: if rows {
          range.top
        } else {
          range.left
        },
        count: if rows {
          height
        } else {
          width
        },
        insert,
        band: Some(
          if rows {
            (range.left, range.right)
          } else {
            (range.top, range.bottom)
          },
        ),
      })
    }
    PageSetup(setup) => return self.set_print_setup(sheet, setup)
    PrintRange(settings) => return self.set_print_range(sheet, settings)
    HeaderFooter(settings) => return self.set_header_footer(sheet, settings)
    Freeze(rows, columns) => return self.freeze(sheet, rows, columns)
    Merge(range, discard) =>
      return self.merge_cells(sheet, Range::parse(range), discard, false)
    Unmerge(range) =>
      return self.merge_cells(sheet, Range::parse(range), false, true)
    RowHeight(first, last, size) =>
      return self.resize_dimensions(sheet, first, last, size, rows=true)
    ColumnWidth(first, last, size) =>
      return self.resize_dimensions(sheet, first, last, size, rows=false)
    _ => ()
  }
  let reason = self.sheet_edit_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let index = self.sheet_index(sheet)
  let tree = Tree::new(self.workbook)
  let root = tree.root("workbook")
  let parent = tree.one(root.id, "sheets").unwrap()
  let nodes = tree.all(parent.id, "sheet")
  let node = nodes[index]
  let changes : Array[@xml.SourceChange] = []
  let sheets = self.sheets.copy()
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let mut created : Sheet? = None
  let created_parts : Map[String, @xml.Document] = Map([])
  let mut deleted : Sheet? = None
  let mut removed : Map[String, @xml.Document] = Map([])
  let mut next_sheet = self.next_sheet
  match change {
    RowHeight(_, _, _)
    | InsertRows(_, _)
    | DeleteRows(_, _)
    | InsertColumns(_, _)
    | DeleteColumns(_, _)
    | InsertCells(_, _)
    | DeleteCells(_, _)
    | Fill(_, _)
    | ColumnWidth(_, _, _)
    | Merge(_, _)
    | Unmerge(_)
    | Freeze(_, _)
    | PageSetup(_)
    | PrintRange(_)
    | HeaderFooter(_)
    | Validation(_, _)
    | ValidationValue(_, _) => abort("Dimension edit was dispatched")
    Rename(name) => return self.rename_sheet(index, name)
    Delete => {
      removed = self.prepare_sheet_delete(index, parts, edits)
      deleted = Some(sheets.remove(index))
      changes.push(sheet_node_removal(tree, node))
      changes.append(
        sheet_reference_changes(
          self.workbook,
          self.sheets[index].name,
          None,
          deleted_scope=Some(index),
        ),
      )
      for position, sheet in sheets {
        let updates = sheet_reference_changes(
          sheet.document,
          self.sheets[index].name,
          None,
        )
        if !updates.is_empty() {
          let (document, edit) = sheet.document.edit_source(updates)
          sheets[position] = Sheet::read(
            sheet.id,
            sheet.name,
            sheet.state,
            document,
            self.strings,
            self.styles.length(),
          )
          edits.push((sheet.id, edit))
        }
      }
    }
    Add | Copy => {
      let copy = if change is Copy {
        let reason = self.sheet_rename_reason()
        guard reason.is_empty() else {
          @failure.reject("protected-content", reason)
        }
        check_sheet_copy_markup(sheets[index].document)
        Some(sheets[index])
      } else {
        None
      }
      let (added, number, markup, metadata) = self.prepare_sheet_add(copy~)
      changes.push({
        node: parent.id,
        offset: node.end - parent.start,
        length: 0,
        xml: markup,
      })
      sheets.insert(index + 1, added)
      created = Some(added)
      next_sheet = number + 1
      for (part, document, edit) in metadata {
        parts[part] = document
        edits.push((part, edit))
      }
      if copy is Some(source) {
        let (documents, types) = self.copied_sheet_parts(source, added, number)
        for part, document in documents {
          parts[part] = document
          created_parts[part] = document
        }
        if !types.is_empty() {
          let path = "[Content_Types].xml"
          let original = parts[path]
          let (document, edit) = original.edit_source([
            insertion(original.nodes()[0], types),
          ])
          parts[path] = document
          edits.push((path, edit))
        }
        changes.append(self.copied_sheet_names(index, added.name))
      }
    }
    Move(target) => {
      guard target >= 0 && target < sheets.length() else {
        @failure.reject(
          "invalid-sheet", "Worksheet position is outside the workbook",
        )
      }
      if target == index {
        return self.query()
      }
      let offset = if target < index {
        nodes[target].start
      } else {
        nodes[target].end
      }
      changes.push({
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: "",
      })
      changes.push({
        node: parent.id,
        offset: offset - parent.start,
        length: 0,
        xml: self.workbook.source()[node.start:node.end].to_owned(),
      })
      let moved = sheets.remove(index)
      sheets.insert(target, moved)
    }
    Visibility(state) => {
      guard ["visible", "hidden", "veryHidden"].contains(state) else {
        @failure.reject("invalid-sheet", "Unknown worksheet visibility")
      }
      if sheets[index].state == state {
        return self.query()
      }
      sheets[index] = { ..sheets[index], state, }
      guard sheets.any(sheet => sheet.state == "visible") else {
        @failure.reject(
          "invalid-sheet", "At least one visible worksheet is required",
        )
      }
      changes.append(metadata_changes(node, [("state", state)]))
    }
  }
  let mut after = self.selection
  let selected = sheets
    .search_by(sheet => sheet.id == after.0)
    .unwrap_or(index.min(sheets.length() - 1))
  if created is Some(added) && added.state == "visible" {
    after = (added.id, { top: 1, left: 1, bottom: 1, right: 1, })
  } else if change is Visibility("visible") {
    after = (sheet, { top: 1, left: 1, bottom: 1, right: 1, })
  } else if sheets[selected].state != "visible" ||
    (deleted is Some(item) && after.0 == item.id) {
    after = (
      sheets[visible_sheet(sheets, selected)].id,
      { top: 1, left: 1, bottom: 1, right: 1, },
    )
  }
  let active = sheets.search_by(sheet => sheet.id == after.0).unwrap()
  if tree.one(root.id, "definedNames") is Some(names) {
    for name in tree.all(names.id, "definedName") {
      if name.attribute("localSheetId") is Some(scope) {
        let old = natural(scope, self.sheets.length() - 1)
        if change is Delete && old == index {
          changes.push(sheet_node_removal(tree, name))
          continue
        }
        let updated = sheets
          .search_by(sheet => sheet.id == self.sheets[old].id)
          .unwrap()
        changes.append(
          metadata_changes(name, [("localSheetId", updated.to_string())]),
        )
      }
    }
  }
  let views = tree.one(root.id, "bookViews")
  let windows = views
    .map(node => tree.all(node.id, "workbookView"))
    .unwrap_or([])
  for window_index, window in windows {
    let old_active = natural(
      window.attribute("activeTab").unwrap_or("0"),
      self.sheets.length() - 1,
    )
    let mapped = sheets
      .search_by(sheet => sheet.id == self.sheets[old_active].id)
      .unwrap_or(index.min(sheets.length() - 1))
    let old_first = natural(
      window.attribute("firstSheet").unwrap_or("0"),
      self.sheets.length() - 1,
    )
    let first = sheets
      .search_by(sheet => sheet.id == self.sheets[old_first].id)
      .unwrap_or(index.min(sheets.length() - 1))
    changes.append(
      metadata_changes(window, [
        (
          "activeTab",
          (if window_index == 0 {
            active
          } else {
            visible_sheet(sheets, mapped)
          }).to_string(),
        ),
        ("firstSheet", visible_sheet(sheets, first).to_string()),
      ]),
    )
  }
  if windows.is_empty() {
    let prefix = root.qualified[:root.qualified.length() - 8].to_owned()
    let view = "<\{prefix}workbookView activeTab=\"\{active}\" firstSheet=\"\{visible_sheet(sheets, 0)}\"/>"
    changes.push(
      if views is Some(views) {
        insertion(views, view)
      } else {
        {
          node: root.id,
          offset: parent.start - root.start,
          length: 0,
          xml: "<\{prefix}bookViews>\{view}</\{prefix}bookViews>",
        }
      },
    )
  }
  let (workbook, edit) = self.workbook.edit_source(changes)
  edits.push((self.main, edit))
  for index, current in sheets {
    let source = Tree::new(current.document)
    if source.one(source.root("worksheet").id, "sheetViews") is Some(views) {
      let changes : Array[@xml.SourceChange] = []
      for view in source.all(views.id, "sheetView") {
        let window = natural(
          view.attribute("workbookViewId").unwrap_or("0"),
          windows.length().max(1) - 1,
        )
        if current.state != "visible" || window == 0 {
          changes.append(
            metadata_changes(view, [
              (
                "tabSelected",
                if current.state == "visible" && current.id == after.0 {
                  "1"
                } else {
                  "0"
                },
              ),
            ]),
          )
        }
      }
      if !changes.is_empty() {
        let (document, edit) = current.document.edit_source(changes)
        sheets[index] = Sheet::read(
          current.id,
          current.name,
          current.state,
          document,
          self.strings,
          self.styles.length(),
        )
        edits.push((current.id, edit))
      }
    }
  }
  let calculation = Calculation::build(sheets, None, [], self.date1904)
  if deleted is Some(_) || change is Copy {
    edits.append(self.cache_edits(sheets, calculation))
  }
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    after,
    parts~,
    created~,
    created_parts~,
    deleted~,
    removed~,
  )
  self.next_sheet = next_sheet
  self.query()
}
