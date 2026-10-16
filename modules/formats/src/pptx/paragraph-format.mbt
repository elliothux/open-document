///|
fn Session::paragraph_reason(self : Session, object : Object) -> String {
  let reason = self.text_frame_reason(object)
  if !reason.is_empty() {
    return reason
  }
  try {
    for paragraph in object.paragraphs {
      if paragraph.source.child("pPr") is Some(p) {
        for name in ["lnSpc", "spcBef", "spcAft"] {
          if p.child(name) is Some(spacing) {
            let children = spacing.tree.children
              .get(spacing.node.id)
              .unwrap_or([])
            guard spacing.node.attributes.is_empty() &&
              spacing.node.text.trim().is_empty() &&
              children is [child] &&
              child.uri == drawing_uri &&
              ["spcPts", "spcPct"].contains(child.name) &&
              child.attributes.length() == 1 &&
              child.attribute("val") is Some(_) &&
              child.text.is_empty() &&
              spacing.tree.children.get(child.id).unwrap_or([]).is_empty() &&
              !source_xml(spacing).contains("<!--") &&
              !source_xml(spacing).contains("<?") else {
              return "Extended paragraph spacing requires editing support"
            }
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::paragraph_query(self : Session) -> Json {
  let fields = ["left", "right", "first", "before", "after", "line"]
  let result : Map[String, Json] = Map([])
  for field in fields {
    result[field] = Json::null()
  }
  result["reason"] = Json("Select an editable text frame")
  let selection = self.candidate.map(c => c.selection).unwrap_or(self.selection)
  if selection.objects.is_empty() {
    return Json(result)
  }
  try {
    let values : Array[Array[Json]] = []
    for id in selection.objects {
      let object = self.current().object(id)
      let reason = self.paragraph_reason(object)
      if !reason.is_empty() {
        result["reason"] = Json(reason)
        return Json(result)
      }
      let mut offset = 0
      for paragraph in object.paragraphs {
        let length = paragraph_length(paragraph)
        if paragraph_selected(selection, offset, length) {
          values.push(paragraph_values(paragraph))
        }
        offset += length + 1
      }
    }
    result["reason"] = Json("")
    if values is [first, ..] {
      for index, field in fields {
        if values.all(value => value[index] == first[index]) {
          result[field] = first[index]
        }
      }
    }
  } catch {
    @failure.Failure(message~, ..) => result["reason"] = Json(message)
  }
  Json(result)
}

///|
fn paragraph_changes(
  object : Object,
  selection : Selection,
  format : ParagraphFormat?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let mut offset = 0
  for paragraph in object.paragraphs {
    let length = paragraph_length(paragraph)
    if paragraph_selected(selection, offset, length) {
      let markup = paragraph_markup(paragraph, format)
      if !markup.is_empty() {
        changes.push(
          if paragraph.source.child("pPr") is Some(p) {
            {
              node: paragraph.source.node.id,
              offset: p.node.start - paragraph.source.node.start,
              length: p.node.end - p.node.start,
              xml: markup,
            }
          } else if paragraph.source.node.empty {
            insertion(paragraph.source.node, markup)
          } else {
            {
              node: paragraph.source.node.id,
              offset: paragraph.source.node.opening_end -
              paragraph.source.node.start,
              length: 0,
              xml: markup,
            }
          },
        )
      }
    }
    offset += length + 1
  }
  changes
}
