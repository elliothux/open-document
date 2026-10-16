///|
priv struct Frozen {
  rows : Int
  columns : Int
  edit_reason : String
  layout_reason : String
}

///|
fn primary_view(tree : Tree) -> @xml.Node? raise @failure.Failure {
  let views = tree
    .one(tree.root("worksheet").id, "sheetViews")
    .map(views => {
      tree
      .all(views.id, "sheetView")
      .filter(view => view.attribute("workbookViewId").unwrap_or("0") == "0")
    })
    .unwrap_or([])
  guard views.length() <= 1 else {
    @failure.reject("malformed-xlsx", "Duplicate primary worksheet view")
  }
  views.get(0)
}

///|
fn read_frozen(tree : Tree) -> Frozen raise @failure.Failure {
  let empty : Frozen = {
    rows: 0,
    columns: 0,
    edit_reason: "",
    layout_reason: "",
  }
  guard primary_view(tree) is Some(view) else { return empty }
  let mut reason = ""
  if view.attributes.any(attribute => {
      !attribute.uri.is_empty() ||
      ![
        "windowProtection", "showFormulas", "showGridLines", "showRowColHeaders",
        "showZeros", "rightToLeft", "tabSelected", "showRuler", "showOutlineSymbols",
        "defaultGridColor", "showWhiteSpace", "view", "topLeftCell", "colorId", "zoomScale",
        "zoomScaleNormal", "zoomScaleSheetLayoutView", "zoomScalePageLayoutView",
        "workbookViewId",
      ].contains(attribute.name)
    }) ||
    !view.text.trim().is_empty() {
    reason = "Unknown view metadata requires pane editing support"
  }
  if flag(view, "windowProtection") ||
    flag(view, "rightToLeft") ||
    view.attribute("view").unwrap_or("normal") != "normal" {
    reason = "Frozen panes require an unprotected normal left-to-right view"
  }
  for child in tree.children.get(view.id).unwrap_or([]) {
    let allowed = if child.name == "pane" {
      ["xSplit", "ySplit", "topLeftCell", "activePane", "state"]
    } else if child.name == "selection" {
      ["pane", "activeCell", "activeCellId", "sqref"]
    } else {
      []
    }
    if child.uri != spreadsheet_uri ||
      allowed.is_empty() ||
      child.attributes.any(attribute => {
        !attribute.uri.is_empty() || !allowed.contains(attribute.name)
      }) ||
      !tree.children.get(child.id).unwrap_or([]).is_empty() ||
      !child.text.trim().is_empty() {
      reason = "Unknown view metadata requires pane editing support"
    }
  }
  guard tree.one(view.id, "pane") is Some(pane) else {
    return { ..empty, edit_reason: reason, }
  }
  guard ["frozen", "frozenSplit"].contains(
    pane.attribute("state").unwrap_or("split"),
  ) else {
    return {
      ..empty,
      edit_reason: "Split panes require view support",
      layout_reason: "Split panes require view support",
    }
  }
  let rows = number(pane.attribute("ySplit").unwrap_or("0"))
  let columns = number(pane.attribute("xSplit").unwrap_or("0"))
  guard rows >= 0 &&
    rows < 1048576 &&
    rows == rows.floor() &&
    columns >= 0 &&
    columns < 16384 &&
    columns == columns.floor() else {
    @failure.reject("malformed-xlsx", "Invalid frozen row or column count")
  }
  {
    rows: rows.to_int(),
    columns: columns.to_int(),
    edit_reason: reason,
    layout_reason: if flag(view, "rightToLeft") {
      "Right-to-left frozen panes require layout support"
    } else {
      ""
    },
  }
}

///|
fn Session::freeze_reason(self : Session, sheet : Sheet) -> String {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  if !sheet.frozen.edit_reason.is_empty() {
    return sheet.frozen.edit_reason
  }
  try {
    let tree = Tree::new(self.workbook)
    if tree
      .one(tree.root("workbook").id, "workbookProtection")
      .map(node => flag(node, "lockWindows"))
      .unwrap_or(false) {
      "Workbook windows are protected"
    } else {
      ""
    }
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::freeze(
  self : Session,
  sheet : String,
  rows : Int,
  columns : Int,
) -> Json raise @failure.Failure {
  guard rows >= 0 && rows < 1048576 && columns >= 0 && columns < 16384 else {
    @failure.reject("invalid-operation", "Invalid frozen row or column count")
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.freeze_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if current.frozen.rows == rows && current.frozen.columns == columns {
    return self.query()
  }
  let tree = Tree::new(current.document)
  let root = tree.root("worksheet")
  let previous = primary_view(tree).bind(view => {
    let selections = tree.all(view.id, "selection")
    let active = tree
      .one(view.id, "pane")
      .bind(pane => pane.attribute("activePane"))
      .unwrap_or("topLeft")
    let selected = selections
      .iter()
      .find_first(selection => {
        selection.attribute("pane").unwrap_or("topLeft") == active
      })
    if selected is Some(_) {
      selected
    } else {
      selections.get(0)
    }
  })
  let range = if self.selection.0 == sheet {
    self.selection.1.name()
  } else {
    previous.bind(node => node.attribute("sqref")).unwrap_or("A1")
  }
  let focus = if self.selection.0 == sheet {
    self.focus
  } else {
    Address::parse(
      previous.bind(node => node.attribute("activeCell")).unwrap_or("A1"),
    )
  }
  let pane = if rows > 0 && columns > 0 {
    if focus.row <= rows {
      if focus.column <= columns {
        "topLeft"
      } else {
        "topRight"
      }
    } else if focus.column <= columns {
      "bottomLeft"
    } else {
      "bottomRight"
    }
  } else if rows > 0 && focus.row > rows {
    "bottomLeft"
  } else if columns > 0 && focus.column > columns {
    "topRight"
  } else {
    "topLeft"
  }
  let origin : Address = { row: rows + 1, column: columns + 1, }
  let markup = (if rows > 0 || columns > 0 {
      "<od:pane xmlns:od=\"\{spreadsheet_uri}\" state=\"frozen\" xSplit=\"\{columns}\" ySplit=\"\{rows}\" topLeftCell=\"\{origin.name()}\" activePane=\"\{pane}\"/>"
    } else {
      ""
    }) +
    "<od:selection xmlns:od=\"\{spreadsheet_uri}\" pane=\"\{pane}\" activeCell=\"\{focus.name()}\" sqref=\"\{escaped_attribute(range)}\"/>"
  let change : @xml.SourceChange = if primary_view(tree) is Some(view) {
    if view.empty {
      insertion(view, markup)
    } else {
      let gaps = StringBuilder()
      let mut cursor = view.opening_end
      for child in tree.children.get(view.id).unwrap_or([]) {
        gaps.write_view(current.document.source()[cursor:child.start])
        cursor = child.end
      }
      gaps.write_view(current.document.source()[cursor:view.closing_start])
      {
        node: view.id,
        offset: view.opening_end - view.start,
        length: view.closing_start - view.opening_end,
        xml: markup + gaps.to_string(),
      }
    }
  } else {
    let view = "<od:sheetView xmlns:od=\"\{spreadsheet_uri}\" workbookViewId=\"0\">\{markup}</od:sheetView>"
    if tree.one(root.id, "sheetViews") is Some(views) {
      insertion(views, view)
    } else {
      let next = tree.children[root.id]
        .iter()
        .find_first(node => !["sheetPr", "dimension"].contains(node.name))
        .unwrap()
      {
        node: root.id,
        offset: next.start - root.start,
        length: 0,
        xml: "<od:sheetViews xmlns:od=\"\{spreadsheet_uri}\">\{view}</od:sheetViews>",
      }
    }
  }
  let (document, edit) = current.document.edit_source([change])
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(current.id, edit)],
    self.selection,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
