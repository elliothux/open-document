///|
fn attribute_change(
  source : Ref,
  name : String,
  value : String,
) -> @xml.SourceChange {
  let node = source.node
  if node.attributes
    .iter()
    .find_first(attr => attr.uri.is_empty() && attr.name == name)
    is Some(attr) {
    {
      node: node.id,
      offset: attr.start - node.start,
      length: attr.end - attr.start,
      xml: value,
    }
  } else {
    {
      node: node.id,
      offset: node.opening_end - node.start - (if node.empty { 2 } else { 1 }),
      length: 0,
      xml: " \{name}=\"\{value}\"",
    }
  }
}

///|
fn Session::prepare_fitted(
  self : Session,
  original : Slide,
  changes : Array[@xml.SourceChange],
  ids : Array[String],
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Slide, @xml.Edit) raise @failure.Failure {
  let prepared = self.prepare(original, changes)
  for id in ids {
    let target = prepared.0.object(id)
    if target.table is Some(_) {
      let fit = target.table_fit_changes(probe, profile)
      if !fit.is_empty() {
        let (document, _) = prepared.0.tree.document.edit_source(fit)
        let tree = Tree::new(original.tree.part, document)
        let source = original.object(id).source
        // Fit uses the resized source offsets; compose back into the original frame.
        for index = changes.length() - 1; index >= 0; index = index - 1 {
          let change = changes[index]
          let start = original.tree.nodes[change.node].start + change.offset
          if start >= source.node.start &&
            start + change.length <= source.node.end {
            ignore(changes.remove(index))
          }
        }
        changes.push(
          table_source_change(
            source,
            source_xml({ tree, node: tree.nodes[target.source.node.id], }),
          ),
        )
      }
      continue
    }
    if target.body.fit == "none" || target.paragraphs.is_empty() {
      continue
    }
    if target.body.fit == "resize" {
      let geometry = resize_text_frame(target, probe, profile)
      for change in resized_frame_changes(original.object(id), geometry) {
        let existing = changes.search_by(item => {
          item.node == change.node &&
          item.offset == change.offset &&
          item.length == change.length
        })
        if existing is Some(index) {
          changes[index] = change
        } else {
          changes.push(change)
        }
      }
      continue
    }
    let (_, scale, diagnostic, _) = fit_text(
      target,
      target.geometry.unwrap(),
      probe,
      profile,
      recalculate=true,
    )
    guard diagnostic.is_empty() else {
      @failure.reject("layout-overflow", diagnostic, part=original.tree.part)
    }
    changes.append(normal_fit_changes(original.object(id), scale))
  }
  self.prepare(original, changes)
}

///|
fn normal_fit_reduction(scale : Double) -> String {
  (0.2 * (1 - scale) * 100000).round().to_int().to_string()
}

///|
fn normal_fit_changes(
  object : Object,
  scale : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let body = object.source.child("txBody", uri=presentation_uri).unwrap()
  let properties = body.child("bodyPr")
  let fit = properties.bind(item => item.child("normAutofit"))
  let value = (scale * 100000).floor().to_int().to_string()
  let reduction = normal_fit_reduction(scale)
  let changes : Array[@xml.SourceChange] = []
  if fit is Some(fit) {
    if fit.node.attribute("fontScale").unwrap_or("100000") != value {
      changes.push(attribute_change(fit, "fontScale", value))
    }
    if fit.node.attribute("lnSpcReduction").unwrap_or("0") != reduction {
      changes.push(attribute_change(fit, "lnSpcReduction", reduction))
    }
    // Missing attributes share an insertion point. Emit one source edit so
    // consumers can distinguish it from conflicting edits to a shared frame.
    if changes.length() == 2 &&
      changes[0].offset == changes[1].offset &&
      changes[0].length == 0 &&
      changes[1].length == 0 {
      return [{ ..changes[0], xml: changes[0].xml + changes[1].xml, }]
    }
  } else if scale < 1 {
    let xml = "<a:normAutofit xmlns:a=\"\{drawing_uri}\" fontScale=\"\{value}\" lnSpcReduction=\"\{reduction}\"/>"
    if properties is Some(properties) {
      changes.push(insertion(properties.node, xml))
    } else {
      changes.push({
        node: body.node.id,
        offset: body.node.opening_end - body.node.start,
        length: 0,
        xml: "<a:bodyPr xmlns:a=\"\{drawing_uri}\">\{xml}</a:bodyPr>",
      })
    }
  }
  changes
}

///|
fn derived_frame_changes(
  object : Object,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if object.body.fit == "none" || object.paragraphs.is_empty() {
    return []
  }
  let body = object.source.child("txBody", uri=presentation_uri).unwrap()
  if body.child("bodyPr") is Some(properties) {
    let reason = text_fit_reason(properties)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
  }
  if object.body.fit == "resize" {
    guard [
      "", "Master objects are read-only", "Layout objects are read-only", "Group members are read-only",
    ].contains(object.read_only) else {
      @failure.reject("protected-content", object.read_only)
    }
    let next = resize_text_frame(
      { ..object, read_only: "", parent: "", },
      probe,
      profile,
    )
    return resized_frame_changes(object, next)
  }
  let (_, scale, diagnostic, _) = fit_text(
    object,
    object.geometry.unwrap(),
    probe,
    profile,
    recalculate=true,
  )
  guard diagnostic.is_empty() else {
    @failure.reject("layout-overflow", diagnostic)
  }
  normal_fit_changes(object, scale)
}
