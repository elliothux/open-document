///|
priv struct MarkupInput {
  output : StringBuilder
  definitions : Array[(String, String)]
  defs : Map[String, @cmark.LabelDef]
  limit : Int
  mode : String
  mut units : Int
  mut nodes : Int
  mut paragraphs : Int
  // Resource preflight has no target; resolve receiving geometry only during paste.
  available : () -> (Double, Double) raise @failure.Failure
  mut area : (Double, Double)?
  mut drawings : Int
  mut afterRule : Bool
  mut pictureBytes : Int
}

///|
fn MarkupInput::new(
  limit : Int,
  defs~ : Map[String, @cmark.LabelDef] = Map([]),
  mode~ : String = "source",
  available~ : () -> (Double, Double) raise @failure.Failure = () => (14400, 0),
) -> MarkupInput raise @failure.Failure {
  let input : MarkupInput = {
    output: StringBuilder(),
    definitions: [],
    defs,
    limit,
    mode,
    units: 0,
    nodes: 0,
    paragraphs: 0,
    available,
    area: None,
    drawings: 0,
    afterRule: false,
    pictureBytes: 0,
  }
  input.add("<od:body>")
  input
}

///|
fn MarkupInput::number(
  self : MarkupInput,
  level : Int,
  start : Int,
  format : String,
) -> Int raise @failure.Failure {
  guard level < 9 && self.definitions.length() < 256 else {
    @failure.reject("limit-exceeded", "Markup exceeds list budget")
  }
  let id = self.definitions.length() + 1
  let text = if format == "bullet" {
    "•"
  } else {
    "%" + (level + 1).to_string() + "."
  }
  self.definitions.push(
    (
      "<od:abstractNum od:abstractNumId=\"\{id}\"><od:lvl od:ilvl=\"\{level}\"><od:start od:val=\"\{start}\"/><od:numFmt od:val=\"\{format}\"/><od:lvlText od:val=\"\{text}\"/><od:lvlJc od:val=\"left\"/></od:lvl></od:abstractNum>",
      "<od:num od:numId=\"\{id}\"><od:abstractNumId od:val=\"\{id}\"/></od:num>",
    ),
  )
  id
}

///|
fn MarkupInput::finish(self : MarkupInput) -> String raise @failure.Failure {
  guard self.paragraphs > 0 else {
    @failure.reject("unsupported-input", "Markup has no editable content")
  }
  if self.afterRule {
    self.add("<od:p/>")
  }
  if !self.definitions.is_empty() {
    self.add(
      "<odClip:numbering xmlns:odClip=\"\{table_fragment_uri}\"><od:numbering>",
    )
    for definition in self.definitions {
      self.add(definition.0)
    }
    for definition in self.definitions {
      self.add(definition.1)
    }
    self.add("</od:numbering></odClip:numbering>")
  }
  self.add("</od:body>")
  self.output.to_string()
}

///|
fn MarkupInput::add(
  self : MarkupInput,
  value : String,
) -> Unit raise @failure.Failure {
  guard value.length() <= self.limit - self.units else {
    @failure.reject("limit-exceeded", "Markup fragment exceeds source budget")
  }
  self.units += value.length()
  self.output.write_string(value)
}

///|
fn MarkupInput::visit(
  self : MarkupInput,
  depth : Int,
) -> Unit raise @failure.Failure {
  self.nodes += 1
  guard depth <= 32 && self.nodes <= 4096 else {
    @failure.reject("limit-exceeded", "Markup exceeds nesting or node budget")
  }
}

///|
fn MarkupInput::text(
  self : MarkupInput,
  value : String,
  format : CharacterFormat,
) -> Unit raise @failure.Failure {
  if !value.is_empty() {
    let properties = character_properties_markup(format)
    self.add(
      "<od:r>" +
      (if properties.is_empty() {
        ""
      } else {
        "<od:rPr>" + properties + "</od:rPr>"
      }) +
      inline_markup(value, self.limit) +
      "</od:r>",
    )
  }
}

///|
fn MarkupInput::inline(
  self : MarkupInput,
  value : @cmark.Inline,
  depth : Int,
  format : CharacterFormat,
) -> Unit raise @failure.Failure {
  self.visit(depth)
  match value {
    Text(node) => self.text(node.v, format)
    Inlines(node) =>
      for child in node.v.iter() {
        self.inline(child, depth + 1, format)
      }
    Emphasis(node) =>
      self.inline(node.v.inline, depth + 1, { ..format, italic: Set(true), })
    StrongEmphasis(node) =>
      self.inline(node.v.inline, depth + 1, { ..format, bold: Set(true), })
    CodeSpan(node) =>
      self.text(node.v.code(), { ..format, family: Set("Courier New"), })
    Break(node) =>
      if node.v.ty == @cmark.Soft {
        self.text(" ", format)
      } else {
        self.add("<od:r><od:br/></od:r>")
      }
    Link(node) => {
      guard node.v.reference_definition(self.defs) is Some(LinkDef(definition)) &&
        definition.v.dest is Some(target) else {
        @failure.reject("invalid-operation", "Markdown link has no destination")
      }
      self.link(
        target.v,
        definition.v.title
        .map(lines => lines.iter().map(line => line.node.v).collect().join(" "))
        .unwrap_or(""),
      )
      self.inline(node.v.text, depth + 1, format)
      self.add("</od:hyperlink>")
    }
    Autolink(node) => {
      self.link(
        (if node.v.is_email { "mailto:" } else { "" }) + node.v.link.v,
        "",
      )
      self.text(node.v.link.v, format)
      self.add("</od:hyperlink>")
    }
    Image(node) => {
      guard node.v.reference_definition(self.defs) is Some(LinkDef(definition)) &&
        definition.v.dest is Some(target) else {
        @failure.reject("invalid-image", "Markdown image has no source")
      }
      let alt = node.v.text
        .to_plain_text(break_on_soft=false)
        .iter()
        .map(parts => parts.iter().collect().join(""))
        .collect()
        .join(" ")
      self.image(
        target.v,
        alt,
        definition.v.title
        .map(lines => lines.iter().map(line => line.node.v).collect().join(" "))
        .unwrap_or(""),
      )
    }
    // shortcut: reject embedded HTML until the CommonMark importer can preserve mixed block boundaries.
    RawHtml(_) | ExtStrikethrough(_) | ExtMathSpan(_) =>
      @failure.reject(
        "unsupported-input", "Markdown embedded HTML and extensions require a supported import path",
      )
  }
}

///|
fn MarkupInput::link(
  self : MarkupInput,
  target : String,
  title : String,
) -> Unit raise @failure.Failure {
  check_hyperlink_target(target)
  guard !target.has_prefix("#") else {
    @failure.reject(
      "unsupported-input", "Markdown local links require imported bookmarks",
    )
  }
  self.add(
    "<od:hyperlink xmlns:odClip=\"\{table_fragment_uri}\" odClip:target=\"\{property_attribute(target)}\" od:tooltip=\"\{property_attribute(title)}\">",
  )
}

///|
fn MarkupInput::paragraph(
  self : MarkupInput,
  content : @cmark.Inline,
  depth : Int,
  quote : Int,
  list : (Int, Int)?,
  first : Ref[Bool],
  heading~ : Int = 0,
  code~ : Bool = false,
) -> Unit raise @failure.Failure {
  self.afterRule = false
  self.paragraphs += 1
  guard self.paragraphs <= 512 else {
    @failure.reject("limit-exceeded", "Markdown exceeds paragraph budget")
  }
  let number = if first.val { list } else { None }
  first.val = false
  self.add("<od:p><od:pPr>")
  if heading > 0 {
    self.add("<od:keepNext/>")
  }
  self.add(
    number
    .map(pair => list_properties(pair.0, pair.1))
    .unwrap_or(list_properties(0, 0)),
  )
  let left = quote * 360 + list.map(pair => (pair.1 + 1) * 720).unwrap_or(0)
  if left != 0 {
    self.add(
      "<od:ind od:left=\"\{left}\"" +
      (if number is Some(_) { " od:hanging=\"360\"" } else { "" }) +
      "/>",
    )
  }
  if heading > 0 {
    self.add("<od:outlineLvl od:val=\"\{heading - 1}\"/>")
  }
  self.add("</od:pPr>")
  self.inline(
    content,
    depth + 1,
    if code {
      CharacterFormat::new(family=Set("Courier New"))
    } else if heading > 0 {
      CharacterFormat::new(bold=Set(true))
    } else {
      CharacterFormat::new()
    },
  )
  self.add("</od:p>")
}

///|
fn MarkupInput::block(
  self : MarkupInput,
  value : @cmark.Block,
  depth : Int,
  quote : Int,
  level : Int,
  list : (Int, Int)?,
  first : Ref[Bool],
) -> Unit raise @failure.Failure {
  self.visit(depth)
  match value {
    BlankLine(_) | LinkRefDefinition(_) => ()
    Blocks(node) =>
      for child in node.v.iter() {
        self.block(child, depth + 1, quote, level, list, first)
      }
    Paragraph(node) => self.paragraph(node.v.inline, depth, quote, list, first)
    Heading(node) =>
      self.paragraph(
        node.v.inline,
        depth,
        quote,
        list,
        first,
        heading=node.v.level,
      )
    BlockQuote(node) =>
      self.block(node.v.block, depth + 1, quote + 1, level, list, first)
    List(node) => {
      let (start, format) = match node.v.ty {
        @cmark_base.Unordered(_) => (1, "bullet")
        @cmark_base.Ordered(start, _) => (start, "decimal")
      }
      let id = self.number(level, start, format)
      for item in node.v.items.iter() {
        self.block(
          item.v.block,
          depth + 1,
          quote,
          level + 1,
          Some((id, level)),
          Ref(true),
        )
      }
    }
    CodeBlock(node) => {
      let text = node.v.code.iter().map(line => line.v).collect().join("\u2028")
      // Soft breaks preserve code lines in a single editable paragraph.
      let content = @cmark.Text(@cmark.Node::new(text))
      self.paragraph(content, depth, quote, list, first, code=true)
    }
    ThematicBreak(_) =>
      self.rule(quote * 18 + list.map(pair => (pair.1 + 1) * 36).unwrap_or(0))
    HtmlBlock(_) | ExtMathBlock(_) | ExtTable(_) | ExtFootnoteDefinition(_) =>
      @failure.reject(
        "unsupported-input", "Markdown embedded HTML and extensions require a supported import path",
      )
  }
}

///|
/// Imports CommonMark text through the existing bounded native fragment transaction.
pub fn Session::paste_markdown(
  self : Session,
  revision : Int,
  selection : Selection,
  markdown : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images~ : @layout.Images? = None,
  mode~ : String = "source",
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  let fragment = self.markdown_fragment(markdown, mode, available=() => {
    self.markup_area(selection, mode, probe, profile, images)
  })
  self.paste_markup_fragment(
    revision, selection, fragment, mode, probe, profile, images,
  )
}

///|
fn Session::markdown_fragment(
  self : Session,
  markdown : String,
  mode : String,
  available~ : () -> (Double, Double) raise @failure.Failure = () => (14400, 0),
) -> String raise @failure.Failure {
  check_markup_mode(mode)
  guard !markdown.trim().is_empty() && markdown.length() <= 65536 else {
    @failure.reject("limit-exceeded", "Markdown requires 1..65536 source units")
  }
  // Bound parser work before building its AST, including adversarial delimiter nesting.
  guard markdown.iter().filter(c => "[]()*_>`".contains(c.to_string())).count() <=
    1024 else {
    @failure.reject("limit-exceeded", "Markdown exceeds syntax budget")
  }
  let doc = @cmark.Doc::from_string(markdown, strict=true)
  let input = MarkupInput::new(
    self.opc.budget.entry_bytes.min(history_byte_limit / 2),
    defs=doc.defs,
    mode~,
    available~,
  )
  input.block(doc.block, 0, 0, 0, None, Ref(false))
  input.finish()
}
