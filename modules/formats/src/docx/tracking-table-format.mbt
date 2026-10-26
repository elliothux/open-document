///|
fn Session::record_table_properties(
  self : Session,
  before : @xml.Document,
  candidate : @xml.Document,
  owners : Array[Int],
  kind~ : String = "trPr",
  force~ : Bool = false,
) -> (@xml.Document, Array[@xml.Edit], Int) raise @failure.Failure {
  guard self.tracking_context is Some((author, date)) else {
    return (candidate, [], 0)
  }
  let tree = WordTree::new(before)
  let next = WordTree::new(candidate)
  let rows = owners.filter(row => {
    let original = tree
      .child(row, kind)
      .map(id => {
        let node = tree.nodes[id]
        tree.source[node.start:node.end].to_owned()
      })
      .unwrap_or("")
    let updated = next
      .child(row, kind)
      .map(id => {
        let node = next.nodes[id]
        next.source[node.start:node.end].to_owned()
      })
      .unwrap_or("")
    force || original != updated
  })
  let fresh = rows.filter(row => {
    (kind != "trPr" || tree.row_revision(row) is None) &&
    tree.child(row, kind).bind(props => tree.child(props, kind + "Change"))
    is None
  })
  let ids = tree.unused_revision_ids(fresh.length())
  let changes : Array[@xml.SourceChange] = []
  for row in rows {
    let original = tree.child(row, kind)
    let existing = original.bind(props => tree.child(props, kind + "Change"))
    if existing is Some(id) {
      if kind == "trPr" {
        ignore(tree.check_row_property_revision(id))
      } else if kind == "tcPr" {
        ignore(tree.check_cell_property_revision(id))
      } else {
        ignore(tree.check_table_property_revision(id))
      }
    } else if original is Some(props) {
      if kind == "trPr" {
        tree.check_row_format_properties(props)
      } else if kind == "tcPr" {
        tree.check_cell_format_properties(props)
      } else {
        tree.check_table_format_properties(props)
      }
    }
    let source_row = if kind == "tcPr" { tree.nodes[row].parent } else { row }
    if kind != "tblPr" && tree.row_revision(source_row) is Some(mark) {
      ignore(tree.check_row_revision(mark))
      guard tree.nodes[mark].name == "ins" &&
        tree.nodes[mark].attribute("author", uri=word_uri) == Some(author) else {
        @failure.reject(
          "protected-content", "Review this row revision before changing its format",
        )
      }
      continue
    }
    let id = existing
      .map(id => tree.nodes[id].attribute("id", uri=word_uri).unwrap())
      .unwrap_or_else(() => ids[fresh.search(row).unwrap()].to_string())
    let previous = existing
      .map(id => tree.standalone_markup(before, tree.children[id][0]))
      .unwrap_or_else(() => {
        let content = original
          .map(props => {
            tree.children[props]
            .map(id => tree.standalone_markup(before, id))
            .join("")
          })
          .unwrap_or("")
        "<od:\{kind} xmlns:od=\"\{word_uri}\">\{content}</od:\{kind}>"
      })
    let markup = "<od:\{kind}Change xmlns:od=\"\{word_uri}\" od:id=\"\{id}\" od:author=\"\{property_attribute(author)}\" od:date=\"\{property_attribute(date)}\">\{previous}</od:\{kind}Change>"
    if next.child(row, kind).bind(props => next.child(props, kind + "Change"))
      is Some(mark) {
      changes.push({ ..table_remove(next, mark), xml: markup, })
    } else if next.table_property_change(
        candidate,
        row,
        kind,
        kind + "Change",
        None,
        markup=Some(markup),
      )
      is Some(change) {
      changes.push(change)
    }
  }
  if changes.is_empty() {
    return (candidate, [], 0)
  }
  let (result, edit) = candidate.edit_source(changes)
  if kind == "tcPr" {
    let tables = Set::from_array(
      rows.map(cell => tree.nodes[tree.nodes[cell].parent].parent),
    )
    let next = WordTree::new(result)
    let fresh = tables
      .to_array()
      .filter(table => {
        next.child(table, "tblPr").bind(p => next.child(p, "tblPrChange"))
        is None
      })
    // Native cell snapshots also establish the table's review group.
    let (result, steps, bytes) = self.record_table_properties(
      result,
      result,
      fresh,
      kind="tblPr",
      force=true,
    )
    (result, [edit, ..steps], edit_bytes(edit) + bytes)
  } else {
    (result, [edit], edit_bytes(edit))
  }
}
