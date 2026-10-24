///|
fn Session::set_footer(
  self : Session,
  index : Int,
  content : FooterContent,
  all : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let content = {
    ..content,
    date: footer_date(content.date),
    footer: footer_text(content.footer),
  }
  let date_text = content.date.map(date => {
    match date {
      Fixed(text) => text
      Automatic(format, language) => {
        guard self.date_time is Some(time) else {
          @failure.reject(
            "invalid-operation", "Automatic dates require an explicit presentation time",
          )
        }
        date_field_value(format, language, time)
      }
    }
  })
  let slides = self.slides.copy()
  let reserved = self.reserved_object_identities()
  let mut next = self.object_sequence
  let edits : Array[(String, @xml.Edit)] = []
  let touched : Map[String, Bool] = Map([])
  let removed : Map[String, Bool] = Map([])
  let mut units = 0L
  for i, original in self.slides {
    if !all && i != index {
      continue
    }
    let existing = original.footer_objects()
    let tree = original.tree
    let changes : Array[@xml.SourceChange] = []
    let affected : Array[String] = []
    for
      (kind, text) in [
        ("dt", date_text),
        ("ftr", content.footer),
        (
          "sldNum",
          if content.number {
            Some(presentation_number(self.main, i))
          } else {
            None
          },
        ),
      ] {
      let before = existing.get(kind)
      if text is None {
        if before is Some(object) {
          let reason = self.object_edit_reason(object, "delete")
          guard reason.is_empty() else {
            @failure.reject("protected-content", reason)
          }
          let node = object.source.node
          let parent = tree.nodes[node.parent]
          changes.push({
            node: parent.id,
            offset: node.start - parent.start,
            length: node.end - node.start,
            xml: "",
          })
          removed[object.id] = true
        }
        continue
      }
      let text = text.unwrap()
      if before is Some(object) &&
        (
          (kind == "dt" && Some(object.footer_date()) == content.date) ||
          (kind == "ftr" && object.text() == text) ||
          (kind == "sldNum" && object.text_reason == slide_number_text_reason)
        ) {
        continue
      }
      let source = match before {
        Some(object) => Some(object.source)
        None => self.footer_template(original, kind)
      }
      let automatic = if kind == "dt" { content.date } else { None }
      let (field, language) = match automatic {
        Some(Automatic(format, language)) =>
          ("datetime" + format.to_string(), language)
        _ => ("", "")
      }
      let body = footer_body(source, kind, text, field~, language~)
      if before is Some(object) {
        let body = if kind == "sldNum" ||
          (!field.is_empty() && object.text_reason != date_field_text_reason) {
          let (copied, after) = footer_copy(
            body,
            tree.part,
            reserved,
            next,
            self.budget,
          )
          next = after
          copied.source()
        } else {
          body
        }
        if object.source.child("txBody", uri=presentation_uri) is Some(old) {
          changes.push({
            node: object.source.node.id,
            offset: old.node.start - object.source.node.start,
            length: old.node.end - old.node.start,
            xml: body,
          })
        } else {
          changes.push(insertion(object.source.node, body))
        }
        affected.push(object.id)
        touched[object.id] = true
      } else {
        let markup = if source is Some(source) {
          layout_placeholder_markup(source, "1", content=body)
        } else {
          self.footer_shape(kind, body)
        }
        let (copied, after) = footer_copy(
          markup,
          tree.part,
          reserved,
          next,
          self.budget,
        )
        next = after
        let identity = copied
          .nodes()
          .iter()
          .find_first(node => {
            node.uri == presentation_uri && node.name == "cNvPr"
          })
          .unwrap()
          .attribute("id")
          .unwrap()
        changes.push(object_insertion(tree, copied.source()))
        affected.push(tree.part + "#" + identity)
      }
    }
    if changes.is_empty() {
      continue
    }
    for change in changes {
      units += (change.length.to_int64() + change.xml.length().to_int64()) * 2
    }
    guard units <= 4194304L else {
      @failure.reject(
        "limit-exceeded", "Slide footer changes exceed history budget",
      )
    }
    let (candidate, edit) = self.prepare(original, changes)
    edits.push((tree.part, edit))
    let fit_changes : Array[@xml.SourceChange] = []
    for id in affected {
      let object = candidate.object(id)
      guard object.read_only.is_empty() &&
        (
          object.text_reason.is_empty() ||
          calculated_field_reason(object.text_reason)
        ) &&
        object.diagnostic.is_empty() else {
        @failure.reject(
          "protected-content", "Slide footer cannot be displayed safely",
        )
      }
      if object.body.fit == "resize" {
        fit_changes.append(
          resized_frame_changes(
            object,
            resize_text_frame(object, probe, profile),
          ),
        )
      } else {
        let (_, scale, diagnostic, _) = fit_text(
          object,
          object.geometry.unwrap(),
          probe,
          profile,
        )
        guard diagnostic.is_empty() else {
          @failure.reject("layout-overflow", diagnostic)
        }
        if object.body.fit == "shrink" {
          fit_changes.append(normal_fit_changes(object, scale))
        }
      }
    }
    slides[i] = if fit_changes.is_empty() {
      candidate
    } else {
      let (candidate, edit) = self.prepare(candidate, fit_changes)
      edits.push((tree.part, edit))
      candidate
    }
  }
  if edits.is_empty() {
    return self.query()
  }
  let mut after = self.selection
  if after.objects.any(id => removed.contains(id)) ||
    touched.contains(after.object) {
    let objects = after.objects.filter(id => !removed.contains(id))
    after = {
      ..after,
      object: if removed.contains(after.object) {
        objects.last().unwrap_or("")
      } else {
        after.object
      },
      objects,
      mode: "object",
      anchor: 0,
      focus: 0,
    }
  }
  self.commit_slides(self.main, slides, edits, after)
  self.object_sequence = next
  self.query()
}
