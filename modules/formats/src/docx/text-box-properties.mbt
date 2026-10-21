///|
/// Edits a native text box's text area as one source transaction, preserving content and selection.
pub fn Session::edit_text_box(
  self : Session,
  revision : Int,
  id : Int,
  properties : @layout.DrawingTextBoxProperties,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard properties.insets.length() == 4 &&
    properties.insets.all(v => {
      !v.is_nan() && !v.is_inf() && v >= 0 && v <= 14400
    }) &&
    ["t", "ctr", "b"].contains(properties.anchor) else {
    @failure.reject("invalid-operation", "Invalid text box properties")
  }
  let properties = {
    ..properties,
    insets: properties.insets.map(v => (v * 12700).round() / 12700),
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let (paragraph, frame, _) = self.editable_shape(tree, id)
  guard frame.content is @layout.TextBox(_, text) else {
    @failure.reject("invalid-operation", "Drawing is not a text box")
  }
  guard !tree.shape_locked(id, "noTextEdit") &&
    !tree.shape_locked(id, "noSelect") else {
    @failure.reject("protected-content", "Text box text editing is locked")
  }
  if Json(text.properties()) == Json(properties) {
    return self.edit_result([])
  }
  let shape = tree.children[tree.drawing_data(id).1.id][0]
  let values : Map[String, String] = {
    "anchor": properties.anchor,
    "wrap": if properties.wrap {
      "square"
    } else {
      "none"
    },
    "horzOverflow": if properties.clip {
      "clip"
    } else {
      "overflow"
    },
    "vertOverflow": if properties.clip {
      "clip"
    } else {
      "overflow"
    },
  }
  for index, name in ["tIns", "rIns", "bIns", "lIns"] {
    values[name] = (properties.insets[index] * 12700)
      .round()
      .to_int64()
      .to_string()
  }
  let changes : Array[@xml.SourceChange] = []
  if tree.drawing_child(shape, "bodyPr", uri=word_shape_uri) is Some(body) {
    let node = tree.nodes[body]
    let missing = StringBuilder()
    for name, value in values {
      if node.attributes
        .iter()
        .find_first(a => a.uri.is_empty() && a.name == name)
        is Some(attr) {
        if attr.value != value {
          changes.push({
            node: body,
            offset: attr.start - node.start,
            length: attr.end - attr.start,
            xml: value,
          })
        }
      } else {
        missing.write_string(" " + name + "=\"" + value + "\"")
      }
    }
    let markup = missing.to_string()
    if !markup.is_empty() {
      changes.push({
        node: body,
        offset: node.opening_end - node.start - (if node.empty { 2 } else { 1 }),
        length: 0,
        xml: markup,
      })
    }
  } else {
    let attributes = values
      .keys()
      .to_array()
      .map(name => " " + name + "=\"" + values[name] + "\"")
      .join("")
    changes.push(
      tree.shape_property_change(
        shape,
        None,
        None,
        "<wps:bodyPr xmlns:wps=\"\{word_shape_uri}\"\{attributes}><a:noAutofit xmlns:a=\"\{picture_drawing_uri}\"/></wps:bodyPr>",
      ),
    )
  }
  let (candidate, xml) = document.edit_source(changes)
  ignore(self.drawing_frame(WordTree::new(candidate), id))
  self.check_picture_layout(candidate, probe, profile, images)
  let paragraphs = [paragraph, ..text.paragraphs().map(p => p.id)]
  self.commit_edit(
    {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs,
      bytes: edit_bytes(xml),
    },
    candidate,
  )
  self.edit_result(paragraphs)
}
