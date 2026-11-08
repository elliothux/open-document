///|
pub(all) struct ViewSettings {
  grid_lines : Bool
  headings : Bool
  rtl : Bool
  formulas : Bool
} derive(Eq)

///|
pub extend ViewSettings with Eq::{equal, not_equal}

///|
fn ViewSettings::header_size(self : ViewSettings) -> (Double, Double) {
  if self.headings {
    (36, 18)
  } else {
    (0, 0)
  }
}

///|
fn read_view(tree : Tree) -> ViewSettings raise @failure.Failure {
  fn shown(view : @xml.Node, name : String) -> Bool raise @failure.Failure {
    match view.attribute(name) {
      None | Some("1" | "true") => true
      Some("0" | "false") => false
      _ =>
        @failure.reject(
          "malformed-xlsx",
          "Invalid worksheet view flag: " + name,
        )
    }
  }
  match primary_view(tree) {
    None => { grid_lines: true, headings: true, rtl: false, formulas: false, }
    Some(view) =>
      {
        grid_lines: shown(view, "showGridLines"),
        headings: shown(view, "showRowColHeaders"),
        rtl: if view.attribute("rightToLeft") is None {
          false
        } else {
          shown(view, "rightToLeft")
        },
        formulas: if view.attribute("showFormulas") is None {
          false
        } else {
          shown(view, "showFormulas")
        },
      }
  }
}

///|
fn insert_primary_view(
  tree : Tree,
  view : String,
) -> @xml.SourceChange raise @failure.Failure {
  let root = tree.root("worksheet")
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

///|
fn Session::commit_view(
  self : Session,
  index : Int32,
  changes : Array[@xml.SourceChange],
) -> Json raise @failure.Failure {
  let current = self.sheets[index]
  let (document, edit) = current.document.edit_source(changes)
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

///|
fn Session::set_view(
  self : Session,
  sheet : String,
  settings : ViewSettings,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.freeze_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if current.view == settings {
    return self.query()
  }
  let tree = Tree::new(current.document)
  let changes = if primary_view(tree) is Some(view) {
    let attributes : Array[(String, String)] = []
    if current.view.grid_lines != settings.grid_lines {
      attributes.push(
        ("showGridLines", if settings.grid_lines { "1" } else { "0" }),
      )
    }
    if current.view.headings != settings.headings {
      attributes.push(
        ("showRowColHeaders", if settings.headings { "1" } else { "0" }),
      )
    }
    if current.view.rtl != settings.rtl {
      attributes.push(("rightToLeft", if settings.rtl { "1" } else { "0" }))
    }
    if current.view.formulas != settings.formulas {
      attributes.push(
        ("showFormulas", if settings.formulas { "1" } else { "0" }),
      )
    }
    metadata_changes(view, attributes)
  } else {
    [
      insert_primary_view(
        tree,
        "<od:sheetView xmlns:od=\"\{spreadsheet_uri}\" workbookViewId=\"0\" showGridLines=\"\{if settings.grid_lines { "1" } else { "0" }}\" showRowColHeaders=\"\{if settings.headings { "1" } else { "0" }}\" rightToLeft=\"\{if settings.rtl { "1" } else { "0" }}\" showFormulas=\"\{if settings.formulas { "1" } else { "0" }}\"/>",
      ),
    ]
  }
  self.commit_view(index, changes)
}

///|
fn neutral_mac_page_layout(tree : Tree, list : @xml.Node) -> Bool {
  list.uri == spreadsheet_uri &&
  list.name == "extLst" &&
  list.attributes.is_empty() &&
  list.text.trim().is_empty() &&
  tree.children.get(list.id).unwrap_or([]) is [extension] &&
  extension.uri == spreadsheet_uri &&
  extension.name == "ext" &&
  extension.attributes.length() == 1 &&
  extension.attribute("uri").map(value => value.to_upper()) ==
  Some("{64002731-A6B0-56B0-2670-7721B7C09600}") &&
  extension.text.trim().is_empty() &&
  tree.children.get(extension.id).unwrap_or([]) is [view] &&
  view.uri == "http://schemas.microsoft.com/office/mac/excel/2008/main" &&
  view.name == "PLV" &&
  view.attributes.length() == 3 &&
  ["Mode", "OnePage", "WScale"].all(name => view.attribute(name) == Some("0")) &&
  view.text.trim().is_empty() &&
  tree.children.get(view.id).unwrap_or([]).is_empty()
}
