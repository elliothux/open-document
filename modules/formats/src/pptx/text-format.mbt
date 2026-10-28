///|
fn paragraph_selected(
  selection : Selection,
  offset : Int32,
  length : Int32,
) -> Bool {
  if selection.mode == "object" {
    return true
  }
  let a = selection.anchor.min(selection.focus)
  let b = selection.anchor.max(selection.focus)
  if a == b {
    a >= offset && a <= offset + length
  } else {
    a <= offset + length && b > offset
  }
}

///|
fn paragraph_length(paragraph : TextParagraph) -> Int32 {
  paragraph.runs.fold(init=0, (sum, run) => sum + run.text.length())
}

///|
fn caret_run(
  paragraph : TextParagraph,
  position : Int32,
  leading~ : Bool = false,
) -> (Int32, Int32) {
  let mut offset = 0
  for index, run in paragraph.runs {
    if run.text.is_empty() && offset == position {
      return (index, 0)
    }
    offset += run.text.length()
  }
  offset = 0
  for index, run in paragraph.runs {
    if position < offset + run.text.length() ||
      (
        position == offset + run.text.length() &&
        (!leading || index == paragraph.runs.length() - 1)
      ) {
      return (index, position - offset)
    }
    offset += run.text.length()
  }
  abort("Text caret must belong to a paragraph")
}

///|
fn format_styles(
  object : Object,
  selection : Selection,
) -> Array[@layout.TextStyle] raise @failure.Failure {
  if selection.mode == "text" && selection.anchor == selection.focus {
    let (p, at) = paragraph_location(object, selection.focus)
    let (r, at) = caret_run(object.paragraphs[p], at)
    let run = object.paragraphs[p].runs[r]
    let mut offset = 0
    for (style, text) in run.parts {
      if at <= offset + text.length() {
        return [style]
      }
      offset += text.length()
    }
  }
  let styles : Array[@layout.TextStyle] = []
  let mut offset = 0
  let a = selection.anchor.min(selection.focus)
  let b = selection.anchor.max(selection.focus)
  for paragraph in object.paragraphs {
    for run in paragraph.runs {
      for (style, text) in run.parts {
        if selection.mode == "object" ||
          (a < offset + text.length() && b > offset) ||
          (text.is_empty() && a <= offset && b > offset) {
          styles.push(style)
        }
        offset += text.length()
      }
    }
    offset += 1
  }
  styles
}

///|
fn Session::formatting_reason(self : Session, object : Object) -> String {
  let reason = if object.table is Some(_) {
    table_format_reason(object)
  } else {
    self.text_frame_reason(object)
  }
  if !reason.is_empty() {
    return reason
  }
  try {
    let slide = self.source_slide(object.source.tree.part)
    guard slide.read_only.is_empty() else { return slide.read_only }
    for paragraph in object.paragraphs {
      let properties = paragraph.source
        .child("endParaRPr")
        .map(p => [p])
        .unwrap_or([])
      for run in paragraph.runs {
        if run.source is Some(source) {
          guard source.node.attributes.is_empty() &&
            (source.node.name == "br" || source.child("t") is Some(_)) &&
            source.tree.children
            .get(source.node.id)
            .unwrap_or([])
            .all(n => {
              n.uri == drawing_uri &&
              (n.name == "rPr" || (n.name == "t" && source.node.name == "r"))
            }) else {
            return "Extended or incomplete text runs require formatting support"
          }
          if source.child("rPr") is Some(p) {
            properties.push(p)
          }
        }
      }
      if properties.any(p => {
          p.node.attributes.any(a => !a.uri.is_empty()) ||
          p.tree.children
          .get(p.node.id)
          .unwrap_or([])
          .any(n => n.uri != drawing_uri || n.name == "extLst")
        }) {
        return "Extended text properties require formatting support"
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::formatting_query(self : Session) -> Json {
  let result : Map[String, Json] = Map([
    ("font", Json::null()),
    ("size", Json::null()),
    ("spacing", Json::null()),
    ("bold", Json::null()),
    ("italic", Json::null()),
    ("color", Json::null()),
    ("underline", Json::null()),
    ("strike", Json::null()),
    ("highlight", Json::null()),
    ("script", Json::null()),
    ("alignment", Json::null()),
    ("reason", Json("Select an editable text frame")),
  ])
  let selection = self.candidate.map(c => c.selection).unwrap_or(self.selection)
  if selection.objects.is_empty() {
    return Json(result)
  }
  try {
    let styles : Array[@layout.TextStyle] = []
    let alignments : Array[String] = []
    for id in selection.objects {
      let object = self.current().object(id)
      let reason = self.formatting_reason(object)
      if !reason.is_empty() {
        result["reason"] = Json(reason)
        return Json(result)
      }
      for (target, selected) in object.format_targets(selection) {
        styles.append(format_styles(target, selected))
        let mut offset = 0
        for paragraph in target.paragraphs {
          let length = paragraph_length(paragraph)
          if paragraph_selected(selected, offset, length) {
            alignments.push(paragraph.align)
          }
          offset += length + 1
        }
      }
    }
    result["reason"] = Json("")
    if styles is [first, ..] {
      let values = fn(style : @layout.TextStyle) -> Array[Json] {
        let parts = style.font.split("|").to_array()
        [
          Json(parts[0].to_owned()),
          Json(style.size),
          Json(style.spacing),
          Json(parts.contains("bold")),
          Json(parts.contains("italic")),
          Json(style.color.to_lower()),
          Json(style.underline),
          Json(style.strike),
          Json(style.highlight.to_lower()),
          Json(style.script),
        ]
      }
      let initial = values(first)
      for
        i, name in [
          "font", "size", "spacing", "bold", "italic", "color", "underline", "strike",
          "highlight", "script",
        ] {
        if styles.all(style => values(style)[i] == initial[i]) {
          result[name] = initial[i]
        }
      }
    }
    if alignments is [first, ..] && alignments.all(v => v == first) {
      result["alignment"] = Json(first)
    }
  } catch {
    @failure.Failure(message~, ..) => result["reason"] = Json(message)
  }
  Json(result)
}

///|
fn text_property_change(
  parent : Ref,
  name : String,
  format : TextFormat?,
  hyperlink~ : String? = None,
) -> @xml.SourceChange raise @failure.Failure {
  let existing = parent.child(name)
  let markup = formatted_properties(existing, name, format, hyperlink~)
  if existing is Some(existing) {
    {
      node: parent.node.id,
      offset: existing.node.start - parent.node.start,
      length: existing.node.end - existing.node.start,
      xml: markup,
    }
  } else {
    insertion(parent.node, markup)
  }
}

///|
fn text_format_changes(
  object : Object,
  selection : Selection,
  format : TextFormat?,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let a = selection.anchor.min(selection.focus)
  let b = selection.anchor.max(selection.focus)
  let caret = if selection.mode == "text" && a == b {
    Some(paragraph_location(object, a))
  } else {
    None
  }
  let mut offset = 0
  for index, paragraph in object.paragraphs {
    let length = paragraph_length(paragraph)
    if caret is Some((p, at)) && p == index {
      let (r, within) = caret_run(paragraph, at)
      let run = paragraph.runs[r]
      let changed = if format is Some(format) {
        !format.matches(format_styles(object, selection)[0])
      } else {
        has_direct_properties(
          if run.source is Some(source) {
            source.child("rPr")
          } else {
            paragraph.source.child("endParaRPr")
          },
        )
      }
      if changed {
        if run.source is Some(source) {
          let markup = if run.text.is_empty() {
            format_run(run, 0, 0, format, clear=format is None)
          } else {
            (if within > 0 { format_run(run, 0, within, None) } else { "" }) +
            format_run(run, within, within, format, clear=format is None) +
            (if within < run.text.length() {
              format_run(run, within, run.text.length(), None)
            } else {
              ""
            })
          }
          changes.push({
            node: source.node.parent,
            offset: source.node.start -
            source.tree.nodes[source.node.parent].start,
            length: source.node.end - source.node.start,
            xml: markup,
          })
        } else {
          changes.push(
            text_property_change(paragraph.source, "endParaRPr", format),
          )
        }
      }
    } else if caret is None {
      let mut position = offset
      for run in paragraph.runs {
        let start = if selection.mode == "object" {
          0
        } else {
          (a - position).max(0)
        }
        let end = if selection.mode == "object" {
          run.text.length()
        } else {
          (b - position).min(run.text.length())
        }
        if (
            start < end ||
            (
              run.text.is_empty() &&
              (selection.mode == "object" || (a <= position && b > position))
            )
          ) &&
          (if format is Some(format) {
            !run.parts.all(pair => format.matches(pair.0))
          } else {
            has_direct_properties(run.source.bind(s => s.child("rPr")))
          }) &&
          run.source is Some(source) {
          let markup = (if start > 0 {
              format_run(run, 0, start, None)
            } else {
              ""
            }) +
            format_run(run, start, end, format, clear=format is None) +
            (if end < run.text.length() {
              format_run(run, end, run.text.length(), None)
            } else {
              ""
            })
          changes.push({
            node: source.node.parent,
            offset: source.node.start -
            source.tree.nodes[source.node.parent].start,
            length: source.node.end - source.node.start,
            xml: markup,
          })
        }
        position += run.text.length()
      }
      if (if format is Some(format) {
          selection.mode == "object" &&
          paragraph.runs.any(run => {
            !run.parts.all(pair => format.matches(pair.0))
          })
        } else {
          (
            selection.mode == "object" ||
            (a <= offset + length && b > offset + length)
          ) &&
          has_direct_properties(paragraph.source.child("endParaRPr"))
        }) {
        changes.push(
          text_property_change(paragraph.source, "endParaRPr", format),
        )
      }
    }
    offset += length + 1
  }
  changes
}

///|
fn Session::format_objects(
  self : Session,
  change : ObjectEdit,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard !self.selection.objects.is_empty() else {
    @failure.reject("invalid-operation", "Select editable text first")
  }
  let format = match change {
    TextFormat(value) => Some(value.normalized())
    _ => None
  }
  let alignment = match change {
    TextAlign(value) => value
    _ => ""
  }
  let paragraph = match change {
    TextParagraph(value) => Some(value.normalized())
    _ => None
  }
  let clear_text = change is ClearTextFormat
  let clear_paragraph = change is ClearParagraphFormat
  guard format is Some(_) ||
    paragraph is Some(_) ||
    clear_text ||
    clear_paragraph ||
    ["left", "center", "right", "justify"].contains(alignment) else {
    @failure.reject("invalid-operation", "Unsupported paragraph alignment")
  }
  let changes : Array[@xml.SourceChange] = []
  for id in self.selection.objects {
    let owner = self.current().object(id)
    let reason = if paragraph is Some(_) || clear_paragraph {
      self.paragraph_reason(owner)
    } else {
      self.formatting_reason(owner)
    }
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    for (object, selected) in owner.format_targets(self.selection) {
      if paragraph is Some(_) || clear_paragraph {
        changes.append(paragraph_changes(object, selected, paragraph))
      } else if format is Some(_) || clear_text {
        changes.append(text_format_changes(object, selected, format))
      } else {
        let mut offset = 0
        for paragraph in object.paragraphs {
          let length = paragraph_length(paragraph)
          if paragraph_selected(selected, offset, length) &&
            paragraph.align != alignment {
            let existing = paragraph.source.child("pPr")
            let code = if alignment == "center" {
              "ctr"
            } else if alignment == "right" {
              "r"
            } else if alignment == "justify" {
              "just"
            } else {
              "l"
            }
            let markup = if existing is Some(p) {
              frame_opening(p, Map([("algn", code)])) +
              (if p.node.empty {
                ""
              } else {
                p.tree.document.source()[p.node.opening_end:p.node.closing_start].to_owned()
              }) +
              "</\{p.node.qualified}>"
            } else {
              "<a:pPr xmlns:a=\"\{drawing_uri}\" algn=\"\{code}\"/>"
            }
            changes.push(
              if existing is Some(p) {
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
          offset += length + 1
        }
      }
    }
  }
  if changes.is_empty() {
    return self.query()
  }
  let (candidate, edit) = self.prepare_fitted(
    self.current(),
    changes,
    self.selection.objects,
    probe,
    profile,
  )
  for id in self.selection.objects {
    let target = candidate.object(id)
    if target.table is Some(_) {
      ignore(target.paint_table(probe, profile))
      continue
    }
    ignore(fit_text(target, target.geometry.unwrap(), probe, profile))
  }
  self.commit(candidate, edit, self.selection, probe~, profile~)
  self.query()
}
