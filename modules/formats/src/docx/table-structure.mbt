///|
pub(all) enum TableEdit {
  RowBefore
  RowAfter
  DeleteRow
  ColumnBefore
  ColumnAfter
  DeleteColumn
  MergeCells(Int, Int)
  UnmergeCell
  SplitCell(Int, Int)
  SplitTable
  PasteCells(String)
  PasteCellFragment(String)
  AutoFit(String)
  TableWidth(Double)
  ColumnWidth(Int, Double)
  RowHeight(Double, String)
  CellFill(String?)
  CellVerticalAlign(String?)
  CellMargins(@layout.CellMargins?)
  TableMargins(@layout.CellMargins?)
  TableAlign(String)
  HeaderRows(Int)
  RowSplit(Bool)
  TableBorders(Map[String, @layout.BorderStyle?])
  CellBorders(Map[String, @layout.BorderStyle?])
}

///|
priv struct TableChanges {
  items : Array[@xml.SourceChange]
  mut bytes : Int
  limit : Int
}

///|
fn TableChanges::push(
  self : TableChanges,
  change : @xml.SourceChange,
) -> Unit raise @failure.Failure {
  guard change.xml.length() <= self.limit - self.bytes else {
    @failure.reject("limit-exceeded", "Table source exceeds history budget")
  }
  self.bytes += change.xml.length()
  self.items.push(change)
}

///|
fn WordTree::table_children(
  self : WordTree,
  parent : Int,
  name : String,
) -> Array[Int] {
  self.children[parent].filter(id => {
    self.nodes[id].uri == word_uri && self.nodes[id].name == name
  })
}

///|
fn table_position(paragraph : Int) -> Position {
  {
    paragraph,
    offset: 0,
    affinity: "after",
    bidiLevel: None,
    frameStart: None,
  }
}

///|
fn WordTree::table_cell_properties(
  self : WordTree,
  document : @xml.Document,
  cell : Int,
  width : Int,
) -> String raise @failure.Failure {
  let fields = ["<od:tcW od:type=\"dxa\" od:w=\"\{width}\"/>"]
  if self.child(cell, "tcPr") is Some(props) {
    let node = self.nodes[props]
    let source = document.source()[node.start:node.end]
    guard node.attributes.is_empty() &&
      node.text.trim().is_empty() &&
      !source.contains("<!--") &&
      !source.contains("<?") else {
      @failure.reject("protected-content", "Unknown cell property markup")
    }
    for id in self.children[props] {
      if !["tcW", "gridSpan", "vMerge"].contains(self.nodes[id].name) {
        fields.push(self.standalone_markup(document, id))
      }
    }
  }
  "<od:tcPr xmlns:od=\"\{word_uri}\">\{fields.join("")}</od:tcPr>"
}

///|
fn Session::empty_table_cell(
  self : Session,
  tree : WordTree,
  cell : Int,
  width : Int,
) -> String raise @failure.Failure {
  let p = tree.child(cell, "p").unwrap()
  tree.check_editable_paragraph(p, part=self.main)
  tree.check_structure_paragraph(p)
  let original = self.document()
  let paragraph = formatted_properties(
    tree,
    original,
    p,
    "pPr",
    ParagraphFormat::new(pageBreakBefore=Set(false)).properties(),
  )
  let run = tree
    .child(p, "r")
    .bind(id => tree.child(id, "rPr"))
    .map(id => tree.standalone_markup(original, id))
    .unwrap_or(tree.empty_run_properties(original, p))
  let bindings = tree.namespace_bindings(p)
  bindings["od"] = word_uri
  let out = StringBuilder()
  out.write_string("<od:tc")
  for prefix, uri in bindings {
    let name = if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }
    out.write_string(" \{name}=\"\{property_attribute(uri)}\"")
  }
  let properties = tree.table_cell_properties(self.document(), cell, width)
  out.write_string(
    ">\{properties}<od:p>\{paragraph}<od:r>\{run}<od:t/></od:r></od:p></od:tc>",
  )
  out.to_string()
}

///|
fn table_remove(tree : WordTree, id : Int) -> @xml.SourceChange {
  let node = tree.nodes[id]
  {
    node: node.parent,
    offset: node.start - tree.nodes[node.parent].start,
    length: node.end - node.start,
    xml: "",
  }
}

///|
/// Edits supported selected cells, rows or columns in a single source history.
pub fn Session::edit_table(
  self : Session,
  revision : Int,
  selection : Selection,
  change : TableEdit,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  match change {
    PasteCellFragment(fragment) =>
      return self.paste_table_fragment(
        revision, selection, fragment, probe, profile, images,
      )
    PasteCells(text) =>
      return self.paste_table_cells(
        revision, selection, text, probe, profile, images,
      )
    ColumnBefore | ColumnAfter =>
      return self.insert_table_column(
        selection,
        change is ColumnBefore,
        probe,
        profile,
        images,
      )
    RowBefore | RowAfter | DeleteRow =>
      return self.edit_table_rows(
        revision,
        selection,
        change,
        probe~,
        profile~,
        images~,
      )
    AutoFit(mode) =>
      return self.fit_table(revision, selection, mode, probe, profile, images)
    TableBorders(value) | CellBorders(value) =>
      return self.set_table_borders(
        revision,
        selection,
        value,
        whole_table=change is TableBorders(_),
      )
    HeaderRows(count) =>
      return self.change_table_property(
        revision,
        selection,
        "tblHeader",
        None,
        header_rows=Some(count),
      )
    RowSplit(value) =>
      return self.change_table_property(
        revision,
        selection,
        "cantSplit",
        Some(Map([("val", Some(if value { "0" } else { "1" }))])),
        whole_row=true,
      )
    MergeCells(rows, columns) =>
      return self.merge_table_cells(revision, selection, rows, columns)
    UnmergeCell =>
      return self.unmerge_table_cells(
        revision, selection, probe, profile, images,
      )
    SplitCell(rows, columns) =>
      return self.split_table_cell(
        revision, selection, rows, columns, probe, profile, images,
      )
    SplitTable => return self.split_table(revision, selection)
    TableWidth(value) =>
      return self.size_table(
        revision,
        selection,
        value,
        width=true,
        probe?,
        profile~,
        images?,
      )
    ColumnWidth(column, value) =>
      return self.size_table(
        revision,
        selection,
        value,
        width=true,
        column=Some(column),
        probe?,
        profile~,
        images?,
      )
    RowHeight(value, rule) =>
      return self.size_table(
        revision,
        selection,
        value,
        width=false,
        rule~,
        probe?,
        profile~,
        images?,
      )
    CellFill(color) => return self.fill_table_cell(revision, selection, color)
    CellMargins(value) =>
      return self.set_table_margins(revision, selection, value)
    TableMargins(value) =>
      return self.set_table_margins(
        revision,
        selection,
        value,
        whole_table=true,
      )
    TableAlign(value) => {
      guard ["left", "center", "right"].contains(value) else {
        @failure.reject("invalid-operation", "Invalid table alignment")
      }
      return self.change_table_property(
        revision,
        selection,
        "jc",
        Some(Map([("val", Some(value))])),
        whole_table=true,
      )
    }
    CellVerticalAlign(value) => {
      if value is Some(align) && !["top", "center", "bottom"].contains(align) {
        @failure.reject("invalid-operation", "Invalid cell vertical alignment")
      }
      return self.change_table_property(
        revision,
        selection,
        "vAlign",
        value.map(align => Map([("val", Some(align))])),
      )
    }
    DeleteColumn => self.delete_table_column(selection, probe, profile, images)
  }
}
