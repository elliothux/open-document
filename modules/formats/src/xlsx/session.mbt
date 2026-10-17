///|
priv struct History {
  edits : Array[(String, @xml.Edit)]
  mut created : Sheet?
  created_parts : Map[String, @xml.Document]
  mut deleted : Sheet?
  removed : Map[String, @xml.Document]
  bytes : Int
  before : (String, Range)
  after : (String, Range)
}

///|
pub struct Session {
  priv opc : @opc.Package
  priv main : String
  priv mut workbook : @xml.Document
  priv mut parts : Map[String, @xml.Document]
  priv mut removed : Array[String]
  priv mut next_sheet : Int
  priv budget : @archive.Budget
  priv strings : Array[(String, Bool)]
  priv strings_part : String?
  priv mut styles : Array[CellStyle]
  priv theme : Array[String]
  priv normal_font : String
  priv normal_size : Double
  priv mut font_context : (@layout.TextProbe, Map[String, String])?
  priv date1904 : Bool
  priv mut sheets : Array[Sheet]
  priv mut selection : (String, Range)
  priv mut anchor : Address
  priv mut focus : Address
  priv mut grid : Grid?
  priv mut grid_id : Int
  priv mut revision : Int
  priv history : Array[History]
  priv redo : Array[History]
  priv mut history_bytes : Int
  priv mut read_only : String
  priv mut calculation : Calculation?
  priv mut closed : Bool
  priv diagnostics : Array[String]
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  Session::from_package(@opc.Package::open(bytes, budget), budget)
}

///|
fn Session::from_package(
  opc : @opc.Package,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  errdefer opc.close()
  guard !opc.signed else {
    @failure.reject("unsupported-xlsx", "Signed workbooks are unsupported")
  }
  let mains = opc
    .relationships()
    .iter()
    .filter(rel => {
      rel.owner == "" && rel.kind == relationship_uri + "officeDocument"
    })
    .collect()
  guard mains is [main] && !main.external else {
    @failure.reject(
      "malformed-xlsx", "Expected one internal workbook relationship",
    )
  }
  let main = main.target
  guard opc.content_type(main) ==
    Some(
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
    ) else {
    @failure.reject(
      "unsupported-xlsx",
      "Only Transitional XLSX workbooks are supported",
      part=main,
    )
  }
  let workbook = opc.xml(main)
  let tree = Tree::new(workbook)
  let root = tree.root("workbook")
  let relations : Map[String, @opc.Relationship] = Map([])
  let strings : Array[(String, Bool)] = []
  let mut strings_part : String? = None
  let mut has_styles = false
  let theme = read_theme(opc, main)
  let mut cell_styles = [default_style()]
  let mut base_font = (default_style().font, default_style().size)
  for rel in opc.relationships() {
    guard !rel.kind.has_prefix("http://purl.oclc.org/ooxml/") else {
      @failure.reject("unsupported-xlsx", "Strict OOXML is unsupported")
    }
    if rel.owner != main {
      continue
    }
    relations[rel.id] = rel
    if rel.kind == relationship_uri + "sharedStrings" {
      guard !rel.external && strings_part is None else {
        @failure.reject("malformed-xlsx", "Invalid shared strings relationship")
      }
      strings_part = Some(rel.target)
      let shared = Tree::new(opc.xml(rel.target))
      let root = shared.root("sst")
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
    if rel.kind == relationship_uri + "styles" {
      guard !rel.external && !has_styles else {
        @failure.reject("malformed-xlsx", "Invalid styles relationship")
      }
      has_styles = true
      cell_styles = read_styles(opc.xml(rel.target), theme)
      base_font = normal_font(opc.xml(rel.target))
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
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  let paths : Map[String, Bool] = Map([])
  let diagnostics : Array[String] = []
  let mut cell_count = 0
  let read_only = ""
  for node in tree.all(container.id, "sheet") {
    let name = node.attribute("name").unwrap_or("")
    let id = node.attribute("sheetId").unwrap_or("")
    let relation = node
      .attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      .unwrap_or("")
    guard !name.is_empty() &&
      name.length() <= 31 &&
      !names.contains(name.to_lower()) &&
      !ids.contains(id) &&
      natural(id, 2147483647) > 0 &&
      relations.get(relation) is Some(rel) &&
      !rel.external &&
      rel.kind == relationship_uri + "worksheet" &&
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
    guard sheets.length() < 256 else {
      @failure.reject("limit-exceeded", "Worksheet count exceeds budget")
    }
    let sheet = Sheet::read(
      rel.target,
      name,
      state,
      opc.xml(rel.target),
      strings,
      cell_styles.length(),
    )
    cell_count += sheet.cells.length()
    guard cell_count <= 100000 else {
      @failure.reject("limit-exceeded", "Workbook cell count exceeds budget")
    }
    let source = Tree::new(sheet.document)
    for child in source.children.get(source.root("worksheet").id).unwrap_or([]) {
      if ![
          "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
          "mergeCells", "sheetProtection", "pageMargins", "pageSetup", "printOptions",
          "headerFooter", "autoFilter", "dataValidations", "conditionalFormatting",
        ].contains(child.name) ||
        child.uri != spreadsheet_uri {
        diagnostics.push("unrendered:" + sheet.id + ":" + child.qualified)
      }
    }
    sheets.push(sheet)
    ids[id] = true
    names[name.to_lower()] = true
    paths[rel.target] = true
  }
  guard !sheets.is_empty() && sheets.any(sheet => sheet.state == "visible") else {
    @failure.reject("malformed-xlsx", "Workbook has no visible worksheet")
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
    date1904: tree
    .one(root.id, "workbookPr")
    .map(node => flag(node, "date1904"))
    .unwrap_or(false),
    sheets,
    selection: (active, { top: 1, left: 1, bottom: 1, right: 1, }),
    anchor: { row: 1, column: 1, },
    focus: { row: 1, column: 1, },
    grid: None,
    grid_id: 0,
    revision: 0,
    history: [],
    redo: [],
    history_bytes: 0,
    read_only,
    closed: false,
    diagnostics,
    calculation: None,
  }
  session.validate(session.sheets)
  session.calculation = Some(
    Calculation::build(session.sheets, None, [], session.date1904),
  ) catch {
    @failure.Failure(code~, message~, ..) if code == "unsupported-formula" ||
      code == "formula-syntax" ||
      code == "invalid-address" ||
      code == "circular-reference" => {
      session.read_only = message
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
fn Session::check_revision(
  self : Session,
  revision : Int,
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
) -> Int raise @failure.Failure {
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
  let range = Some(range.map(Range::parse).unwrap_or(self.selection.1))
  let cells : Array[Json] = []
  let selected : Array[Cell] = []
  for cell in current.cells.values() {
    if range.map(range => range.contains(cell.address)).unwrap_or(true) {
      selected.push(cell)
    }
  }
  guard selected.length() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Query exceeds 4096 cells; request a smaller rectangle",
    )
  }
  selected.sort_by((a, b) => {
    if a.address.row == b.address.row {
      a.address.column.compare(b.address.column)
    } else {
      a.address.row.compare(b.address.row)
    }
  })
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
  }
  // Formatting diagnostics keep a post-commit query from reporting a failed write.
  let conditional : ConditionalRules = self.conditional_rules(
    current,
    sheet_index,
    self.sheets,
    work,
  ) catch {
    @failure.Failure(code="limit-exceeded", message~, ..) =>
      { rules: [], reason: message, scales: Map([]), }
    error => raise error
  }
  let diagnostics = self.diagnostics.copy()
  if !conditional.reason.is_empty() {
    diagnostics.push(
      "conditional-format:" + current.id + ":" + conditional.reason,
    )
  }
  for cell in selected {
    let json = current.cell_json(
      cell.address,
      self.read_only,
      self.calculation.bind(calculation => {
        calculation.values.get((sheet_index, cell.address.name()))
      }),
    )
    if json is Object(fields) {
      let value = self.calculation
        .bind(calculation => {
          calculation.values.get((sheet_index, cell.address.name()))
        })
        .unwrap_or(cell.value)
      if !(cell.formula is Some(_) && value == Blank) {
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
        fields["display"] = Json(formatted(value, style.format, self.date1904))
        if !style.diagnostic.is_empty() {
          let diagnostic = "cell-style:" + current.id + ":" + style.diagnostic
          if !diagnostics.contains(diagnostic) {
            diagnostics.push(diagnostic)
          }
        }
      }
    }
    cells.push(json)
  }
  if range is Some(range) &&
    range.top == range.bottom &&
    range.left == range.right &&
    cells.is_empty() {
    cells.push(
      current.cell_json(
        { row: range.top, column: range.left, },
        self.read_only,
        None,
      ),
    )
  }
  {
    "revision": self.revision,
    "sheets": self.sheets.map(sheet => {
      let value : Json = {
        "id": sheet.id,
        "name": sheet.name,
        "state": sheet.state,
        "protected": sheet.locked,
      }
      value
    }),
    "mainPart": self.main,
    "fontKeys": self.styles
    .map(style => style.font)
    .iter()
    .fold(init=[], (keys : Array[String], key) => {
      if !keys.contains(key) {
        keys.push(key)
      }
      keys
    }),
    "sheet": current.id,
    "filter": self.filter_query(sheet_index),
    "cells": cells,
    "selection": {
      "sheet": self.selection.0,
      "range": self.selection.1,
      "address": self.selection.1.name(),
    },
    "canUndo": !self.history.is_empty(),
    "canRedo": !self.redo.is_empty(),
    "historyBytes": self.history_bytes,
    "readOnlyReason": self.read_only,
    "sheetEditReason": self.sheet_edit_reason(),
    "sheetRenameReason": self.sheet_rename_reason(),
    "frozen": {
      "rows": current.frozen.rows,
      "columns": current.frozen.columns,
      "readOnlyReason": self.freeze_reason(current),
    },
    "printSetup": self.print_setup_query(current),
    "dataValidation": self.validation_query(sheet_index, range.unwrap()),
    "conditionalFormats": self.conditional_query(current, conditional),
    "printRange": self.print_range_query(sheet_index),
    "headerFooter": self.header_footer_query(current),
    "dimensions": {
      "rowHeight": current.dimensions.rows
      .uniform(range.unwrap().top, range.unwrap().bottom)
      .map(value => Json(value))
      .unwrap_or(Json::null()),
      "columnWidth": current.dimensions.columns
      .uniform(range.unwrap().left, range.unwrap().right)
      .map(value => Json(value))
      .unwrap_or(Json::null()),
      "readOnlyReason": self.dimension_reason(current),
    },
    "formatting": self.formatting(current, range.unwrap()),
    "normalFont": self.normal_font,
    "merging": self.merging(current, range.unwrap()),
    "diagnostics": diagnostics,
    "date1904": self.date1904,
  }
}

///|
pub fn Session::select(
  self : Session,
  revision : Int,
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
  self.sheets.clear()
  self.parts.clear()
  self.removed.clear()
  self.strings.clear()
  self.history.clear()
  self.redo.clear()
  self.diagnostics.clear()
  self.history_bytes = 0
  self.calculation = None
  self.font_context = None
  self.grid = None
  self.opc.close()
}
