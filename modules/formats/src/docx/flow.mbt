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
  let mut page = default_page_setup()
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
        let relation = for rel in self.relationships() {
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
      let source_page = tree.page_values(id, page)
      page = {
        ..source_page,
        width: tree
        .number(id, "pgSz", "w")
        .map(page_dimension)
        .unwrap_or(page.width),
        height: tree
        .number(id, "pgSz", "h")
        .map(page_dimension)
        .unwrap_or(page.height),
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
          self.table(
            tree,
            styles,
            id,
            paragraphs.length(),
            diagnostics,
            page.width - page.left - page.right,
          ),
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
  let numbered : Map[Int, @layout.Paragraph] = Map([])
  let backgrounds : Map[Int, String] = Map([])
  for p in paragraphs {
    numbered[p.id] = p
    backgrounds[p.id] = "ffffff"
  }
  for table in tables {
    for row_index, row in table.rows {
      for cell_index, cell in row {
        let background = table.fills
          .get(row_index)
          .bind(row => row.get(cell_index))
          .filter(color => !color.is_empty())
          .unwrap_or("ffffff")
        for p in cell {
          numbered[p.id] = p
          backgrounds[p.id] = background
        }
      }
    }
  }
  self.apply_numbering(tree, styles, numbered, backgrounds)
  {
    revision: self.revision,
    page,
    paragraphs: paragraphs.map(p => numbered[p.id]),
    diagnostics,
    tables: tables.map(table => {
      ..table,
      rows: table.rows.map(row => row.map(cell => cell.map(p => numbered[p.id]))),
    }),
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
  for child in tree.children[id] {
    let node = tree.nodes[child]
    if node.uri == word_uri && node.name == "hyperlink" {
      tree.check_hyperlink(child) catch {
        @failure.Failure(message~, ..) =>
          diagnostics.push("unsupported-layout:" + message)
      }
    } else if Some(child) != props && (node.uri != word_uri || node.name != "r") {
      diagnostics.push("unsupported-layout:" + node.qualified)
    }
  }
  for run in tree.paragraph_runs(id) {
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
      for (style, text) in style.font_runs(text, styles.themes) {
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
  }
  if spans.is_empty() {
    let run = match tree.paragraph_runs(id).get(0) {
      Some(run) => Some(run)
      None => props
    }
    if run is Some(run) {
      run_style = styles.run_character_style(tree, run, run_style, diagnostics)
    }
    run_style = run_style.font_runs("", styles.themes)[0].0
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
  let picture_reason = if spans.any(span => span.image is Some(_)) {
    try {
      self.check_native_pictures(tree, id)
      paragraph.readOnlyReason
    } catch {
      @failure.Failure(message~, ..) => message
    }
  } else {
    paragraph.readOnlyReason
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
    readOnlyReason: diagnostics.get(0).unwrap_or(picture_reason),
  }
}
