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
    let name = node.attribute("name").unwrap_or(sheet.name)
    result.push({
      ..sheet,
      state,
      name,
      sparklines: if name == sheet.name {
        sheet.sparklines
      } else {
        read_sparklines(Tree::new(sheet.document), name, sheet.merges)
      },
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
fn Session::edit_sheet_current(
  self : Session,
  revision : Int,
  sheet : String,
  change : SheetEdit,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  match change {
    Sparkline(cell, source, kind) =>
      return self.set_sparkline(sheet, cell, source, kind)
    WorkbookProtection(enabled, password, salt) =>
      return self.set_workbook_protection(enabled, password, salt)
    Protection(enabled, password, salt) =>
      return self.set_protection(sheet, enabled, password, salt)
    MoveCells(source_sheet, source, destination) =>
      return self.move_cells(source_sheet, source, sheet, destination)
    GroupOutline(_, _, _, _)
    | CollapseOutline(_, _, _, _, _)
    | ClearOutline(_)
    | OutlineSummary(_, _) => return self.edit_outline(sheet, change)
    Note(cell, text, author) => return self.set_note(sheet, cell, text, author)
    DrawingOrder(id, direction) =>
      return self.order_drawing(sheet, id, direction)
    DuplicateDrawing(id) => return self.duplicate_drawing(sheet, id)
    MoveDrawing(source, id) => return self.move_drawing(source, id, sheet)
    Hyperlink(range, target) => return self.set_hyperlink(sheet, range, target)
    OpenHyperlink(range, source_revision) =>
      return self.open_hyperlink(sheet, range, source_revision)
    SetFilter(_) | ClearFilter | RemoveFilter | ReapplyFilter =>
      return self.edit_filter(sheet, change)
    TableFilter(id, columns) => {
      let table = self.table_for_edit(sheet, id)
      return self.edit_filter(
        sheet,
        SetFilter({
          range: Range::{
            ..table.range,
            bottom: table.range.bottom - table.totals,
          }.name(),
          columns,
        }),
        table=Some(table),
      )
    }
    TableFilterClear(id) | TableFilterRemove(id) | TableFilterReapply(id) => {
      let table = self.table_for_edit(sheet, id)
      let action = match change {
        TableFilterClear(_) => ClearFilter
        TableFilterRemove(_) => RemoveFilter
        _ => ReapplyFilter
      }
      return self.edit_filter(sheet, action, table=Some(table))
    }
    ConditionalRule(range, priority, settings, source_revision) =>
      return self.set_conditional(
        sheet, range, priority, settings, source_revision,
      )
    ConditionalPriority(priority, position, source_revision) =>
      return self.move_conditional(sheet, priority, position, source_revision)
    Validation(range, settings) =>
      return self.set_validation(sheet, range, settings)
    ValidationValue(index, source_revision) =>
      return self.pick_validation(sheet, index, source_revision)
    Fill(range, direction) => return self.fill_cells(sheet, range, direction)
    Series(mode, source, range, direction) =>
      return self.fill_series(sheet, mode, source, range, direction)
    Sort(range, settings) => return self.sort_cells(sheet, range, settings)
    RemoveDuplicates(settings, source_revision) =>
      return self.remove_duplicates(sheet, settings, source_revision)
    TextToColumns(settings, source_revision, overwrite) =>
      return self.split_text_columns(
        sheet, settings, source_revision, overwrite,
      )
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
    View(settings) => return self.set_view(sheet, settings)
    RenameTable(id, name) => return self.rename_table(sheet, id, name)
    CreateTable(range, name) => return self.create_table(sheet, range, name)
    ResizeTable(id, range) => return self.resize_table(sheet, id, range)
    TableColumnFormula(id, column, formula) =>
      return self.set_table_column_formula(sheet, id, column, formula)
    TableTotals(id, visible) =>
      return self.show_table_totals(sheet, id, visible)
    TableStyle(id, settings) => return self.set_table_style(sheet, id, settings)
    TableStyleDefinition(original, name, elements) =>
      return self.edit_table_style_definition(
        sheet,
        original,
        name,
        Some(elements),
      )
    DeleteTableStyle(name, replacement) =>
      return self.edit_table_style_definition(
        sheet,
        Some(name),
        replacement.unwrap_or(""),
        None,
      )
    TableColumnTotal(id, column, total) =>
      return self.set_table_total(sheet, id, column, total)
    RenameTableColumn(id, column, name) =>
      return self.rename_table(sheet, id, name, column=Some(column))
    SetName(settings) => return self.edit_name(settings)
    DeleteName(name, scope) =>
      return self.edit_name(
        { original: Some(name), name, scope, formula: "", },
        delete=true,
      )
    SelectName(name, scope) => return self.select_name(name, scope)
    Merge(range, discard) =>
      return self.merge_cells(sheet, Range::parse(range), discard, false)
    Unmerge(range) =>
      return self.merge_cells(sheet, Range::parse(range), false, true)
    RowHeight(first, last, size) =>
      return self.resize_dimensions(sheet, first, last, size, rows=true)
    ColumnWidth(first, last, size) =>
      return self.resize_dimensions(sheet, first, last, size, rows=false)
    Rename(name) => return self.rename_sheet(self.sheet_index(sheet), name)
    _ => ()
  }
  let reason = self.sheet_edit_reason(analysis=change is Delete)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let index = self.sheet_index(sheet)
  let context = {
    ..self,
    parts: self.parts.copy(),
    sheets: self.sheets.copy(),
    removed: self.removed.copy(),
  }
  let edits : Array[(String, @xml.Edit)] = []
  let removed : Map[String, @xml.Document] = Map([])
  let analysis_parts = if change is Delete {
    let reason = self.sheet_rename_reason(
      tables=true,
      pivots=true,
      sparklines=true,
      pictures=true,
      charts=true,
      analysis=true,
    )
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    context.prepare_analysis_sheet_delete(sheet, edits, removed)
  } else {
    []
  }
  let tree = Tree::new(context.workbook)
  let root = tree.root("workbook")
  let parent = tree.one(root.id, "sheets").unwrap()
  let nodes = tree.all(parent.id, "sheet")
  let node = nodes[index]
  let changes : Array[@xml.SourceChange] = []
  let sheets = context.sheets.copy()
  let parts = context.parts
  let pivot_edits : Array[String] = []
  let mut created : Sheet? = None
  let created_parts : Map[String, @xml.Document] = Map([])
  let mut deleted : Sheet? = None
  let mut next_sheet = self.next_sheet
  match change {
    RowHeight(_, _, _)
    | GroupOutline(_, _, _, _)
    | CollapseOutline(_, _, _, _, _)
    | ClearOutline(_)
    | OutlineSummary(_, _)
    | InsertRows(_, _)
    | DeleteRows(_, _)
    | InsertColumns(_, _)
    | DeleteColumns(_, _)
    | InsertCells(_, _)
    | DeleteCells(_, _)
    | MoveCells(_, _, _)
    | Fill(_, _)
    | Series(_, _, _, _)
    | Sort(_, _)
    | RemoveDuplicates(_, _)
    | TextToColumns(_, _, _)
    | SetFilter(_)
    | TableFilter(_, _)
    | TableFilterClear(_)
    | TableFilterRemove(_)
    | TableFilterReapply(_)
    | ClearFilter
    | RemoveFilter
    | ReapplyFilter
    | ColumnWidth(_, _, _)
    | Merge(_, _)
    | Unmerge(_)
    | Freeze(_, _)
    | View(_)
    | SetName(_)
    | RenameTable(_, _)
    | CreateTable(_, _)
    | ResizeTable(_, _)
    | TableColumnFormula(_, _, _)
    | TableTotals(_, _)
    | TableStyle(_, _)
    | TableStyleDefinition(_, _, _)
    | DeleteTableStyle(_, _)
    | TableColumnTotal(_, _, _)
    | RenameTableColumn(_, _, _)
    | DeleteName(_, _)
    | SelectName(_, _)
    | PageSetup(_)
    | PrintRange(_)
    | HeaderFooter(_)
    | Validation(_, _)
    | ValidationValue(_, _)
    | ConditionalRule(_, _, _, _)
    | Sparkline(_, _, _)
    | Hyperlink(_, _)
    | OpenHyperlink(_, _)
    | Protection(_, _, _)
    | WorkbookProtection(_, _, _)
    | Note(_, _, _)
    | DrawingOrder(_, _)
    | DuplicateDrawing(_)
    | MoveDrawing(_, _)
    | ConditionalPriority(_, _, _)
    | Rename(_) => abort("Dimension edit was dispatched")
    Delete => {
      context.sheet_chart_references(
        self.sheets[index].name,
        None,
        parts,
        edits,
        deleted=Some(sheet),
      )
      let deleted_parts = context.prepare_sheet_delete(
        index,
        parts,
        edits,
        changes,
        pivot_edits,
        analysis_parts~,
        profiles=Some(self),
      )
      for path, document in deleted_parts {
        removed[path] = document
      }
      deleted = Some(sheets.remove(index))
      changes.push(sheet_node_removal(tree, node))
      changes.append(
        sheet_reference_changes(
          context.workbook,
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
          sparklines=true,
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
        let reason = self.sheet_rename_reason(
          tables=true,
          pivots=true,
          sparklines=true,
          pictures=true,
          charts=true,
        )
        guard reason.is_empty() else {
          @failure.reject("protected-content", reason)
        }
        ignore(read_filter(sheets[index]))
        let tree = Tree::new(sheets[index].document)
        check_sheet_copy_markup(
          sheets[index].document,
          filter=tree.one(tree.root("worksheet").id, "autoFilter"),
          sparkline=tree.one(tree.root("worksheet").id, "extLst"),
        )
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
        let (documents, types, tables) = self.copied_sheet_parts(
          source, added, number,
        )
        let document = self.copied_table_references(added.document, tables)
        let added = Sheet::read(
          added.id,
          added.name,
          added.state,
          document,
          self.strings,
          self.styles.length(),
        )
        sheets[index + 1] = added
        created = Some(added)
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
        changes.append(self.copied_sheet_names(index, added.name, tables~))
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
        xml: context.workbook.source()[node.start:node.end].to_owned(),
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
  let (workbook, edit) = context.workbook.edit_source(changes)
  let mut workbook = workbook
  edits.push((self.main, edit))
  let table_edits = if change is Delete {
    let tables = self.sheet_tables()
    self.sheet_table_references(
      tables,
      self.sheets[index].name,
      None,
      parts,
      edits,
    )
    workbook = self.table_reference_removals(
      sheets,
      workbook,
      tables
      .filter(table => table.sheet == sheet)
      .map(table => {
        (table, table.columns.map(column => column.name.to_upper()), true)
      }),
      tables.filter(table => table.sheet != sheet),
      parts,
      edits,
    )
    tables.map(table => table.part)
  } else {
    []
  }
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
  let removed_parts = [
    ..self.removed,
    ..removed
    .keys()
    .filter(part => self.opc.names.contains(part.to_lower()))
    .to_array(),
  ]
  let calculation = self.calculate(
    sheets,
    None,
    [],
    workbook,
    parts~,
    removed=removed_parts,
  )
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
    table_edits~,
    pivot_edits~,
  )
  self.next_sheet = next_sheet
  self.query()
}
