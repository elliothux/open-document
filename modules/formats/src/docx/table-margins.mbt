///|
fn WordTree::table_margins(
  self : WordTree,
  id : Int,
  inherited : @layout.CellMargins,
) -> @layout.CellMargins raise @failure.Failure {
  let node = self.nodes[id]
  guard node.attributes.is_empty() && node.text.trim().is_empty() else {
    @failure.reject("unsupported-layout", "Unknown cell margin properties")
  }
  let values : Map[String, Double] = Map([])
  for child in self.children[id] {
    let side = self.nodes[child]
    guard side.uri == word_uri &&
      ["top", "right", "bottom", "left", "start", "end"].contains(side.name) &&
      !values.contains(side.name) &&
      self.children[child].is_empty() &&
      side.text.trim().is_empty() &&
      side.attributes.all(a => {
        a.uri == word_uri && ["w", "type"].contains(a.name)
      }) else {
      @failure.reject("unsupported-layout", "Unknown or duplicate cell margin")
    }
    let kind = side.attribute("type", uri=word_uri).unwrap_or("dxa")
    let value : Double = if kind == "nil" {
      0.0
    } else {
      guard kind == "dxa" && self.number(id, side.name, "w") is Some(value) else {
        @failure.reject("unsupported-layout", "Cell margins require twips")
      }
      guard value >= 0 && value <= 288000 && value == value.floor() else {
        @failure.reject("invalid-table", "Invalid cell margin width")
      }
      value / 20
    }
    values[side.name] = value
  }
  {
    top: values.get("top").unwrap_or(inherited.top),
    right: values
    .get("end")
    .unwrap_or_else(() => values.get("right").unwrap_or(inherited.right)),
    bottom: values.get("bottom").unwrap_or(inherited.bottom),
    left: values
    .get("start")
    .unwrap_or_else(() => values.get("left").unwrap_or(inherited.left)),
  }
}

///|
fn Session::set_table_margins(
  self : Session,
  revision : Int,
  selection : Selection,
  value : @layout.CellMargins?,
  whole_table~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let markup = StringBuilder()
  let name = if whole_table { "tblCellMar" } else { "tcMar" }
  if value is Some(value) {
    markup.write_string("<od:\{name} xmlns:od=\"\{word_uri}\">")
    for
      (name, width) in [
        ("top", value.top),
        ("left", value.left),
        ("bottom", value.bottom),
        ("right", value.right),
      ] {
      guard width >= 0 && width <= 14400 && width * 20 == (width * 20).round() else {
        @failure.reject(
          "invalid-operation", "Cell margins require finite nonnegative integer twips",
        )
      }
      markup.write_string(
        "<od:\{name} od:w=\"\{(width * 20).round().to_int()}\" od:type=\"dxa\"/>",
      )
    }
    markup.write_string("</od:\{name}>")
  }
  self.change_table_property(
    revision,
    selection,
    name,
    None,
    markup=Some(markup.to_string()),
    whole_table~,
  )
}

///|
fn table_margin_defaults(
  tree : WordTree,
  styles : Styles,
  table : Int,
  diagnostics : Array[String],
) -> @layout.CellMargins raise @failure.Failure {
  let mut margins : @layout.CellMargins = {
    top: 0,
    right: 5.4,
    bottom: 0,
    left: 5.4,
  }
  if tree.child(table, "tblPr").bind(p => tree.value(p, "tblStyle"))
    is Some(key) &&
    styles.tree is Some(source) {
    for style in styles.chain(key, diagnostics) {
      if source.child(style, "tblPr").bind(p => source.child(p, "tblCellMar"))
        is Some(id) {
        margins = source.table_margins(id, margins)
      }
    }
  }
  if tree.child(table, "tblPr").bind(p => tree.child(p, "tblCellMar"))
    is Some(id) {
    margins = tree.table_margins(id, margins)
  }
  margins
}

///|
fn check_margin_layout(
  table : @layout.Table,
  page : @layout.PageSetup,
) -> Unit raise @failure.Failure {
  for r, row in table.rows {
    let mut start = 0
    for c, _ in row {
      let end = start + table.columnSpans[r][c]
      let width = table.widths[start:end].fold(init=0.0, (sum, width) => {
        sum + width
      })
      let margins = table.cell_insets(r, c)
      guard width > margins.left + margins.right else {
        @failure.reject(
          "invalid-operation", "Borders and margins leave no cell text width",
        )
      }
      start = end
    }
  }
  let mut first = 0
  while first < table.rows.length() {
    let mut last = first
    let mut r = first
    while r <= last {
      for span in table.rowSpans[r] {
        last = last.max(r + span - 1)
      }
      r += 1
    }
    let mut height = table.border_width(last + 1)
    for row in first..<=last {
      height += table.row_minimum_height(row)
    }
    guard height < page.height - page.top - page.bottom else {
      @failure.reject(
        "invalid-operation", "Cell margins exceed the page content height",
      )
    }
    first = last + 1
  }
}
