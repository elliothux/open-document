///|
priv struct MarkupOutput {
  builder : StringBuilder
  limit : Int
  mut units : Int
  markdown : Bool
  links : Map[String, @opc.Relationship]
  bookmarks : Map[String, Bool]
  lists : Map[Int, MarkupList]
  background : String
}

///|
fn MarkupOutput::add(
  self : MarkupOutput,
  text : String,
) -> Unit raise @failure.Failure {
  guard text.length() <= self.limit - self.units else {
    @failure.reject("limit-exceeded", "Document markup exceeds output budget")
  }
  self.units += text.length()
  self.builder.write_string(text)
}

///|
fn markdown_text(text : String) -> String {
  let output = StringBuilder()
  for character in text {
    if "\\`*_{}[]()#+-.!|>~".contains(character.to_string()) {
      output.write_string("\\")
    }
    output.write_char(character)
  }
  output
  .to_string()
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old="\n", new="  \n")
}

///|
fn markup_css_string(text : String) -> String {
  "\"" +
  text
  .replace_all(old="\\", new="\\\\")
  .replace_all(old="\"", new="\\\"")
  .replace_all(old="\r", new="\\d ")
  .replace_all(old="\n", new="\\a ") +
  "\""
}

///|
fn markup_span(
  span : @layout.Span,
  markdown : Bool,
) -> String raise @failure.Failure {
  let markdown = markdown && span.style.spacing == 0
  let text = span.text
    .replace_all(old="\u000c", new="\n")
    .replace_all(old="\u000b", new="\n")
  let mut text = if markdown {
    markdown_text(text)
  } else {
    @xml.escape_text(text).replace_all(old="\n", new="<br />")
  }
  if span.style.font.contains("|bold") {
    text = "<strong>" + text + "</strong>"
  }
  if span.style.font.contains("|italic") {
    text = "<em>" + text + "</em>"
  }
  if span.style.underline {
    text = "<u>" + text + "</u>"
  }
  if span.style.strike {
    text = "<s>" + text + "</s>"
  }
  if span.style.script == "superscript" {
    text = "<sup>" + text + "</sup>"
  }
  if span.style.script == "subscript" {
    text = "<sub>" + text + "</sub>"
  }
  if markdown {
    return text
  }
  let family = span.style.font.split("|").to_array()[0].to_owned()
  let css = "font-family:" +
    markup_css_string(family) +
    ";font-size:" +
    span.style.size.to_string() +
    "pt;color:#" +
    span.style.color +
    (if span.style.spacing == 0 {
      ""
    } else {
      ";letter-spacing:" + span.style.spacing.to_string() + "pt"
    }) +
    (if span.style.highlight.is_empty() {
      ""
    } else {
      ";background-color:#" + span.style.highlight
    })
  "<span style=\"" + property_attribute(css) + "\">" + text + "</span>"
}

///|
fn Session::markup_picture(
  self : Session,
  tree : WordTree,
  span : @layout.Span,
  output : MarkupOutput,
) -> String raise @failure.Failure {
  tree.check_fragment_picture(span.node)
  let image = self.image_frame(tree, span.node)
  let bytes = self.image_bytes(image.key)
  let (_, mime, _, _) = @image.type_info(bytes)
  guard bytes.length().to_int64() * 4 / 3 + 1024 <=
    (output.limit - output.units).to_int64() else {
    @failure.reject("limit-exceeded", "Embedded picture exceeds markup budget")
  }
  let metadata = tree
    .descendants(span.node)
    .iter()
    .find_first(id => tree.nodes[id].name == "docPr")
  let alt = metadata.bind(id => tree.nodes[id].attribute("descr")).unwrap_or("")
  let width = image.width / (1 - image.crop[0] - image.crop[2])
  let height = image.height / (1 - image.crop[1] - image.crop[3])
  let css = "display:inline-block;position:relative;overflow:hidden;vertical-align:middle;width:" +
    image.width.to_string() +
    "pt;height:" +
    image.height.to_string() +
    "pt"
  let inner = "position:absolute;max-width:none;width:" +
    width.to_string() +
    "pt;height:" +
    height.to_string() +
    "pt;left:" +
    (-image.crop[0] * width).to_string() +
    "pt;top:" +
    (-image.crop[1] * height).to_string() +
    "pt"
  "<span style=\"" +
  css +
  "\"><img alt=\"" +
  property_attribute(alt) +
  "\" src=\"data:" +
  mime +
  ";base64," +
  @base64.encode(bytes) +
  "\" style=\"" +
  inner +
  "\" /></span>"
}

///|
fn Session::markup_paragraph(
  self : Session,
  tree : WordTree,
  styles : Styles,
  paragraph : @layout.Paragraph,
  output : MarkupOutput,
  html~ : Bool = false,
  listed~ : Bool = false,
) -> Unit raise @failure.Failure {
  guard paragraph.readOnlyReason.is_empty() else {
    @failure.reject(
      "unsupported-output", "Markup export requires supported ordinary paragraphs",
    )
  }
  let markdown = output.markdown && !html
  let outline = styles.outline_level(tree, paragraph.id)
  let heading = outline.filter(level => level < 6).map(level => level + 1)
  let tag = heading.map(level => "h" + level.to_string()).unwrap_or("p")
  if markdown {
    if heading is Some(level) {
      output.add("#".repeat(level) + " ")
    }
  } else {
    let align = if paragraph.align == "both" {
      "justify"
    } else {
      paragraph.align
    }
    let css = "white-space:pre-wrap;font-weight:normal;font-style:normal;font-size:" +
      paragraph.nominalSize.to_string() +
      "pt;text-align:" +
      align +
      ";margin-top:" +
      paragraph.before.to_string() +
      "pt;margin-bottom:" +
      paragraph.after.to_string() +
      "pt;margin-left:" +
      (if listed { 0.0 } else { paragraph.left }).to_string() +
      "pt;margin-right:" +
      paragraph.right.to_string() +
      "pt;text-indent:" +
      (if listed { 0.0 } else { paragraph.first }).to_string() +
      "pt"
    output.add(
      "<" +
      tag +
      " dir=\"" +
      (if paragraph.rtl { "rtl" } else { "ltr" }) +
      "\" style=\"" +
      css +
      "\">",
    )
  }
  if paragraph.marker is Some(marker) {
    if !listed || (!markdown && !output.lists[paragraph.id].native) {
      let suffix = match marker.suffix {
        "nothing" => ""
        "tab" => "\t"
        _ => " "
      }
      output.add(
        markup_span(
          {
            node: paragraph.id,
            text: marker.text + suffix,
            style: marker.style,
            drawing: None,
            field: "",
          },
          markdown,
        ),
      )
    }
  }
  let spans : Map[Int, Array[@layout.Span]] = Map([])
  for span in paragraph.spans {
    spans.get_or_init(span.node, () => []).push(span)
  }
  for id in tree.descendants(paragraph.id) {
    if tree.nodes[id].name == "bookmarkStart" && tree.is_bookmark(id) {
      tree.check_bookmark_marker(id)
      let name = tree.nodes[id].attribute("name", uri=word_uri).unwrap()
      output.add("<a id=\"" + property_attribute(name) + "\"></a>")
    }
    if spans.get(id) is Some(items) {
      for span in items {
        if span.text.is_empty() {
          continue
        }
        let content = if span.drawing is Some(_) {
          self.markup_picture(tree, span, output)
        } else {
          markup_span(span, markdown)
        }
        let run = tree.nodes[id].parent
        if tree.nodes[id].name != "p" && tree.run_hyperlink(run) is Some(link) {
          tree.check_hyperlink(link)
          let target = hyperlink_target(
            tree,
            run,
            output.links,
            output.bookmarks,
          ).unwrap()
          check_hyperlink_target(target)
          let title = tree.nodes[link]
            .attribute("tooltip", uri=word_uri)
            .unwrap_or("")
          output.add(
            "<a href=\"" +
            property_attribute(target) +
            "\" title=\"" +
            property_attribute(title) +
            "\">" +
            content +
            "</a>",
          )
        } else {
          output.add(content)
        }
      }
    }
  }
  if !markdown && paragraph.spans.all(span => span.text.is_empty()) {
    output.add("<br />")
  }
  output.add(if markdown { "\n\n" } else { "</" + tag + ">\n" })
}

///|
fn Session::markup_table(
  self : Session,
  tree : WordTree,
  styles : Styles,
  table : @layout.Table,
  output : MarkupOutput,
) -> Unit raise @failure.Failure {
  // Markdown retains native merged-cell structure as an HTML table.
  let alignment = if table.align == "center" {
    ";margin-left:auto;margin-right:auto"
  } else if table.align == "right" {
    ";margin-left:auto"
  } else {
    ""
  }
  output.add(
    "<table style=\"border-collapse:collapse;background-color:#" +
    output.background +
    alignment +
    "\"><colgroup>",
  )
  for width in table.widths {
    output.add("<col style=\"width:" + width.to_string() + "pt\" />")
  }
  output.add("</colgroup><tbody>\n")
  for row_index, row in table.rows {
    output.add("<tr>")
    for column, paragraphs in row {
      let rows = table.rowSpans[row_index][column]
      if rows == 0 {
        continue
      }
      let columns = table.columnSpans[row_index][column]
      let fill = table.fills[row_index][column]
      let mut css = "vertical-align:" +
        (if table.verticalAligns[row_index][column] == "center" {
          "middle"
        } else {
          table.verticalAligns[row_index][column]
        }) +
        (if fill.is_empty() { "" } else { ";background-color:#" + fill })
      let margin = table.margins[row_index][column]
      css += ";padding:" +
        margin.top.to_string() +
        "pt " +
        margin.right.to_string() +
        "pt " +
        margin.bottom.to_string() +
        "pt " +
        margin.left.to_string() +
        "pt"
      let borders = cell_border_query(table, row_index, column)
      for side in ["top", "right", "bottom", "left"] {
        guard borders[side]
          is { "width": Number(width, ..), "color": String(color), .. } else {
          @failure.reject(
            "unsupported-output", "Markup requires uniform merged-cell borders",
          )
        }
        css += ";border-" +
          side +
          ":" +
          width.to_string() +
          "pt solid #" +
          color
      }
      let tag = if row_index < table.headerRows { "th" } else { "td" }
      output.add(
        "<" +
        tag +
        " rowspan=\"" +
        rows.to_string() +
        "\" colspan=\"" +
        columns.to_string() +
        "\" style=\"" +
        css +
        "\">",
      )
      self.markup_paragraphs(tree, styles, paragraphs, output, html=true)
      output.add("</" + tag + ">")
    }
    output.add("</tr>\n")
  }
  output.add("</tbody></table>\n\n")
}

///|
/// Exports semantic body content without modifying native source or edit history.
pub fn Session::export_markup(
  self : Session,
  revision : Int,
  format : String,
  output_bytes : Int,
) -> Bytes raise @failure.Failure {
  self.check_revision(revision)
  guard ["html", "markdown"].contains(format) &&
    output_bytes > 0 &&
    output_bytes <= 67108864 else {
    @failure.reject(
      "invalid-operation", "Invalid markup format or output budget",
    )
  }
  let tree = WordTree::new(self.document())
  let flow = self.flow()
  guard flow.diagnostics.is_empty() &&
    flow.headers.is_empty() &&
    flow.footers.is_empty() &&
    !tree.order.any(id => {
      tree.is_comment_marker(id) || revision_element(tree.nodes[id].name)
    }) else {
    @failure.reject(
      "unsupported-output", "Markup export requires supported body content without running areas or review identities",
    )
  }
  let styles = self.styles([])
  let output : MarkupOutput = {
    builder: StringBuilder(),
    limit: output_bytes.min(self.opc.budget.output_bytes),
    units: 0,
    markdown: format == "markdown",
    links: self.hyperlink_relationships(),
    bookmarks: tree.bookmark_targets(),
    lists: self.markup_lists(tree, styles, flow),
    background: flow.background,
  }
  if !output.markdown {
    output.add(
      "<!doctype html>\n<html><head><meta charset=\"utf-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" /><title>Document</title></head><body style=\"background-color:#" +
      flow.background +
      "\">\n",
    )
  }
  let tables : Map[Int, Array[@layout.Table]] = Map([])
  for table in flow.tables {
    tables.get_or_init(table.beforeParagraph, () => []).push(table)
  }
  let mut start = 0
  for index in 0..<=flow.paragraphs.length() {
    if tables.get(index) is Some(current) {
      self.markup_paragraphs(
        tree,
        styles,
        flow.paragraphs[start:index].to_owned(),
        output,
      )
      for table in current {
        self.markup_table(tree, styles, table, output)
      }
      start = index
    }
  }
  self.markup_paragraphs(
    tree,
    styles,
    flow.paragraphs[start:].to_owned(),
    output,
  )
  if !output.markdown {
    output.add("</body></html>\n")
  }
  let bytes = @utf8.encode(output.builder.to_string())
  guard bytes.length() <= output.limit else {
    @failure.reject("limit-exceeded", "UTF-8 markup exceeds output budget")
  }
  bytes
}
