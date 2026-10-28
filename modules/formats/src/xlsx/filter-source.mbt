///|
fn filter_markup(state : AutoFilterState) -> String raise @failure.Failure {
  let out = StringBuilder()
  let columns = state.flags.keys().to_array()
  for column in state.settings.columns {
    if !columns.contains(column.column) {
      columns.push(column.column)
    }
  }
  columns.sort()
  for index in columns {
    if index < state.bounds.left || index > state.bounds.right {
      continue
    }
    let flags = state.flags
      .get(index)
      .unwrap_or([])
      .map(pair => " \{pair.0}=\"\{escaped_attribute(pair.1)}\"")
      .join("")
    out <+
      "<od:filterColumn xmlns:od=\"\{spreadsheet_uri}\" colId=\"\{index - state.bounds.left}\"\{flags}>"
    if state.settings.columns.iter().find_first(c => c.column == index)
      is Some(column) {
      match column.rule {
        Icon(set, id) => {
          let index = id.map(id => " iconId=\"\{id}\"").unwrap_or("")
          out <+ "<od:iconFilter iconSet=\"\{set}\"\{index}/>"
        }
        Relative(period, cache) => {
          let attributes = cache
            .map(bounds => " val=\"\{bounds.0}\" maxVal=\"\{bounds.1}\"")
            .unwrap_or("")
          out <+ "<od:dynamicFilter type=\"\{period}\"\{attributes}/>"
        }
        Calendar(unit, value) =>
          out <+
            "<od:dynamicFilter type=\"\{filter_calendar_type(unit, value)}\"/>"
        ColorStyle(index, cell_color~) =>
          out <+
            "<od:colorFilter dxfId=\"\{index}\" cellColor=\"\{if cell_color {1} else {0}}\"/>"
        Color(_, ..) =>
          @failure.reject(
            "invalid-operation", "Color filters require a differential style",
          )
        Dates(groups, values~, blank~) => {
          out <+ "<od:filters blank=\"\{if blank { 1 } else { 0 }}\">"
          for value in values {
            out <+ "<od:filter val=\"\{escaped_attribute(value)}\"/>"
          }
          for group in groups {
            out.write_string(filter_date_markup(group))
          }
          out <+ "</od:filters>"
        }
        Average(above~) =>
          out <+
            "<od:dynamicFilter type=\"\{if above { "aboveAverage" } else { "belowAverage" }}\"/>"
        Rank(value, top~, percent~) =>
          out <+
            "<od:top10 top=\"\{if top { 1 } else { 0 }}\" percent=\"\{if percent { 1 } else { 0 }}\" val=\"\{value}\"/>"
        Values(values, blank~) => {
          out <+ "<od:filters blank=\"\{if blank { 1 } else { 0 }}\">"
          for value in values {
            out <+ "<od:filter val=\"\{escaped_attribute(value)}\"/>"
          }
          out <+ "</od:filters>"
        }
        Custom(conditions, all~) => {
          out <+ "<od:customFilters and=\"\{if all { 1 } else { 0 }}\">"
          for condition in conditions {
            out <+
              "<od:customFilter operator=\"\{condition.operator}\" val=\"\{escaped_attribute(condition.value)}\"/>"
          }
          out <+ "</od:customFilters>"
        }
      }
    }
    out <+ "</od:filterColumn>"
  }
  if state.sort is Some(sort) {
    out.write_string(sort.source)
  }
  let manual = state.manual.map(row => row.to_string()).join(" ")
  let filtered = state.filtered.map(row => row.to_string()).join(" ")
  out <+
    "<od:extLst xmlns:od=\"\{spreadsheet_uri}\"><od:ext uri=\"\{filter_state_uri}\"><f:visibility xmlns:f=\"\{filter_state_uri}\" manual=\"\{manual}\" filtered=\"\{filtered}\"/></od:ext></od:extLst>"
  out.to_string()
}

///|
fn filter_source_changes(
  tree : Tree,
  root : @xml.Node,
  next : AutoFilterState?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let existing = tree.one(root.id, "autoFilter")
  let changes : Array[@xml.SourceChange] = []
  if next is Some(state) {
    let content = filter_markup(state)
    if existing is Some(node) {
      changes.append(metadata_changes(node, [("ref", state.bounds.name())]))
      changes.push(
        if node.empty {
          insertion(node, content)
        } else {
          {
            node: node.id,
            offset: node.opening_end - node.start,
            length: node.closing_start - node.opening_end,
            xml: content,
          }
        },
      )
    } else {
      let markup = "<od:autoFilter xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{state.bounds.name()}\">\{content}</od:autoFilter>"
      let after = if root.name == "table" {
        ["sortState", "tableColumns", "tableStyleInfo", "extLst"]
      } else {
        [
          "sortState", "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr",
          "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions",
          "pageMargins", "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "customProperties",
          "cellWatches", "ignoredErrors", "smartTags", "drawing", "legacyDrawing",
          "legacyDrawingHF", "picture", "oleObjects", "controls", "webPublishItems",
          "tableParts", "extLst",
        ]
      }
      changes.push(
        if tree.children
          .get(root.id)
          .unwrap_or([])
          .iter()
          .find_first(n => after.contains(n.name))
          is Some(node) {
          {
            node: root.id,
            offset: node.start - root.start,
            length: 0,
            xml: markup,
          }
        } else {
          insertion(root, markup)
        },
      )
    }
  } else if existing is Some(node) {
    changes.push(sheet_node_removal(tree, node))
  }
  changes
}

///|
fn filter_write(
  sheet : Sheet,
  next : AutoFilterState?,
  hidden : Map[Int32, Bool],
  active~ : Bool = next
    .map(state => !state.settings.columns.is_empty())
    .unwrap_or(false),
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let changes = filter_source_changes(tree, root, next)
  if tree.one(root.id, "sheetPr") is Some(properties) {
    changes.append(
      metadata_changes(properties, [
        ("filterMode", if active { "1" } else { "0" }),
      ]),
    )
  } else if active {
    changes.push({
      node: root.id,
      offset: root.opening_end - root.start,
      length: 0,
      xml: "<od:sheetPr xmlns:od=\"\{spreadsheet_uri}\" filterMode=\"1\"/>",
    })
  }
  let rows : Map[Int32, Array[(String, String)]] = Map([])
  for row, value in hidden {
    if (sheet.dimensions.rows.size(row) == 0) != value {
      rows[row] = [("hidden", if value { "1" } else { "0" })]
    }
  }
  changes.append(sheet.row_metadata_changes(tree, rows))
  sheet.document.edit_source(join_insertions(changes))
}
