///|
fn Sheet::is_chart(self : Sheet) -> Bool {
  self.document.nodes()[0].name == "chartsheet"
}

///|
fn read_chart_sheet(
  id : String,
  name : String,
  state : String,
  tree : Tree,
) -> Sheet raise @failure.Failure {
  let root = tree.root("chartsheet")
  guard tree.children
    .get(root.id)
    .unwrap_or([])
    .all(node => {
      node.uri != spreadsheet_uri ||
      ![
        "sheetData", "cols", "dimension", "mergeCells", "sheetFormatPr", "autoFilter",
        "sortState", "tableParts", "conditionalFormatting", "dataValidations", "hyperlinks",
      ].contains(node.name)
    }) else {
    @failure.reject(
      "malformed-xlsx",
      "Chart sheets cannot contain worksheet cells",
      part=id,
    )
  }
  ignore(
    tree
    .one(root.id, "drawing")
    .unwrap_or_else(() => {
      @failure.reject(
        "malformed-xlsx",
        "Chart sheet requires a drawing",
        part=id,
      )
    }),
  )
  let locked = tree
    .one(root.id, "sheetProtection")
    .map(node => flag(node, "content") || flag(node, "objects"))
    .unwrap_or(false)
  {
    id,
    name,
    state,
    document: tree.document,
    cells: Map([]),
    rows: Map([]),
    merges: [],
    locked,
    protection_reason: "Chart sheet protection requires editing support",
    data: -1,
    dimensions: {
      rows: { default_size: 15, spans: [], limit: WorksheetRows, },
      columns: { default_size: 8, spans: [], limit: WorksheetColumns, },
      base_column_width: Some(8),
      automatic_rows: Map([]),
      automatic_columns: [],
    },
    row_styles: Map([]),
    column_styles: [],
    frozen: {
      rows: 0,
      columns: 0,
      edit_reason: "Chart sheets have no cell panes",
      layout_reason: "",
    },
    view: { grid_lines: false, headings: false, rtl: false, formulas: false, },
    sparklines: { items: [], reason: "", },
  }
}
