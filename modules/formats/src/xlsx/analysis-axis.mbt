///|
fn Session::axis_analysis(
  self : Session,
  sheet : Sheet,
  change : AxisChange,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Map[String, Range] raise @failure.Failure {
  let resources = self.analysis_parts()
  let moved : Map[String, Range] = Map([])
  let projected_records : Map[String, Array[Int]] = Map([])
  for pivot in self.pivot_locations() {
    if pivot.sheet != sheet.id {
      continue
    }
    guard change.range(pivot.range) is Some(next) &&
      next.bottom - next.top == pivot.range.bottom - pivot.range.top &&
      next.right - next.left == pivot.range.right - pivot.range.left else {
      @failure.reject(
        "protected-content", "Axis editing cannot split or remove a pivot report",
      )
    }
    if next == pivot.range {
      continue
    }
    let document = self.part_xml(pivot.part)
    let tree = Tree::new(document)
    let location = tree.one(0, "location").unwrap()
    let body = Range::parse(location.attribute("ref").unwrap())
    let rows = next.top - pivot.range.top
    let columns = next.left - pivot.range.left
    let (document, edit) = document.edit_source(
      metadata_changes(location, [
        (
          "ref",
          Range::{
            top: body.top + rows,
            bottom: body.bottom + rows,
            left: body.left + columns,
            right: body.right + columns,
          }.name(),
        ),
      ]),
    )
    parts[pivot.part] = document
    edits.push((pivot.part, edit))
    moved[pivot.part] = next
  }
  for path in resources {
    let document = self.part_xml(path)
    if document.nodes()[0].name != "pivotCacheDefinition" {
      continue
    }
    let tree = Tree::new(document)
    let source = tree
      .one(0, "cacheSource")
      .bind(node => tree.one(node.id, "worksheetSource"))
    guard source is Some(source) &&
      source
      .attribute("sheet")
      .map(name => name.to_lower() == sheet.name.to_lower())
      .unwrap_or(false) else {
      continue
    }
    let original = Range::parse(source.attribute("ref").unwrap_or(""))
    guard change.range(original) is Some(next) && next.bottom > next.top else {
      @failure.reject(
        "protected-content", "Axis editing must retain a pivot source header and data range",
      )
    }
    if next.right - next.left != original.right - original.left {
      self.project_analysis_columns(
        path, original, next, change, parts, edits, projected_records, resources,
      )
      continue
    }
    if original == next {
      continue
    }
    let changes = metadata_changes(source, [("ref", next.name())])
    changes.append(metadata_changes(tree.nodes[0], [("invalid", "1")]))
    let (document, edit) = document.edit_source(changes)
    parts[path] = document
    edits.push((path, edit))
  }
  moved
}
