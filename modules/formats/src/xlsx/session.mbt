///|
pub const WorksheetCount : Int32 = 256

///|
priv struct History {
  before_random : Map[(Int32, Address), (Value, String?)]
  after_random : Map[(Int32, Address), (Value, String?)]
  edits : Array[(String, @xml.Edit)]
  mut created : Sheet?
  created_parts : Map[String, @xml.Document]
  mut deleted : Sheet?
  removed : Map[String, @xml.Document]
  added_media : Map[String, Bytes]
  bytes : Int32
  before : (String, Range)
  after : (String, Range)
  before_picture : (String, String)?
  after_picture : (String, String)?
}

///|
pub struct Session {
  priv opc : @opc.Package
  priv main : String
  priv mut workbook : @xml.Document
  priv mut parts : Map[String, @xml.Document]
  priv mut media : Map[String, Bytes]
  priv mut removed : Array[String]
  priv mut next_sheet : Int32
  priv budget : @archive.Budget
  priv strings : Array[(String, Bool)]
  priv strings_part : String?
  priv mut styles : Array[CellStyle]
  priv theme : Array[String]
  priv normal_font : String
  priv normal_size : Double
  priv mut font_context : (@layout.TextProbe, Map[String, String])?
  priv date1904 : Bool
  priv random : @random.Rand?
  priv mut calendar_date : (Int32, Int32, Int32)?
  priv mut sheets : Array[Sheet]
  priv mut selection : (String, Range)
  priv mut drawing_selection : (String, String)?
  priv slicer_scrolls : Map[(String, String), Int32]
  priv mut anchor : Address
  priv mut focus : Address
  priv mut grid : Grid?
  priv mut grid_id : Int32
  priv mut revision : Int32
  priv mut read_cache : ReadCache?
  priv history : Array[History]
  priv redo : Array[History]
  priv mut history_bytes : Int32
  priv mut read_only : String
  priv mut calculation : Calculation?
  priv mut closed : Bool
  priv diagnostics : Array[String]
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
  date~ : String? = None,
  random_seed~ : Bytes? = None,
) -> Session raise @failure.Failure {
  Session::from_package(
    @opc.Package::open(bytes, budget),
    budget,
    date~,
    random_seed~,
  )
}

///|
fn Session::from_package(
  opc : @opc.Package,
  budget : @archive.Budget,
  date~ : String? = None,
  random_seed~ : Bytes? = None,
) -> Session raise @failure.Failure {
  errdefer opc.close()
  let random = formula_random(random_seed)
  guard !opc.signed else {
    @failure.reject("unsupported-xlsx", "Signed workbooks are unsupported")
  }
  let relationships = opc.relationships()
  let mains = relationships
    .iter()
    .filter(rel => {
      rel.owner == "" &&
      (
        rel.kind == relationship_uri + "officeDocument" ||
        rel.kind == strict_relationship_uri + "officeDocument"
      )
    })
    .collect()
  guard mains is [main] && !main.external else {
    @failure.reject(
      "malformed-xlsx", "Expected one internal workbook relationship",
    )
  }
  let strict = main.kind == strict_relationship_uri + "officeDocument"
  let relationship = if strict {
    strict_relationship_uri
  } else {
    relationship_uri
  }
  let spreadsheet = if strict {
    strict_spreadsheet_uri
  } else {
    spreadsheet_uri
  }
  let other_relationship = if strict {
    relationship_uri
  } else {
    "http://purl.oclc.org/ooxml/"
  }
  guard !relationships
    .iter()
    .any(rel => rel.kind.has_prefix(other_relationship)) else {
    @failure.reject(
      "unsupported-xlsx", "Mixed SpreadsheetML relationship dialects",
    )
  }
  let main = main.target
  guard opc.content_type(main) ==
    Some(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
    ) else {
    @failure.reject(
      "unsupported-xlsx",
      "Expected XLSX workbook content type",
      part=main,
    )
  }
  let workbook = opc.xml(main)
  let tree = Tree::new(workbook)
  let root = tree.root("workbook")
  guard root.uri == spreadsheet else {
    @failure.reject(
      "malformed-xlsx",
      "Workbook namespace and relationship disagree",
      part=main,
    )
  }
  let relations : Map[String, @opc.Relationship] = Map([])
  let strings : Array[(String, Bool)] = []
  let mut strings_part : String? = None
  let mut has_styles = false
  let mut font_count = 0
  let theme = read_theme(opc, main, relationship)
  let mut cell_styles = [default_style()]
  let mut base_font = (default_style().font, default_style().size)
  for rel in relationships {
    if rel.owner != main {
      continue
    }
    relations[rel.id] = rel
    if rel.kind == relationship + "sharedStrings" {
      guard !rel.external && strings_part is None else {
        @failure.reject("malformed-xlsx", "Invalid shared strings relationship")
      }
      strings_part = Some(rel.target)
      let shared = Tree::new(opc.xml(rel.target))
      let root = shared.root("sst")
      guard root.uri == spreadsheet else {
        @failure.reject(
          "malformed-xlsx",
          "Shared strings namespace and relationship disagree",
          part=rel.target,
        )
      }
      let mut units = 0
      for item in shared.all(root.id, "si") {
        let value = shared.text(item.id)
        units += value.0.length()
        guard strings.length() < 100000 && units <= 4194304 else {
          @failure.reject("limit-exceeded", "Shared strings exceed budget")
        }
        strings.push(value)
      }
    }
    if rel.kind == relationship + "styles" {
      guard !rel.external && !has_styles else {
        @failure.reject("malformed-xlsx", "Invalid styles relationship")
      }
      has_styles = true
      let styles = Tree::new(opc.xml(rel.target))
      let style_root = styles.root("styleSheet")
      guard style_root.uri == spreadsheet else {
        @failure.reject(
          "malformed-xlsx",
          "Styles namespace and relationship disagree",
          part=rel.target,
        )
      }
      cell_styles = read_styles(styles, theme)
      base_font = normal_font(styles)
      font_count = styles
        .one(style_root.id, "fonts")
        .map(node => styles.all(node.id, "font").length())
        .unwrap_or(0)
    }
  }
  let container = tree
    .one(root.id, "sheets")
    .unwrap_or_error(
      @failure.Failure(
        code="malformed-xlsx",
        part=main,
        offset=-1,
        message="Missing sheets",
      ),
    )
  let sheets : Array[Sheet] = []
  let legacy_drawings : Array[Result[@xml.Node?, @failure.Failure]] = []
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  let paths : Map[String, Bool] = Map([])
  let diagnostics : Array[String] = []
  let mut cell_count = 0
  let read_only = if strict { "Strict XLSX is read-only" } else { "" }
  for node in tree.all(container.id, "sheet") {
    let name = node.attribute("name").unwrap_or("")
    let id = node.attribute("sheetId").unwrap_or("")
    let relation = node
      .attribute("id", uri=relationship[:relationship.length() - 1].to_owned())
      .unwrap_or("")
    guard !name.is_empty() &&
      name.length() <= 31 &&
      !names.contains(name.to_lower()) &&
      !ids.contains(id) &&
      natural(id, 2147483647) > 0 &&
      relations.get(relation) is Some(rel) &&
      !rel.external &&
      ["worksheet", "chartsheet"].any(kind => rel.kind == relationship + kind) &&
      !paths.contains(rel.target) else {
      @failure.reject(
        "malformed-xlsx",
        "Invalid worksheet identity or relationship",
        part=main,
      )
    }
    let state = node.attribute("state").unwrap_or("visible")
    guard ["visible", "hidden", "veryHidden"].contains(state) else {
      @failure.reject("malformed-xlsx", "Invalid worksheet visibility")
    }
    guard sheets.length() < WorksheetCount else {
      @failure.reject("limit-exceeded", "Worksheet count exceeds budget")
    }
    let document = opc.xml(rel.target)
    let kind = if rel.kind == relationship + "chartsheet" {
      "chartsheet"
    } else {
      "worksheet"
    }
    let source = Tree::new(document)
    let sheet_root = source.sheet_root()
    guard opc.content_type(rel.target) ==
      Some(
        "application/vnd.openxmlformats-officedocument.spreadsheetml." +
        kind +
        "+xml",
      ) &&
      sheet_root.name == kind &&
      sheet_root.uri == spreadsheet else {
      @failure.reject(
        "malformed-xlsx",
        "Sheet relationship, content type and root disagree",
        part=rel.target,
      )
    }
    let sheet = Sheet::read(
      rel.target,
      name,
      state,
      document,
      strings,
      cell_styles.length(),
      tree=source,
    )
    cell_count += sheet.cells.length()
    guard cell_count <= 100000 else {
      @failure.reject("limit-exceeded", "Workbook cell count exceeds budget")
    }
    for child in source.children.get(sheet_root.id).unwrap_or([]) {
      if !sheet.is_chart() &&
        (
          phonetic_defaults(source, child, font_count) ||
          neutral_mac_page_layout(source, child)
        ) {
        continue
      }
      if sheet.sparklines.reason.is_empty() &&
        sparkline_extension(source, child) {
        continue
      }
      if ![
          "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
          "mergeCells", "sheetProtection", "pageMargins", "pageSetup", "printOptions",
          "headerFooter", "autoFilter", "sortState", "dataValidations", "conditionalFormatting",
          "hyperlinks", "legacyDrawing",
        ].contains(child.name) ||
        child.uri != spreadsheet {
        diagnostics.push("unrendered:" + sheet.id + ":" + child.qualified)
      }
    }
    // Preserve worksheet validation before checking legacy note metadata.
    legacy_drawings.push(
      if sheet.is_chart() {
        Ok(None)
      } else {
        Ok(source.one(sheet_root.id, "legacyDrawing")) catch {
          error => Err(error)
        }
      },
    )
    sheets.push(sheet)
    ids[id] = true
    names[name.to_lower()] = true
    paths[rel.target] = true
  }
  guard !sheets.is_empty() && sheets.any(sheet => sheet.state == "visible") else {
    @failure.reject("malformed-xlsx", "Workbook has no visible worksheet")
  }
  for sheet in sheets {
    let reason = sparkline_reason(sheet, sheets)
    if sheet.sparklines.reason.is_empty() && !reason.is_empty() {
      diagnostics.push("unrendered:" + sheet.id + ":" + reason)
    }
  }
  let active = tree
    .one(root.id, "bookViews")
    .bind(node => tree.all(node.id, "workbookView").get(0))
    .map(node => {
      natural(node.attribute("activeTab").unwrap_or("0"), sheets.length() - 1)
    })
    .unwrap_or(0)
  let active = sheets[visible_sheet(sheets, active)].id
  let session : Session = {
    opc,
    main,
    workbook,
    parts: Map([]),
    media: Map([]),
    removed: [],
    next_sheet: 1,
    budget,
    strings,
    strings_part,
    styles: cell_styles,
    theme,
    normal_font: base_font.0,
    normal_size: base_font.1,
    font_context: None,
    calendar_date: date.map(filter_current_date),
    date1904: tree
    .one(root.id, "workbookPr")
    .map(node => flag(node, "date1904"))
    .unwrap_or(false),
    sheets,
    selection: (active, { top: 1, left: 1, bottom: 1, right: 1, }),
    anchor: { row: 1, column: 1, },
    focus: { row: 1, column: 1, },
    grid: None,
    drawing_selection: None,
    slicer_scrolls: Map([]),
    grid_id: 0,
    revision: 0,
    read_cache: None,
    history: [],
    redo: [],
    history_bytes: 0,
    read_only,
    closed: false,
    diagnostics,
    calculation: None,
    random,
  }
  session.validate(session.sheets)
  for index, sheet in session.sheets {
    let legacy = match legacy_drawings[index] {
      Ok(node) => node
      Err(error) => raise error
    }
    if legacy is Some(legacy) {
      ignore(session.read_sheet_notes(sheet, allow_threads=true)) catch {
        @failure.Failure(..) =>
          session.diagnostics.push(
            "unrendered:" + sheet.id + ":" + legacy.qualified,
          )
      }
    }
  }
  session.calculation = Some(
    session.calculate(session.sheets, None, [], session.workbook),
  ) catch {
    @failure.Failure(code~, message~, ..) if code == "unsupported-formula" ||
      code == "formula-syntax" ||
      code == "invalid-address" ||
      code == "circular-reference" => {
      if session.read_only.is_empty() {
        session.read_only = message
      }
      None
    }
    error => raise error
  }
  session
}

///|
fn Session::check(self : Session) -> Unit raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "XLSX session is closed")
  }
}

///|
pub fn Session::current_revision(
  self : Session,
) -> Int32 raise @failure.Failure {
  self.check()
  self.revision
}

///|
fn Session::check_revision(
  self : Session,
  revision : Int32,
) -> Unit raise @failure.Failure {
  self.check()
  guard revision == self.revision else {
    @failure.reject("revision-conflict", "Workbook revision changed")
  }
}

///|
fn Session::sheet_index(
  self : Session,
  id : String,
) -> Int32 raise @failure.Failure {
  self.check()
  for index, sheet in self.sheets {
    if sheet.id == id {
      return index
    }
  }
  @failure.reject("invalid-sheet", "Unknown worksheet identity")
}

///|
pub fn Session::query(
  self : Session,
  sheet~ : String? = None,
  range~ : String? = None,
) -> Json raise @failure.Failure {
  self.check()
  let id = sheet.unwrap_or(self.selection.0)
  let sheet_index = self.sheet_index(id)
  let current = self.sheets[sheet_index]
  let range = range.map(Range::parse).unwrap_or(self.selection.1)
  let cells : Array[QueryCell] = []
  let selected : Array[Cell] = []
  let area = (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64()
  // Only enumerate addresses when the rectangle is much smaller than the sheet.
  if area <= (current.cells.length() / 16).min(256).to_int64() {
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        let key = Address::{ row, column, }.name()
        if current.cells.get(key) is Some(cell) {
          selected.push(cell)
        }
      }
    }
  } else {
    for cell in current.cells.values() {
      if range.contains(cell.address) {
        guard selected.length() < 4096 else {
          @failure.reject(
            "limit-exceeded", "Query exceeds 4096 cells; request a smaller rectangle",
          )
        }
        selected.push(cell)
      }
    }
    selected.sort_by((a, b) => {
      if a.address.row == b.address.row {
        a.address.column.compare(b.address.column)
      } else {
        a.address.row.compare(b.address.row)
      }
    })
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    random: None,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  // Formatting diagnostics keep a post-commit query from reporting a failed write.
  let conditional : ConditionalRules = self.read_conditional_rules(
    sheet_index, work,
  ) catch {
    @failure.Failure(code="limit-exceeded", message~, ..) =>
      {
        rules: [],
        table_styles: TableStyles::empty(),
        reason: message,
        scales: ConditionalMemo::new(),
        duplicates: ConditionalMemo::new(),
      }
    error => raise error
  }
  let diagnostics = self.diagnostics.filter(diagnostic => {
    !conditional.renders(diagnostic, current)
  })
  if !conditional.reason.is_empty() {
    diagnostics.push(
      "conditional-format:" + current.id + ":" + conditional.reason,
    )
  }
  for cell in selected {
    let calculated = self.calculation.bind(calculation => {
      calculation.values.get((sheet_index, cell.address))
    })
    let details = current.query_cell(
      cell.address,
      self.cell_edit_reason(current, cell.address),
      calculated,
      hide_formula=self.styles[current.style_at(cell.address)].formula_hidden,
      calculation_reason=self.cell_calculation_reason(sheet_index, cell.address),
    )
    let value = calculated.unwrap_or(cell.value)
    if current.view.formulas || !(cell.formula is Some(_) && value == Blank) {
      let base = self.styles[cell.style]
      let style = conditional.applied(
        base,
        cell.address,
        self.sheets,
        sheet_index,
        self.calculation.map(c => c.values).unwrap_or(Map([])),
        work,
      ) catch {
        @failure.Failure(code="limit-exceeded", message~, ..) =>
          { ..base, diagnostic: message, }
        error => raise error
      }
      details.display = current.view.display(
        cell.formula,
        value,
        style.format,
        self.date1904,
        hidden=current.locked && style.formula_hidden,
      )
      if !style.diagnostic.is_empty() {
        let diagnostic = "cell-style:" + current.id + ":" + style.diagnostic
        if !diagnostics.contains(diagnostic) {
          diagnostics.push(diagnostic)
        }
      }
    }
    cells.push(details)
  }
  if !current.is_chart() &&
    range.top == range.bottom &&
    range.left == range.right &&
    cells.is_empty() {
    cells.push(
      current.query_cell(
        { row: range.top, column: range.left, },
        self.cell_edit_reason(current, { row: range.top, column: range.left, }),
        None,
        hide_formula=false,
        calculation_reason="",
      ),
    )
  }
  let current_tree = Tree::new(current.document)
  let reference_reason = self.sheet_rename_reason(
    tables=true,
    sparklines=true,
    pictures=true,
    charts=true,
    analysis=true,
    threads=true,
    current_tree~,
  )
  let copy_reason = if reference_reason.is_empty() {
    ""
  } else {
    self.sheet_rename_reason(
      tables=true,
      pivots=true,
      sparklines=true,
      pictures=true,
      charts=true,
      analysis=true,
      threads=true,
      current_tree~,
    )
  }
  let result : QueryState = {
    revision: self.revision,
    sheets: self.sheets.map(sheet => {
      id: sheet.id,
      name: sheet.name,
      state: sheet.state,
      kind: if sheet.is_chart() {
        "chartsheet"
      } else {
        "worksheet"
      },
      locked: sheet.locked,
    }),
    mainPart: self.main,
    fontKeys: self.font_keys(),
    sheet: current.id,
    outline: self.outline_query(current, current_tree),
    tables: self.table_query(current, current_tree),
    tableStyles: self
    .custom_table_styles(self.parts)
    .values()
    .to_array()
    .map(style => {
      name: style.name,
      readOnlyReason: style.reason,
      elements: if style.reason.is_empty() {
        table_element_order()
        .iter()
        .filter_map(kind => style.elements.get(kind))
        .to_array()
      } else {
        []
      },
    }),
    view: {
      gridLines: current.view.grid_lines,
      headings: current.view.headings,
      rtl: current.view.rtl,
      formulas: current.view.formulas,
      readOnlyReason: self.freeze_reason(current),
    },
    statistics: self.selection_statistics(sheet_index, range, selected),
    filter: self.filter_query(sheet_index, tree=current_tree),
    sparklines: self.sparkline_query(current),
    names: self.names_query(current_tree),
    hyperlink: self.hyperlink_query(
      current,
      current.merge_target(range),
      current_tree,
    ),
    cells,
    selection: {
      sheet: self.selection.0,
      range: self.selection.1,
      address: self.selection.1.name(),
    },
    canUndo: !self.history.is_empty(),
    canRedo: !self.redo.is_empty(),
    historyBytes: self.history_bytes,
    readOnlyReason: self.read_only,
    note: self.note_query(current, range),
    sheetEditReason: self.sheet_edit_reason(analysis=true),
    protection: self.protection_query(current, current_tree),
    workbookProtection: self.workbook_protection_query(),
    sheetRenameReason: reference_reason,
    sheetCopyReason: copy_reason,
    sheetDeleteReason: copy_reason,
    frozen: {
      rows: current.frozen.rows,
      columns: current.frozen.columns,
      readOnlyReason: self.freeze_reason(current),
    },
    printSetup: self.print_setup_query(current, current_tree),
    dataValidation: self.validation_query(sheet_index, range, current_tree),
    conditionalFormats: self.conditional_query(
      current, conditional, current_tree,
    ),
    printRange: self.print_range_query(sheet_index),
    headerFooter: self.header_footer_query(current, current_tree),
    dimensions: {
      rowHeight: {
        value: (if self.grid is Some(grid) &&
          grid.revision == self.revision &&
          grid.sheet == current.id {
          grid.dimensions.rows
        } else {
          current.dimensions.rows
        }).uniform(range.top, range.bottom),
      },
      columnWidth: {
        value: current.dimensions.columns.uniform(range.left, range.right),
      },
      readOnlyReason: self.dimension_reason(current),
    },
    formatting: self.formatting(current, range),
    normalFont: self.normal_font,
    merging: self.merging(current, range, selected, current_tree),
    diagnostics,
    date1904: self.date1904,
  }
  ToJson::to_json(result)
}

///|
pub fn Session::select(
  self : Session,
  revision : Int32,
  sheet : String,
  range : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let index = self.sheet_index(sheet)
  guard self.sheets[index].state == "visible" else {
    @failure.reject(
      "invalid-sheet", "Show a hidden worksheet before selecting it",
    )
  }
  let parsed = Range::parse(range)
  let selected = if parsed.top == parsed.bottom && parsed.left == parsed.right {
    let merged = self.sheets[index].cell_range({
      row: parsed.top,
      column: parsed.left,
    })
    {
      top: merged.top,
      bottom: merged.top,
      left: merged.left,
      right: merged.left,
    }
  } else {
    parsed
  }
  let result = self.query(sheet=Some(sheet), range=Some(selected.name()))
  self.selection = (sheet, selected)
  self.drawing_selection = None
  self.anchor = { row: selected.top, column: selected.left, }
  self.focus = { row: selected.bottom, column: selected.right, }
  if result is Object(fields) {
    fields["selection"] = {
      "sheet": sheet,
      "range": selected,
      "address": selected.name(),
    }
  }
  result
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.closed = true
  self.read_cache = None
  self.sheets.clear()
  self.parts.clear()
  self.media.clear()
  self.removed.clear()
  self.strings.clear()
  self.history.clear()
  self.redo.clear()
  self.diagnostics.clear()
  self.history_bytes = 0
  self.calculation = None
  self.font_context = None
  self.grid = None
  self.drawing_selection = None
  self.opc.close()
  self.slicer_scrolls.clear()
}
