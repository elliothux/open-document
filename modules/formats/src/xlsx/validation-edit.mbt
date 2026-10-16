///|
fn Session::set_validation(
  self : Session,
  id : String,
  range : String,
  settings : DataValidation?,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let target = Range::parse(range)
  let reason = self.validation_reason(sheet, target)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let anchor : Address = { row: target.top, column: target.left, }
  if settings is Some(settings) {
    settings.check_metadata()
    if settings.kind != "none" {
      let work = FormulaWork::{
        remaining: 1048576,
        date1904: self.date1904,
        origin: anchor,
      }
      let first = rule_expression(
        settings.formula1,
        anchor,
        anchor,
        self.sheets,
        index,
        work,
      )
      if settings.kind == "list" {
        ignore(
          validation_values(
            first,
            self.sheets,
            index,
            self.calculation.unwrap(),
            work,
          ),
        )
      }
      if !settings.formula2.is_empty() {
        ignore(
          rule_expression(
            settings.formula2,
            anchor,
            anchor,
            self.sheets,
            index,
            work,
          ),
        )
      }
    }
  }
  let (current, mixed) = sheet.validation_at(target)
  if !mixed && current == settings {
    return self.query()
  }
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let container = tree.one(root.id, "dataValidations")
  let changes = []
  let nodes = validation_nodes(tree)
  let mut count = nodes.length()
  for node in nodes {
    let (remove, edits) = clear_rule_changes(tree, node, target)
    if remove {
      changes.push(sheet_node_removal(tree, node))
      count -= 1
    } else {
      changes.append(edits)
    }
  }
  if settings is Some(settings) {
    count += 1
    guard count <= 4096 else {
      @failure.reject(
        "limit-exceeded", "Data validation rule count exceeds budget",
      )
    }
    let markup = settings.markup(target)
    if container is Some(container) {
      changes.push(insertion(container, markup))
    } else {
      let markup = "<od:dataValidations xmlns:od=\"\{spreadsheet_uri}\" count=\"1\">\{markup}</od:dataValidations>"
      let next = tree.children
        .get(root.id)
        .unwrap_or([])
        .iter()
        .find_first(n => {
          [
            "hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter",
            "rowBreaks", "colBreaks", "customProperties", "cellWatches", "ignoredErrors",
            "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF", "picture",
            "oleObjects", "controls", "webPublishItems", "tableParts", "extLst",
          ].contains(n.name)
        })
      changes.push(
        if next is Some(next) {
          {
            node: root.id,
            offset: next.start - root.start,
            length: 0,
            xml: markup,
          }
        } else {
          insertion(root, markup)
        },
      )
    }
  }
  if container is Some(container) {
    if count == 0 {
      changes.clear()
      changes.push(sheet_node_removal(tree, container))
    } else {
      changes.append(
        metadata_changes(container, [("count", count.to_string())]),
      )
    }
  }
  if changes.is_empty() {
    return self.query()
  }
  let (document, edit) = sheet.document.edit_source(join_insertions(changes))
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    id,
    sheet.name,
    sheet.state,
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
    [(id, edit)],
    self.selection,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
