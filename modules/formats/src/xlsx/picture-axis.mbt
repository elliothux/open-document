///|
fn AxisChange::picture_markers(
  self : AxisChange,
  first : Int,
  first_offset : Double,
  last : Int,
  last_offset : Double,
  resize : Bool,
) -> (Int, Double, Int, Double) raise @failure.Failure {
  let at = self.first - 1
  let end = at + self.count - 1
  let (first, first_offset, last, last_offset) = if self.insert {
    if at <= first {
      (first + self.count, first_offset, last + self.count, last_offset)
    } else if resize && at <= last {
      (first, first_offset, last + self.count, last_offset)
    } else {
      (first, first_offset, last, last_offset)
    }
  } else if at <= first {
    if end < first {
      (first - self.count, first_offset, last - self.count, last_offset)
    } else if resize {
      let remaining = last - end - 1
      (
        at,
        0.0,
        at + remaining.max(1),
        if remaining > 0 {
          last_offset
        } else {
          0.0
        },
      )
    } else {
      (first, first_offset, last, last_offset)
    }
  } else if resize && at <= last {
    if end >= last {
      (first, first_offset, at, 0.0)
    } else {
      (first, first_offset, last - self.count, last_offset)
    }
  } else {
    (first, first_offset, last, last_offset)
  }
  guard first >= 0 &&
    last >= first &&
    first < self.limit() &&
    last < self.limit() else {
    @failure.reject(
      "invalid-operation", "Structural editing would move a picture anchor outside the worksheet",
    )
  }
  (
    first,
    first_offset,
    last,
    if first == last {
      last_offset.max(first_offset)
    } else {
      last_offset
    },
  )
}

///|
fn SheetObject::axis_marker_changes(
  self : SheetObject,
  change : AxisChange,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if self.anchor == "fixed" || change.band is Some(_) {
    return []
  }
  let name = if change.rows { "row" } else { "col" }
  let offset_name = name + "Off"
  let from = self.tree.picture_node(self.frame.id, "from")
  let to = if self.anchor == "size" {
    self.tree.picture_node(self.frame.id, "to")
  } else {
    from
  }
  let first = natural(
    self.tree.picture_node(from.id, name).text,
    change.limit() - 1,
  )
  let first_offset = picture_integer(
    self.tree.picture_node(from.id, offset_name).text,
  )
  let last = natural(
    self.tree.picture_node(to.id, name).text,
    change.limit() - 1,
  )
  let last_offset = picture_integer(
    self.tree.picture_node(to.id, offset_name).text,
  )
  let (a, a_offset, b, b_offset) = change.picture_markers(
    first,
    first_offset,
    last,
    last_offset,
    self.anchor == "size",
  )
  let result : Array[@xml.SourceChange] = []
  for
    (marker, old, old_offset, next, offset) in [
      (from, first, first_offset, a, a_offset),
      (to, last, last_offset, b, b_offset),
    ] {
    if old != next {
      result.append(
        axis_text_change(
          self.tree,
          self.tree.picture_node(marker.id, name),
          next.to_string(),
        ),
      )
    }
    if old_offset != offset {
      result.append(
        axis_text_change(
          self.tree,
          self.tree.picture_node(marker.id, offset_name),
          offset.to_int64().to_string(),
        ),
      )
    }
    if self.anchor != "size" {
      break
    }
  }
  result
}

///|
fn Session::axis_pictures(
  self : Session,
  before : Sheet,
  after : Sheet,
  change : AxisChange,
  context : Session,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  analysis~ : Bool = false,
) -> Unit raise @failure.Failure {
  guard self.picture_drawing(before) is Some(_) else { return }
  guard self.font_context is Some((probe, profile)) else {
    @failure.reject(
      "missing-font", "Measure worksheet picture anchors before structural editing",
    )
  }
  let before_dimensions = self.resolved_dimensions(before, probe, profile)
  let after_dimensions = context.resolved_dimensions(after, probe, profile)
  let pictures = self.sheet_objects(before, before_dimensions)
  if pictures.is_empty() {
    return
  }
  let changes : Array[@xml.SourceChange] = []
  for picture in pictures {
    changes.append(picture.axis_marker_changes(change))
  }
  let part = pictures[0].part
  if !changes.is_empty() {
    let (document, edit) = pictures[0].tree.document.edit_source(changes)
    parts[part] = document
    edits.push((part, edit))
  }
  let candidate = { ..context, parts, }
  let next = candidate.sheet_objects(after, after_dimensions)
  let transforms : Array[@xml.SourceChange] = []
  for index, picture in next {
    let previous = pictures[index]
    if picture.rect.x != previous.rect.x ||
      picture.rect.y != previous.rect.y ||
      picture.rect.width != previous.rect.width ||
      picture.rect.height != previous.rect.height {
      transforms.push(
        picture.transform_change(picture.rect, analysis_frame=analysis),
      )
    }
  }
  if !transforms.is_empty() {
    let (document, edit) = next[0].tree.document.edit_source(transforms)
    parts[part] = document
    edits.push((part, edit))
  }
}
