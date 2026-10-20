///|
fn sparkline_markup(
  items : Array[Sparkline],
  name : String,
) -> String raise @failure.Failure {
  let groups = StringBuilder()
  for item in items {
    let formula = item.source
      .map(source => {
        "'" +
        item.owner.unwrap_or(name).replace_all(old="'", new="''") +
        "'!" +
        source.name()
      })
      .unwrap_or("#REF!")
    let kind = if item.kind == "winLoss" { "stacked" } else { item.kind }
    groups.write_string(
      "<s:sparklineGroup type=\"\{kind}\" lineWeight=\"0.75\" displayEmptyCellsAs=\"gap\" negative=\"1\" displayHidden=\"0\"><s:colorSeries rgb=\"FF4472C4\"/><s:colorNegative rgb=\"FFED7D31\"/><s:sparklines><s:sparkline><m:f>\{@xml.escape_text(formula)}</m:f><m:sqref>\{item.cell.name()}</m:sqref></s:sparkline></s:sparklines></s:sparklineGroup>",
    )
  }
  "<od:ext xmlns:od=\"\{spreadsheet_uri}\" uri=\"\{sparkline_extension_uri}\"><s:sparklineGroups xmlns:s=\"\{sparkline_uri}\" xmlns:m=\"\{sparkline_formula_uri}\">\{groups.to_string()}</s:sparklineGroups></od:ext>"
}

///|
fn Session::set_sparkline(
  self : Session,
  id : String,
  cell : String,
  source : String?,
  kind : String,
) -> Json raise @failure.Failure {
  guard ["line", "column", "winLoss"].contains(kind) else {
    @failure.reject("invalid-operation", "Unknown sparkline type")
  }
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let address = Address::parse(cell)
  guard self.read_only.is_empty() &&
    !sheet.locked &&
    sparkline_reason(sheet, self.sheets).is_empty() else {
    @failure.reject(
      "protected-content", "Protected or unsupported sparkline content",
    )
  }
  guard !sheet.merges.any(range => range.contains(address)) else {
    @failure.reject(
      "protected-content", "Sparkline locations require an unmerged cell",
    )
  }
  let items = sheet.sparklines.items.filter(item => item.cell != address)
  if source is Some(source) {
    let (owner, range) = sparkline_source(source, sheet.name)
    let owner = owner.map(name => {
      guard sparkline_sheet_index(self.sheets, name) is Some(index) else {
        @failure.reject(
          "protected-content", "Sparkline source worksheet is missing",
        )
      }
      self.sheets[index].name
    })
    guard items.length() < 256 else {
      @failure.reject("limit-exceeded", "Sparkline count exceeds 256")
    }
    items.push({ cell: address, source: range, owner, kind, })
  }
  items.sort_by((a, b) => {
    if a.cell.row == b.cell.row {
      a.cell.column.compare(b.cell.column)
    } else {
      a.cell.row.compare(b.cell.row)
    }
  })
  let previous = sheet.sparklines.items.copy()
  previous.sort_by((a, b) => {
    if a.cell.row == b.cell.row {
      a.cell.column.compare(b.cell.column)
    } else {
      a.cell.row.compare(b.cell.row)
    }
  })
  if previous == items {
    return self.query()
  }
  self.commit_view(index, sheet.sparkline_changes(items))
}

///|
fn Sheet::sparkline_changes(
  self : Sheet,
  items : Array[Sparkline],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if items == self.sparklines.items {
    return []
  }
  guard self.sparklines.reason.is_empty() else {
    @failure.reject("protected-content", self.sparklines.reason)
  }
  let tree = Tree::new(self.document)
  let root = tree.root("worksheet")
  let extensions = tree.one(root.id, "extLst")
  let owned = extensions
    .map(n => {
      tree.children
      .get(n.id)
      .unwrap_or([])
      .filter(n => n.attribute("uri") == Some(sparkline_extension_uri))
    })
    .unwrap_or([])
  guard owned.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate sparkline extensions")
  }
  let markup = if items.is_empty() {
    ""
  } else {
    sparkline_markup(items, self.name)
  }
  let changes : Array[@xml.SourceChange] = if items.is_empty() &&
    extensions is Some(container) &&
    tree.children.get(container.id).unwrap_or([]).length() == 1 {
    [sheet_node_removal(tree, container)]
  } else if owned is [extension] {
    [{ ..sheet_node_removal(tree, extension), xml: markup, }]
  } else if extensions is Some(extensions) {
    [insertion(extensions, markup)]
  } else {
    [
      insertion(
        root,
        "<od:extLst xmlns:od=\"\{spreadsheet_uri}\">\{markup}</od:extLst>",
      ),
    ]
  }
  changes
}
