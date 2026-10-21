///|
fn check_markup_mode(mode : String) -> Unit raise @failure.Failure {
  guard ["source", "merge", "text"].contains(mode) else {
    @failure.reject("invalid-operation", "Unknown markup paste mode")
  }
}

///|
fn Session::paste_markup_fragment(
  self : Session,
  revision : Int,
  selection : Selection,
  fragment : String,
  mode : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images?,
) -> Json raise @failure.Failure {
  check_markup_mode(mode)
  if mode == "source" {
    return self.paste_body_fragment(
      revision,
      selection,
      fragment,
      probe,
      profile,
      images~,
    )
  }
  if mode == "text" {
    // Import into local candidates only, so list counters resolve without creating native resources.
    let parts = self.parts.copy()
    let document = self.read_body_fragment(
      fragment,
      parts,
      Map([]),
      Map([]),
      self.media.copy(),
      Map([]),
    )
    let view = { ..self, parts, }
    let flow = view.flow_from(document)
    let text = markup_plain_text(flow)
    // Imports preflight the receiving layout before the ordinary text transaction commits.
    if self.prepare_range(selection, text) is Some(prepared) &&
      prepared.edit.bytes > 0 {
      ignore(
        @layout.paginate(
          probe,
          self.flow_from(prepared.document),
          profile,
          images.unwrap_or_else(() => @layout.Images::new()),
        ),
      )
    }
    return self.replace_range(revision, selection, text)
  }
  let original = self.document()
  let range = self.paragraph_range(
    WordTree::new(original),
    selection,
    structural=true,
    fields=true,
    tables=true,
  )
  let caret = { anchor: range.start, focus: range.start, }
  let selected = self.formatting_range(original, caret, fields=true)
  let (characters, _) = self.formatting_styles(
    WordTree::new(original),
    selected,
  )
  let base = characters[0]
  let paragraph = self.formatting_paragraphs(original, [range.start.paragraph])[0]
  let patch = ParagraphFormat::new(
    style=Clear,
    align=Set(paragraph.align),
    rtl=Set(paragraph.rtl),
    before=Set(paragraph.before),
    after=Set(paragraph.after),
    left=Set(paragraph.left),
    right=Set(paragraph.right),
    first=Set(paragraph.first),
    line=Set(paragraph.line),
    pageBreakBefore=Set(paragraph.pageBreakBefore),
    keepLines=Set(paragraph.keepLines),
    keepNext=Set(paragraph.keepNext),
    widowControl=Set(paragraph.widowControl),
  ).properties()
  let document = @xml.Document::parse(
    @utf8.encode(
      "<od:document xmlns:od=\"\{word_uri}\">" + fragment + "</od:document>",
    ),
    "markup-fragment",
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  let tree = WordTree::new(document)
  let styles = self.styles([])
  let changes : Array[@xml.SourceChange] = []
  for id in tree.order {
    let name = tree.nodes[id].name
    if tree.nodes[id].uri != word_uri {
      continue
    }
    let markup = if name == "p" {
      formatted_properties(
        tree,
        document,
        id,
        "pPr",
        patch,
        nested=Map([
          (
            "rPr",
            "<od:rPr>" +
            character_properties_markup(base.fragment_format()) +
            "</od:rPr>",
          ),
          ("tabs", tabs_markup([], paragraph.tabs)),
        ]),
      )
    } else if name == "r" {
      let source = styles.run_character_style(tree, id, base, [])
      let format = {
        ..source.fragment_format(),
        family: Set(base.family),
        size: Set(base.size),
        color: Set(base.color),
        spacing: Set(base.spacing),
        highlight: Set(base.highlight),
      }
      formatted_properties(tree, document, id, "rPr", format.properties())
    } else {
      continue
    }
    if properties_change(
        tree,
        document,
        id,
        if name == "p" {
          "pPr"
        } else {
          "rPr"
        },
        markup,
      )
      is Some(change) {
      changes.push(change)
    }
  }
  let candidate = if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
  let tree = WordTree::new(candidate)
  let body = tree.child(0, "body").unwrap()
  self.paste_body_fragment(
    revision,
    selection,
    tree.standalone_markup(candidate, body),
    probe,
    profile,
    images~,
  )
}

///|
fn markup_paragraph_text(p : @layout.Paragraph) -> String {
  p.marker
  .map(marker => {
    marker.text + (if marker.suffix == "nothing" { "" } else { "\t" })
  })
  .unwrap_or("") +
  p.spans.map(s => s.text).join("")
}

///|
fn markup_plain_text(flow : @layout.Flow) -> String {
  let lines : Array[String] = []
  for position in 0..<=flow.paragraphs.length() {
    for table in flow.tables {
      if table.beforeParagraph != position {
        continue
      }
      for r, row in table.rows {
        let values : Array[String] = []
        for c, paragraphs in row {
          let text = if table.rowSpans[r][c] == 0 {
            ""
          } else {
            paragraphs.map(markup_paragraph_text).join("\n")
          }
          values.push(@delimited.quote_field(text))
          for _ in 1..<table.columnSpans[r][c] {
            values.push("")
          }
        }
        lines.push(values.join("\t"))
      }
    }
    if flow.paragraphs.get(position) is Some(p) {
      lines.push(markup_paragraph_text(p))
    }
  }
  lines.join("\n")
}
