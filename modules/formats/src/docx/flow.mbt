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
  let background = tree.page_background().unwrap_or("ffffff") catch {
      @failure.Failure(message~, ..) => {
        diagnostics.push("unsupported-layout:page-background:" + message)
        "ffffff"
      }
    }
  let mut styles = self.styles(diagnostics)
  let page_borders = tree.page_borders() catch {
    @failure.Failure(message~, ..) => {
      diagnostics.push("unsupported-layout:page-borders:" + message)
      @layout.PageBorders::new()
    }
  }
  let headers : Map[String, Array[@layout.Paragraph]] = Map([])
  let footers : Map[String, Array[@layout.Paragraph]] = Map([])
  let mut different_first = false
  let mut different_even = false
  let mut footer_distance = 0.0
  let mut header_distance = 0.0
  let mut page = default_page_setup()
  let mut page_numbering = @layout.PageNumbering::new()
  let mut columns = @layout.Columns::new()
  let body = tree.child(0, "body").unwrap()
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri {
      continue
    }
    if node.name == "sectPr" {
      columns = tree.page_columns(Some(id)) catch {
        @failure.Failure(message~, ..) => {
          diagnostics.push("unsupported-layout:columns:" + message)
          @layout.Columns::new()
        }
      }
      page_numbering = tree.page_numbering(Some(id)) catch {
        @failure.Failure(message~, ..) => {
          diagnostics.push("unsupported-layout:page-numbering:" + message)
          @layout.PageNumbering::new()
        }
      }
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
      footer_distance = tree
        .number(id, "pgMar", "footer")
        .map(v => v / 20)
        .unwrap_or(0)
      let (section_headers, section_footers) = self.running_content(
        tree, id, styles, diagnostics, background,
      )
      for key, paragraphs in section_headers {
        headers[key] = paragraphs
      }
      for key, paragraphs in section_footers {
        footers[key] = paragraphs
      }
      let (first, even) = self.running_options(tree, Some(id))
      different_first = first
      different_even = even
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
      "p" =>
        paragraphs.push(
          self.paragraph(tree, styles, id, diagnostics, background~),
        )
      "tbl" =>
        tables.push(
          self.table(
            tree,
            styles,
            id,
            paragraphs.length(),
            diagnostics,
            background~,
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
    backgrounds[p.id] = background
  }
  for table in tables {
    for row_index, row in table.rows {
      for cell_index, cell in row {
        let background = table.fills
          .get(row_index)
          .bind(row => row.get(cell_index))
          .filter(color => !color.is_empty())
          .unwrap_or(background)
        for p in cell {
          numbered[p.id] = p
          backgrounds[p.id] = background
        }
      }
    }
  }
  self.apply_numbering(tree, styles, numbered, backgrounds)
  styles.apply_contextual_spacing(tree, numbered)
  let outline_levels : Map[Int, Int] = Map([])
  for id, _ in numbered {
    let level = styles.outline_level(tree, id) catch {
      @failure.Failure(message~, ..) => {
        diagnostics.push("unsupported-layout:outline-level:" + message)
        None
      }
    }
    if level is Some(level) {
      outline_levels[id] = level
    }
  }
  {
    revision: self.revision,
    background,
    pageBorders: page_borders,
    page,
    pageNumbering: page_numbering,
    outlineLevels: outline_levels,
    bookmarks: Map::from_array(
      tree
      .bookmarks()
      .filter(b => b.reason.is_empty())
      .map(b => {
        let selection = b.selection.unwrap()
        (
          b.name.to_lower(),
          (
            selection.anchor.paragraph,
            selection.anchor.offset,
            selection.focus.paragraph,
            selection.focus.offset,
          ),
        )
      }),
    ),
    columns,
    paragraphs: paragraphs.map(p => numbered[p.id]),
    diagnostics,
    tables: tables.map(table => {
      ..table,
      rows: table.rows.map(row => row.map(cell => cell.map(p => numbered[p.id]))),
    }),
    headers,
    headerDistance: header_distance,
    footers,
    footerDistance: footer_distance,
    differentFirst: different_first,
    differentEven: different_even,
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
  running~ : Bool = false,
) -> @layout.Paragraph raise @failure.Failure {
  let diagnostics : Array[String] = []
  let has_fields = running ||
    tree
    .descendants(id)
    .any(item => {
      tree.nodes[item].uri == word_uri &&
      ["fldSimple", "fldChar", "instrText"].contains(tree.nodes[item].name)
    })
  let fields = if has_fields {
    tree.running_fields(id) catch {
      @failure.Failure(message~, ..) => {
        if running {
          @failure.reject("unsupported-layout", message)
        }
        diagnostics.push("unsupported-layout:" + message)
        Map([])
      }
    }
  } else {
    Map([])
  }
  guard !running ||
    !fields
    .values()
    .any(code => {
      code.has_prefix("PAGEREF:") ||
      code.has_prefix("SEQ:") ||
      code.has_prefix("REF:")
    }) else {
    @failure.reject(
      "unsupported-layout", "This field requires the main document story",
    )
  }
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
    if node.uri == math_uri && node.name == "oMath" {
      ()
    } else if node.uri == word_uri && node.name == "hyperlink" {
      tree.check_hyperlink(child) catch {
        @failure.Failure(message~, ..) =>
          diagnostics.push("unsupported-layout:" + message)
      }
    } else if tree.is_bookmark(child) {
      tree.check_bookmark_marker(child) catch {
        @failure.Failure(message~, ..) =>
          diagnostics.push("unsupported-layout:" + message)
      }
    } else if tree.is_comment_marker(child) {
      tree.check_comment_marker(child) catch {
        @failure.Failure(message~, ..) =>
          diagnostics.push("unsupported-layout:" + message)
      }
    } else if has_fields && node.uri == word_uri && node.name == "fldSimple" {
      ()
    } else if !running &&
      node.uri == word_uri &&
      ["ins", "del"].contains(node.name) {
      try tree.check_text_revision(child) catch {
        @failure.Failure(..) =>
          diagnostics.push("unsupported-layout:" + node.qualified)
      } noraise {
        _ => ()
      }
    } else if Some(child) != props && (node.uri != word_uri || node.name != "r") {
      diagnostics.push("unsupported-layout:" + node.qualified)
    }
  }
  for
    run in tree.paragraph_runs(
      id,
      running=has_fields,
      review=!running,
      math=true,
    ) {
    if tree.nodes[run].uri == math_uri {
      let style : @layout.TextStyle = {
        font: run_style.key(),
        size: run_style.size,
        color: run_style.text_color(background),
        underline: false,
        strike: false,
        highlight: "",
        script: "baseline",
        spacing: 0,
      }
      try self.read_math_fraction(tree, run, style) catch {
        @failure.Failure(code="limit-exceeded", ..) as error => raise error
        @failure.Failure(message~, ..) =>
          diagnostics.push("unsupported-layout:math:" + message)
      } noraise {
        frame =>
          spans.push({
            node: run,
            text: "\ufffc",
            style,
            drawing: Some(frame),
            field: "",
          })
      }
      continue
    }
    let base = styles.run_character_style(tree, run, run_style, diagnostics)
    let review = tree.nodes[tree.nodes[run].parent]
    let style = if review.uri == word_uri && review.name == "ins" {
      { ..base, underline: true, }
    } else if review.uri == word_uri && review.name == "del" {
      { ..base, strike: true, }
    } else {
      base
    }
    for content in tree.children[run] {
      let item = tree.nodes[content]
      if has_fields && ["fldChar", "instrText"].contains(item.name) {
        continue
      }
      if fields.get(content) == Some("") {
        continue
      }
      if item.uri != word_uri {
        diagnostics.push("unsupported-layout:" + item.qualified)
        continue
      }
      let image = if item.name == "drawing" {
        Some(self.drawing_frame(tree, content))
      } else {
        None
      }
      let text = match item.name {
        "t" => item.text
        "delText" if review.uri == word_uri && review.name == "del" => item.text
        "br" => inline_text(item).replace_all(old="\u2028", new="\n")
        "cr" => "\n"
        "tab" => "\t"
        "drawing" => "\ufffc"
        "rPr" | "lastRenderedPageBreak" => continue
        "commentReference" => {
          tree.check_comment_marker(content) catch {
            @failure.Failure(message~, ..) =>
              diagnostics.push("unsupported-layout:" + message)
          }
          continue
        }
        _ => {
          diagnostics.push("unsupported-layout:" + item.qualified)
          continue
        }
      }
      let field = fields.get(content).unwrap_or("")
      let runs = if field.is_empty() {
        style.font_runs(text, styles.themes)
      } else {
        style.font_runs("0", styles.themes).map(pair => (pair.0, text))
      }
      for (style, text) in runs {
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
            spacing: style.spacing,
          },
          drawing: image,
          field,
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
        spacing: run_style.spacing,
      },
      drawing: None,
      field: "",
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
  let picture_reason = if spans.any(span => span.drawing is Some(_)) {
    try {
      self.check_native_drawings(tree, id)
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
    readOnlyReason: diagnostics
    .get(0)
    .unwrap_or(
      if tree
        .descendants(id)
        .any(item => {
          tree.nodes[item].uri == word_uri &&
          revision_element(tree.nodes[item].name)
        }) {
        "Tracked revisions require review before editing"
      } else if !running && has_fields {
        try {
          tree.check_editable_paragraph(
            id,
            part=self.main,
            pictures=true,
            fields=true,
            math=true,
          )
          picture_reason
        } catch {
          @failure.Failure(..) => "Page fields require field editing"
        }
      } else {
        picture_reason
      },
    ),
  }
}
