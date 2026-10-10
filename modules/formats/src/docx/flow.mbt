///|
pub fn Session::flow(self : Session) -> @layout.Flow raise @failure.Failure {
  let tree = WordTree::new(self.document())
  let paragraphs : Array[@layout.Paragraph] = []
  let tables : Array[@layout.Table] = []
  let diagnostics : Array[String] = []
  let styles = self.styles(diagnostics)
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
  for id, node in tree.nodes {
    if node.uri != word_uri {
      continue
    }
    if node.name == "sectPr" {
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
        let header = WordTree::new(self.opc.xml(relation.target))
        guard header.nodes[0].name == "hdr" else {
          @failure.reject("invalid-docx", "Invalid header root")
        }
        // shortcut: only empty headers reserve space; render header content in a later phase.
        for item in header.nodes {
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
        for item, _ in header.nodes {
          header.diagnose_properties(item, relation.target, diagnostics)
        }
        for item in header.children[0] {
          guard header.nodes[item].name == "p" else {
            @failure.reject("unsupported-layout", "Header body is unsupported")
          }
          paragraphs.push(
            self.paragraph(header, styles, item, diagnostics, edits=false),
          )
        }
        headers.push(paragraphs)
      }
      if node.parent != body {
        diagnostics.push("unsupported-layout:multiple-sections")
      }
      page = {
        width: tree
        .number(id, "pgSz", "w")
        .map(v => v / 20)
        .unwrap_or(page.width),
        height: tree
        .number(id, "pgSz", "h")
        .map(v => v / 20)
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
      "tbl" => tables.push(self.table(tree, styles, id, diagnostics))
      "sectPr" => ()
      _ => diagnostics.push("unsupported-layout:" + node.qualified)
    }
  }
  for id, node in tree.nodes {
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
  diagnostics : Array[String],
  edits? : Bool = true,
  background? : String = "ffffff",
) -> @layout.Paragraph raise @failure.Failure {
  let props = tree.child(id, "pPr")
  let key = match props.bind(props => tree.value(props, "pStyle")) {
    Some(key) => Some(key)
    None => styles.default_paragraph
  }
  let mut paragraph = { ..styles.paragraph, id, }
  let mut run_style = styles.defaults
  if key is Some(key) && styles.tree is Some(style_tree) {
    for style in styles.chain(key, diagnostics) {
      if style_tree.child(style, "pPr") is Some(p) {
        paragraph = paragraph_properties(style_tree, p, paragraph)
      }
      if style_tree.child(style, "rPr") is Some(r) {
        run_style = run_properties(
          style_tree,
          r,
          run_style,
          styles.themes,
          inherited=true,
        )
      }
    }
  }
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
    let mut style = run_style
    if tree.child(run, "rPr") is Some(r) {
      if tree.value(r, "rStyle") is Some(key) && styles.tree is Some(style_tree) {
        for style_id in styles.chain(key, diagnostics) {
          if style_tree.child(style_id, "rPr") is Some(r) {
            style = run_properties(
              style_tree,
              r,
              style,
              styles.themes,
              inherited=true,
            )
          }
        }
      }
      style = run_properties(tree, r, style, styles.themes)
    }
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
        "t" =>
          if edits {
            self.replacements.get(content).unwrap_or(item.text)
          } else {
            item.text
          }
        "br" =>
          if item.attribute("type", uri=word_uri) == Some("page") {
            "\u000c"
          } else {
            "\n"
          }
        "cr" => "\n"
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
        },
        image,
      })
    }
  }
  if spans.is_empty() {
    if props.bind(props => tree.child(props, "rPr")) is Some(r) {
      run_style = run_properties(tree, r, run_style, styles.themes)
    }
    spans.push({
      node: id,
      text: "",
      style: {
        font: run_style.key(),
        size: run_style.size,
        color: run_style.text_color(background),
      },
      image: None,
    })
  }
  if paragraph.align != "left" &&
    paragraph.align != "center" &&
    paragraph.align != "right" {
    let message = "unsupported-layout:alignment-" + paragraph.align
    if !diagnostics.contains(message) {
      diagnostics.push(message)
    }
  }
  { ..paragraph, spans, }
}
