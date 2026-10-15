///|
pub fn Session::flow(self : Session) -> @layout.Flow raise @failure.Failure {
  self.flow_from(self.display_document())
}

///|
fn Session::flow_from(
  self : Session,
  document : @xml.Document,
) -> @layout.Flow raise @failure.Failure {
  let tree = WordTree::new(document)
  let paragraphs : Array[@layout.Paragraph] = []
  let tables : Array[@layout.Table] = []
  let diagnostics : Array[String] = []
  let mut styles = self.styles(diagnostics)
  let headers : Array[Array[@layout.Paragraph]] = []
  let mut header_distance = 0.0
  let mut page : @layout.PageSetup = {
    width: 612,
    height: 792,
    top: 72,
    right: 72,
    bottom: 72,
    left: 72,
  }
  let body = tree.child(0, "body").unwrap()
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri {
      continue
    }
    if node.name == "sectPr" {
      let section_diagnostics : Array[String] = []
      tree.diagnose_properties(id, self.main, section_diagnostics)
      if node.parent != body {
        section_diagnostics.push("unsupported-layout:multiple-sections")
      }
      if section_diagnostics.get(0) is Some(reason) {
        styles = {
          ..styles,
          paragraph: { ..styles.paragraph, readOnlyReason: reason, },
        }
      }
      header_distance = tree
        .number(id, "pgMar", "header")
        .map(v => v / 20)
        .unwrap_or(0)
      for child in tree.children[id] {
        let reference = tree.nodes[child]
        if reference.name != "headerReference" {
          continue
        }
        let key = reference
          .attribute(
            "id",
            uri="http://schemas.openxmlformats.org/officeDocument/2006/relationships",
          )
          .unwrap_or("")
        let relation = for rel in self.opc.relationships() {
          if rel.owner == self.main &&
            rel.id == key &&
            rel.kind ==
            "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" {
            break rel
          }
        } nobreak {
          @failure.reject("invalid-docx", "Unresolved header relationship")
        }
        guard !relation.external else {
          @failure.reject(
            "unsupported-layout", "External headers are unsupported",
          )
        }
        let header = WordTree::new(self.part_xml(relation.target))
        guard header.nodes[0].name == "hdr" else {
          @failure.reject("invalid-docx", "Invalid header root")
        }
        // shortcut: only empty headers reserve space; render header content in a later phase.
        for id in header.order {
          let item = header.nodes[id]
          guard item.name != "t" || item.text.is_empty() else {
            @failure.reject(
              "unsupported-layout", "Header content is unsupported",
            )
          }
          guard item.name != "drawing" &&
            item.name != "tbl" &&
            item.name != "br" &&
            item.name != "fldChar" &&
            item.name != "instrText" else {
            @failure.reject(
              "unsupported-layout", "Header objects are unsupported",
            )
          }
        }
        let paragraphs : Array[@layout.Paragraph] = []
        for item in header.order {
          header.diagnose_properties(item, relation.target, diagnostics)
        }
        for item in header.children[0] {
          guard header.nodes[item].name == "p" else {
            @failure.reject("unsupported-layout", "Header body is unsupported")
          }
          paragraphs.push(self.paragraph(header, styles, item, diagnostics))
        }
        headers.push(paragraphs)
      }
      if node.parent != body {
        diagnostics.push("unsupported-layout:multiple-sections")
      }
      page = {
        width: tree
        .number(id, "pgSz", "w")
        .map(page_dimension)
        .unwrap_or(page.width),
        height: tree
        .number(id, "pgSz", "h")
        .map(page_dimension)
        .unwrap_or(page.height),
        top: tree
        .number(id, "pgMar", "top")
        .map(v => v / 20)
        .unwrap_or(page.top),
        right: tree
        .number(id, "pgMar", "right")
        .map(v => v / 20)
        .unwrap_or(page.right),
        bottom: tree
        .number(id, "pgMar", "bottom")
        .map(v => v / 20)
        .unwrap_or(page.bottom),
        left: tree
        .number(id, "pgMar", "left")
        .map(v => v / 20)
        .unwrap_or(page.left),
      }
    }
  }
  for id in tree.children[body] {
    let node = tree.nodes[id]
    if node.uri != word_uri {
      diagnostics.push("unsupported-layout:" + node.qualified)
      continue
    }
    match node.name {
      "p" => paragraphs.push(self.paragraph(tree, styles, id, diagnostics))
      "tbl" =>
        tables.push(
          self.table(tree, styles, id, paragraphs.length(), diagnostics),
        )
      "sectPr" => ()
      _ => diagnostics.push("unsupported-layout:" + node.qualified)
    }
  }
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri {
      continue
    }
    tree.diagnose_properties(id, self.main, diagnostics)
  }
  {
    revision: self.revision,
    page,
    paragraphs,
    diagnostics,
    tables,
    headers,
    headerDistance: header_distance,
    additiveSpacing: self.additive_spacing(),
  }
}

///|
fn Session::paragraph(
  self : Session,
  tree : WordTree,
  styles : Styles,
  id : Int,
  document_diagnostics : Array[String],
  background~ : String = "ffffff",
) -> @layout.Paragraph raise @failure.Failure {
  let diagnostics : Array[String] = []
  for item in tree.descendants(id) {
    tree.diagnose_properties(item, self.main, diagnostics)
  }
  let props = tree.child(id, "pPr")
  let mut paragraph = styles.paragraph_style(tree, id, diagnostics)
  let mut run_style = styles.character_style(tree, id, None, diagnostics)
  let nominal_size = run_style.size
  if props is Some(props) {
    paragraph = paragraph_properties(tree, props, paragraph)
  }
  let spans : Array[@layout.Span] = []
  for run in tree.children[id] {
    if tree.nodes[run].uri != word_uri || tree.nodes[run].name != "r" {
      if Some(run) != props {
        diagnostics.push("unsupported-layout:" + tree.nodes[run].qualified)
      }
      continue
    }
    let style = styles.run_character_style(tree, run, run_style, diagnostics)
    for content in tree.children[run] {
      let item = tree.nodes[content]
      if item.uri != word_uri {
        diagnostics.push("unsupported-layout:" + item.qualified)
        continue
      }
      let image = if item.name == "drawing" {
        Some(self.inline_image(tree, content))
      } else {
        None
      }
      let text = match item.name {
        "t" => item.text
        "br" =>
          if item.attribute("type", uri=word_uri) == Some("page") {
            "\u000c"
          } else {
            "\n"
          }
        "cr" => "\n"
        "tab" => "\t"
        "drawing" => "\ufffc"
        "rPr" | "lastRenderedPageBreak" => continue
        _ => {
          diagnostics.push("unsupported-layout:" + item.qualified)
          continue
        }
      }
      spans.push({
        node: content,
        text,
        style: {
          font: style.key(),
          size: style.size,
          color: style.text_color(background),
          underline: style.underline,
          strike: style.strike,
          highlight: highlight_color(style.highlight),
          script: style.vertAlign,
        },
        image,
      })
    }
  }
  if spans.is_empty() {
    let run = match tree.child(id, "r") {
      Some(run) => Some(run)
      None => props
    }
    if run is Some(run) {
      run_style = styles.run_character_style(tree, run, run_style, diagnostics)
    }
    spans.push({
      node: id,
      text: "",
      style: {
        font: run_style.key(),
        size: run_style.size,
        color: run_style.text_color(background),
        underline: run_style.underline,
        strike: run_style.strike,
        highlight: highlight_color(run_style.highlight),
        script: run_style.vertAlign,
      },
      image: None,
    })
  }
  if paragraph.align != "left" &&
    paragraph.align != "center" &&
    paragraph.align != "right" &&
    paragraph.align != "both" {
    let message = "unsupported-layout:alignment-" + paragraph.align
    if !diagnostics.contains(message) {
      diagnostics.push(message)
    }
  }
  for message in diagnostics {
    if !document_diagnostics.contains(message) {
      document_diagnostics.push(message)
    }
  }
  {
    ..paragraph,
    nominalSize: nominal_size,
    spans,
    container: if tree.nodes[id].parent >= 0 &&
      tree.nodes[tree.nodes[id].parent].name == "tc" &&
      tree.nodes[tree.nodes[id].parent].uri == word_uri {
      tree.nodes[id].parent
    } else {
      0
    },
    readOnlyReason: diagnostics.get(0).unwrap_or(paragraph.readOnlyReason),
  }
}
