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
    let (_, scale, diagnostic) = fit_text(
      target,
      target.geometry.unwrap(),
      probe,
      profile,
    )
    guard diagnostic.is_empty() else {
      @failure.reject("layout-overflow", diagnostic, part=original.tree.part)
    }
    changes.append(normal_fit_changes(original.object(id), scale))
  }
  self.prepare(original, changes)
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
  let changes : Array[@xml.SourceChange] = []
  if fit is Some(fit) {
    if fit.node.attribute("fontScale").unwrap_or("100000") != value {
      changes.push(attribute_change(fit, "fontScale", value))
    }
    if fit.node.attribute("lnSpcReduction").unwrap_or("0") != "0" {
      changes.push(attribute_change(fit, "lnSpcReduction", "0"))
    }
  } else if scale < 1 {
    let xml = "<a:normAutofit xmlns:a=\"\{drawing_uri}\" fontScale=\"\{value}\"/>"
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
