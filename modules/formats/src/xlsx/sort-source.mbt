///|
fn Sheet::sorted_cell(
  self : Sheet,
  tree : Tree,
  from : Address,
  to : Address,
  value : CellContent,
) -> String raise @failure.Failure {
  let style = self.style_at(from)
  guard self.cells.get(from.name()) is Some(cell) else {
    return "<od:c xmlns:od=\"\{spreadsheet_uri}\" r=\"\{to.name()}\" s=\"\{style}\"/>"
  }
  let node = tree.nodes[cell.node]
  guard node.attributes.all(a => {
      a.uri.is_empty() && ["r", "s", "t"].contains(a.name)
    }) &&
    tree.children
    .get(node.id)
    .unwrap_or([])
    .all(n => {
      n.uri == spreadsheet_uri && ["v", "f", "is", "extLst"].contains(n.name)
    }) &&
    tree
    .one(node.id, "extLst")
    .map(n => {
      tree.children.get(n.id).unwrap_or([]).is_empty() &&
      n.text.trim().is_empty()
    })
    .unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Unknown cell metadata requires sorting ownership support",
    )
  }
  let changes = metadata_changes(node, [
    ("r", to.name()),
    ("s", style.to_string()),
  ])
  if value.formula is Some(formula) {
    let f = tree.one(node.id, "f").unwrap()
    guard f.attributes.all(a => {
        a.uri.is_empty() && ["t", "si", "ref"].contains(a.name)
      }) &&
      tree.children.get(f.id).unwrap_or([]).is_empty() &&
      !self.document.source()[f.opening_end:f.closing_start].contains("<") else {
      @failure.reject(
        "protected-content", "Opaque formula markup requires sorting support",
      )
    }
    let bindings = f.namespaces
      .map(binding => {
        " \{if binding.0.is_empty() { "xmlns" } else { "xmlns:" + binding.0 }}=\"\{escaped_attribute(binding.1)}\""
      })
      .join("")
    changes.push({
      node: node.id,
      offset: f.start - node.start,
      length: f.end - f.start,
      xml: "<\{f.qualified}\{bindings}>\{@xml.escape_text(formula)}</\{f.qualified}>",
    })
  }
  // Cell fragments cross row namespace scopes; make inherited bindings local.
  let namespaces : Map[String, String] = Map([])
  let mut parent = node.id
  while parent >= 0 {
    for (prefix, uri) in tree.nodes[parent].namespaces {
      if !namespaces.contains(prefix) {
        namespaces[prefix] = uri
      }
    }
    parent = tree.nodes[parent].parent
  }
  let bindings = StringBuilder()
  for prefix, uri in namespaces {
    if !node.namespaces.any(binding => binding.0 == prefix) {
      bindings <+
        " \{if prefix.is_empty() { "xmlns" } else { "xmlns:" + prefix }}=\"\{escaped_attribute(uri)}\""
    }
  }
  if !bindings.is_empty() {
    changes.push({
      node: node.id,
      offset: node.qualified.length() + 1,
      length: 0,
      xml: bindings.to_string(),
    })
  }
  let patches = changes.map(change => {
    (
      tree.nodes[change.node].start + change.offset - node.start,
      change.length,
      change.xml,
    )
  })
  patches.sort_by((a, b) => a.0.compare(b.0))
  let out = StringBuilder()
  let source = self.document.source()[node.start:node.end]
  let mut cursor = 0
  for (offset, length, xml) in patches {
    guard offset >= cursor else {
      @failure.reject(
        "invalid-operation", "Overlapping sorted cell source changes",
      )
    }
    out.write_view(source[cursor:offset])
    out.write_string(xml)
    cursor = offset + length
  }
  out.write_view(source[cursor:])
  out.to_string()
}

///|
fn Session::sort_resources(
  self : Session,
  sheet : Sheet,
  filter~ : Bool = false,
  tables~ : Bool = false,
  sparklines~ : Bool = false,
) -> Unit raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  self.check_sort_metadata(tree)
  let reason = sparkline_reason(sheet, self.sheets)
  if sparklines && !reason.is_empty() {
    @failure.reject("protected-content", reason)
  }
  for node in tree.children.get(tree.root("worksheet").id).unwrap_or([]) {
    if sparklines && sparkline_extension(tree, node) {
      continue
    }
    guard node.uri == spreadsheet_uri &&
      !["drawing", "legacyDrawingHF"].contains(node.name) &&
      (filter || node.name != "autoFilter") &&
      !(["extLst", "pivotTableParts"].contains(node.name) &&
      !tree.children.get(node.id).unwrap_or([]).is_empty()) &&
      (
        tables ||
        node.name != "tableParts" ||
        tree.children.get(node.id).unwrap_or([]).is_empty()
      ) else {
      @failure.reject(
        "protected-content", "Worksheet resources require sorting ownership support",
      )
    }
  }
  for link in self.relationships() {
    if link.owner != sheet.id {
      continue
    }
    guard (tables && link.kind == relationship_uri + "table") ||
      link.kind == thread_relationship_uri + "threadedComment" ||
      ["hyperlink", "printerSettings", "comments", "vmlDrawing"].any(kind => {
        link.kind == relationship_uri + kind
      }) else {
      @failure.reject(
        "protected-content", "Worksheet relationships require sorting ownership support",
      )
    }
  }
  if tables {
    ignore(self.sheet_tables())
  }
}

///|
fn Session::check_reorder_cells(
  self : Session,
  current : Sheet,
  target : Range,
  filter~ : Bool = false,
  tables~ : Bool = false,
  sparklines~ : Bool = false,
) -> Unit raise @failure.Failure {
  guard self.read_only.is_empty() && !current.locked else {
    @failure.reject(
      "protected-content",
      if current.locked {
        "Worksheet is protected"
      } else {
        self.read_only
      },
    )
  }
  guard !current.merges.any(merge => merge.intersects(target)) else {
    @failure.reject(
      "protected-content", "Merged cells require sorting geometry support",
    )
  }
  self.check_thread_fallbacks(current, self.read_sheet_threads(current))
  self.sort_resources(current, filter~, tables~, sparklines~)
  for cell in current.cells.values() {
    if target.contains(cell.address) {
      guard cell.read_only.is_empty() ||
        cell.read_only == "Rich text cell is read-only" else {
        @failure.reject("protected-content", cell.read_only)
      }
    }
  }
}
