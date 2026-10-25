///|
fn Session::markup_note_labels(
  self : Session,
  flow : @layout.Flow,
  layout : @layout.Layout?,
) -> Map[Int, String] raise @failure.Failure {
  let labels : Map[Int, String] = Map([])
  if flow.notes.is_empty() {
    return labels
  }
  guard layout is Some(layout) && layout.revision == self.revision else {
    @failure.reject("stale-layout", "Note markup requires the current layout")
  }
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Note markup requires a complete layout",
    )
  }
  let keys = Map::from_array(
    flow.notes.map(note => ((note.paragraph, note.node), note.node)),
  )
  for page in layout.pages {
    for line in page.lines {
      if line.container < 0 {
        continue
      }
      for run in line.runs {
        for source in run.sources {
          if keys.get((line.paragraph, source.node)) is Some(node) {
            guard labels
              .get(node)
              .map(label => label == run.text)
              .unwrap_or(true) else {
              @failure.reject("unsupported-layout", "Note label is ambiguous")
            }
            labels[node] = run.text
          }
        }
      }
    }
  }
  guard labels.length() == keys.length() else {
    @failure.reject(
      "unsupported-layout", "Note reference position is unavailable",
    )
  }
  labels
}

///|
fn Session::markup_notes(
  self : Session,
  flow : @layout.Flow,
  styles : Styles,
  output : MarkupOutput,
) -> Unit raise @failure.Failure {
  for kind in ["footnote", "endnote"] {
    let notes = flow.notes.filter(note => note.kind == kind)
    if notes.is_empty() {
      continue
    }
    let source = self.note_source(kind).unwrap()
    let entries = Map::from_array(
      source.entries.map(entry => (entry.key, entry)),
    )
    let name = if kind == "footnote" { "Footnote" } else { "Endnote" }
    output.add(
      "\n<section aria-label=\"\{name}s\"><ol style=\"list-style:none;padding:0\">\n",
    )
    for note in notes {
      let entry = entries[note.key]
      guard entry.reason.is_empty() &&
        entry.paragraphs.length() == note.content.length() &&
        entry.paragraphs.all(id => {
          styles.numbering_reference(source.tree, id) is None
        }) else {
        @failure.reject(
          "unsupported-output", "Note markup requires supported ordinary note paragraphs",
        )
      }
      let label = output.fields[note.node]
      let target = "od-\{kind}-\{note.key}"
      output.add("<li id=\"\{target}\">\n")
      let inner = {
        ..output,
        builder: StringBuilder(),
        units: 0,
        limit: output.limit - output.units,
        markdown: false,
        fields: Map([]),
        lists: Map([]),
      }
      for index, paragraph in note.content {
        guard paragraph.readOnlyReason == "protected-content:note-area" else {
          @failure.reject("unsupported-output", "Unsupported note paragraph")
        }
        self.markup_paragraph(
          source.tree,
          styles,
          {
            ..paragraph,
            id: entry.paragraphs[index],
            container: 0,
            readOnlyReason: "",
            spans: paragraph.spans.map(span => {
              if source.tree.nodes[span.node].name == kind + "Ref" {
                { ..span, text: label, }
              } else {
                span
              }
            }),
          },
          inner,
          html=true,
        )
      }
      output.add(inner.builder.to_string())
      output.add(
        "<a href=\"#\{target}-ref\" aria-label=\"\{property_attribute("Back to " + name.to_lower() + " " + label)}\">↩</a></li>\n",
      )
    }
    output.add("</ol></section>\n\n")
  }
}
