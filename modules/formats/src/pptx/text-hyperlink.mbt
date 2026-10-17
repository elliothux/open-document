///|
priv struct TextHyperlinkSpan {
  paragraph : TextParagraph
  run : TextRun?
  start : Int
  end : Int
}

///|
fn TextHyperlinkSpan::properties(
  self : TextHyperlinkSpan,
) -> Ref? raise @failure.Failure {
  if self.run is Some(run) {
    run.source.bind(source => source.child("rPr"))
  } else {
    self.paragraph.source.child("endParaRPr")
  }
}

///|
fn same_text_hyperlink(
  left : Ref?,
  right : Ref?,
) -> Bool raise @failure.Failure {
  guard left.bind(p => p.child("hlinkClick")) is Some(left) &&
    right.bind(p => p.child("hlinkClick")) is Some(right) else {
    return false
  }
  left.node.attributes.length() == right.node.attributes.length() &&
  left.node.attributes.all(a => {
    right.node.attributes.any(b => {
      a.uri == b.uri && a.name == b.name && a.value == b.value
    })
  })
}

///|
fn text_hyperlink_spans(
  object : Object,
  selection : Selection,
) -> Array[TextHyperlinkSpan] raise @failure.Failure {
  let spans : Array[TextHyperlinkSpan] = []
  let a = selection.anchor.min(selection.focus)
  let b = selection.anchor.max(selection.focus)
  if a == b {
    let (p, at) = paragraph_location(object, a)
    let paragraph = object.paragraphs[p]
    let (r, within) = caret_run(paragraph, at)
    let run = paragraph.runs[r]
    let span : TextHyperlinkSpan = {
      paragraph,
      run: if run.source is Some(_) {
        Some(run)
      } else {
        None
      },
      start: within,
      end: within,
    }
    let properties = span.properties()
    if properties.bind(p => p.child("hlinkClick")) is None || run.source is None {
      return [span]
    }
    let mut first = r
    let mut last = r
    while first > 0 &&
          same_text_hyperlink(
            properties,
            paragraph.runs[first - 1].source.bind(s => s.child("rPr")),
          ) {
      first -= 1
    }
    while last + 1 < paragraph.runs.length() &&
          same_text_hyperlink(
            properties,
            paragraph.runs[last + 1].source.bind(s => s.child("rPr")),
          ) {
      last += 1
    }
    for i in first..<=last {
      let run = paragraph.runs[i]
      spans.push({
        paragraph,
        run: Some(run),
        start: 0,
        end: run.text.length(),
      })
    }
    if last == paragraph.runs.length() - 1 &&
      same_text_hyperlink(properties, paragraph.source.child("endParaRPr")) {
      spans.push({ paragraph, run: None, start: 0, end: 0, })
    }
    return spans
  }
  let mut position = 0
  for paragraph in object.paragraphs {
    for run in paragraph.runs {
      let start = (a - position).max(0)
      let end = (b - position).min(run.text.length())
      if start < end || (run.text.is_empty() && a <= position && b > position) {
        spans.push({
          paragraph,
          run: if run.source is Some(_) {
            Some(run)
          } else {
            None
          },
          start,
          end,
        })
      }
      position += run.text.length()
    }
    // Keep the paragraph's typing properties from reviving a removed link.
    if paragraph_length(paragraph) > 0 &&
      ((a < position && b >= position) || (a <= position && b > position)) &&
      paragraph.source.child("endParaRPr").bind(p => p.child("hlinkClick"))
      is Some(_) {
      spans.push({ paragraph, run: None, start: 0, end: 0, })
    }
    position += 1
  }
  spans
}

///|
fn Session::text_hyperlink_query(
  self : Session,
  links : ReadOnlyArray[@opc.Relationship],
) -> Json {
  let unavailable = fn(reason : String) -> Json {
    { "value": Json::null(), "mixed": false, "reason": reason }
  }
  if self.selection.mode != "text" || self.selection.objects.length() != 1 {
    return unavailable("Select an editable text range")
  }
  try {
    let object = self.current().object(self.selection.object)
    let reason = self.formatting_reason(object)
    guard reason.is_empty() else { return unavailable(reason) }
    let spans = text_hyperlink_spans(object, self.selection)
    let values = spans.map(span => {
      self.read_hyperlink_at(span.properties(), object.source.tree.part, links)
    })
    let value = values.get(0).unwrap_or(None)
    let mixed = values.any(v => v != value)
    {
      "value": if mixed {
        Json::null()
      } else {
        value
        .map(pair => {
          let result : Json = { "kind": pair.0, "target": pair.1 }
          result
        })
        .unwrap_or(Json::null())
      },
      "mixed": mixed,
      "reason": "",
    }
  } catch {
    @failure.Failure(message~, ..) => unavailable(message)
  }
}

///|
fn Session::set_text_hyperlink(
  self : Session,
  kind : String,
  target : String,
) -> Json raise @failure.Failure {
  guard self.selection.mode == "text" && self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Hyperlink editing requires one selected text range",
    )
  }
  self.check_hyperlink_target(kind, target)
  let original = self.current()
  let object = original.object(self.selection.object)
  let reason = self.formatting_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let links = self.relationships()
  let spans = text_hyperlink_spans(object, self.selection)
  let values = spans.map(span => {
    self.read_hyperlink_at(span.properties(), original.tree.part, links)
  })
  let next = if kind == "none" { None } else { Some((kind, target)) }
  if values.all(value => value == next) {
    return self.query()
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let relation = if kind == "none" || kind == "action" {
    ""
  } else {
    self.hyperlink_relationship(
      original.tree.part,
      kind,
      target,
      links,
      parts,
      created,
      edits,
    )
  }
  let changes : Array[@xml.SourceChange] = []
  let mut units = 0
  for i, span in spans {
    if values[i] == next {
      continue
    }
    let node = span.properties().map(hyperlink_node).unwrap_or(None)
    let hyperlink = Some(hyperlink_markup(node, kind, relation, target~))
    let change : @xml.SourceChange = if span.run is Some(run) &&
      run.source is Some(source) {
      let markup = (if span.start > 0 {
          format_run(run, 0, span.start, None)
        } else {
          ""
        }) +
        format_run(run, span.start, span.end, None, hyperlink~) +
        (if span.end < run.text.length() {
          format_run(run, span.end, run.text.length(), None)
        } else {
          ""
        })
      {
        node: source.node.parent,
        offset: source.node.start - source.tree.nodes[source.node.parent].start,
        length: source.node.end - source.node.start,
        xml: markup,
      }
    } else {
      text_property_change(
        span.paragraph.source,
        "endParaRPr",
        None,
        hyperlink~,
      )
    }
    units += change.xml.length()
    guard units <= 2 * 1024 * 1024 else {
      @failure.reject("limit-exceeded", "Text hyperlink source exceeds budget")
    }
    changes.push(change)
  }
  let (document, edit) = original.tree.document.edit_source(changes)
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    index=self.index(original.tree.part),
    parts~,
  )
  let slides = self.slides.copy()
  slides[self.index(original.tree.part)] = candidate
  edits.push((original.tree.part, edit))
  self.commit_slides(
    self.main,
    slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
