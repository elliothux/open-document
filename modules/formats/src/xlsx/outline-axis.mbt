///|
fn Session::axis_outline(
  self : Session,
  original : Sheet,
  document : @xml.Document,
  change : AxisChange,
  parts : Map[String, @xml.Document],
) -> (@xml.Document, Array[(String, @xml.Edit)]) raise @failure.Failure {
  if change.band is Some(_) {
    return (document, [])
  }
  let before = original.outline_axis(change.rows)
  if before.bands.is_empty() {
    return (document, [])
  }
  let read = fn(document) raise @failure.Failure {
    Sheet::read(
      original.id,
      original.name,
      original.state,
      document,
      self.strings,
      self.styles.length(),
    )
  }
  let edits : Array[(String, @xml.Edit)] = []
  let mut current = read(document)
  let filter_source = current
  let mut inserted_hidden = false
  if change.insert && before.level(change.first - 1) > 0 {
    let metadata : Map[Int, Array[(String, String)]] = Map([])
    inserted_hidden = before.groups.any(group => {
      group.collapsed &&
      group.first < change.first &&
      group.last >= change.first - 1
    })
    for item in change.first..<(change.first + change.count) {
      metadata[item] = [
        ("outlineLevel", before.level(change.first - 1).to_string()),
        ("hidden", if inserted_hidden { "1" } else { "0" }),
      ]
    }
    let (document, edit) = current.document.edit_source(
      current.outline_metadata(change.rows, metadata),
    )
    edits.push((original.id, edit))
    current = read(document)
  }
  let after = current.outline_axis(change.rows)
  let metadata : Map[Int, Array[(String, String)]] = Map([])
  let retained : Map[Int, Bool] = Map([])
  for marker in before.collapsed.keys() {
    if !before.groups.any(group => group.summary == marker) &&
      change.interval(marker, marker) is Some((marker, _)) {
      retained[marker] = true
    }
  }
  for marker in after.collapsed.keys() {
    if !retained.contains(marker) {
      outline_put(metadata, marker, "collapsed", "0")
    }
  }
  for group in before.groups {
    if group.collapsed &&
      change.interval(group.first, group.last) is Some((first, last)) {
      if after.groups
        .iter()
        .find_first(next => {
          next.level == group.level && next.first <= first && next.last >= last
        })
        is Some(next) {
        guard next.summary >= 1 && next.summary <= after.limit else {
          @failure.reject(
            "protected-content", "Structural edit removes the outline summary position",
          )
        }
        outline_put(metadata, next.summary, "collapsed", "1")
      }
    }
  }
  let updates = current.outline_metadata(change.rows, metadata)
  updates.append(
    outline_level_changes(
      current,
      change.rows,
      after.bands.fold(init=0, (value, band) => value.max(band.2)),
    ),
  )
  if !updates.is_empty() {
    let (document, edit) = current.document.edit_source(
      join_insertions(updates),
    )
    edits.push((original.id, edit))
    current = read(document)
  }
  if inserted_hidden && change.rows {
    let (document, changes) = self.filter_dimension_changes(
      filter_source,
      current.document,
      change.first,
      change.first + change.count - 1,
      0,
      parts,
    )
    edits.append(changes)
    current = read(document)
  }
  (current.document, edits)
}
