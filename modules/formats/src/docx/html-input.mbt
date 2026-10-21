///|
priv struct HtmlInput {
  output : MarkupInput
  document : @html5.Document
  mut open : Bool
  mut pendingSpace : Bool
  mut textStarted : Bool
  mut link : (String, String)?
  mut inTable : Bool
}

///|
fn html_ignored_element(tag : String) -> Bool {
  [
    "script", "style", "head", "meta", "link", "base", "title", "noscript", "iframe",
    "object", "embed", "template",
  ].contains(tag)
}

///|
fn HtmlInput::close_link(self : HtmlInput) -> Unit raise @failure.Failure {
  if self.link is Some(_) {
    self.output.add("</od:hyperlink>")
    self.link = None
  }
}

///|
fn HtmlInput::close_paragraph(self : HtmlInput) -> Unit raise @failure.Failure {
  self.close_link()
  if self.open {
    self.output.add("</od:p>")
    self.open = false
  }
  self.pendingSpace = false
  self.textStarted = false
}

///|
fn HtmlInput::paragraph(
  self : HtmlInput,
  context : HtmlContext,
) -> Unit raise @failure.Failure {
  if self.open {
    return
  }
  self.output.paragraphs += 1
  guard self.output.paragraphs <= 512 else {
    @failure.reject("limit-exceeded", "HTML exceeds paragraph budget")
  }
  self.output.add("<od:p><od:pPr>")
  if context.heading > 0 {
    self.output.add("<od:keepNext/>")
  }
  let number = if context.first.val { context.list } else { None }
  context.first.val = false
  self.output.add(
    number
    .map(pair => list_properties(pair.0, pair.1))
    .unwrap_or(list_properties(0, 0)),
  )
  self.output.add(
    "<od:bidi od:val=\"\{if context.rtl { "1" } else { "0" }}\"/>",
  )
  let left = context.quote * 360 +
    context.list.map(pair => (pair.1 + 1) * 720).unwrap_or(0)
  if left > 0 {
    self.output.add(
      "<od:ind od:left=\"\{left}\"" +
      (if number is Some(_) { " od:hanging=\"360\"" } else { "" }) +
      "/>",
    )
  }
  self.output.add("<od:jc od:val=\"\{context.align}\"/>")
  if context.heading > 0 {
    self.output.add("<od:outlineLvl od:val=\"\{context.heading - 1}\"/>")
  }
  self.output.add("</od:pPr>")
  self.open = true
}

///|
fn HtmlInput::content(
  self : HtmlInput,
  text : String,
  context : HtmlContext,
) -> Unit raise @failure.Failure {
  if text.is_empty() {
    return
  }
  self.paragraph(context)
  if self.link != context.link {
    self.close_link()
    if context.link is Some((target, title)) {
      self.output.link(target, title)
      self.link = context.link
    }
  }
  self.output.text(text, context.format)
}

///|
fn HtmlInput::text(
  self : HtmlInput,
  text : String,
  context : HtmlContext,
) -> Unit raise @failure.Failure {
  if context.preserve {
    if self.pendingSpace && self.textStarted {
      self.content(" ", context)
    }
    self.pendingSpace = false
    self.content(
      text
      .replace_all(old="\r\n", new="\n")
      .replace_all(old="\r", new="\n")
      .replace_all(old="\n", new="\u2028"),
      context,
    )
    self.textStarted = self.textStarted || !text.is_empty()
    return
  }
  let value = StringBuilder()
  for character in text {
    if [" ", "\t", "\n", "\r", "\u000c"].contains(character.to_string()) {
      self.pendingSpace = true
    } else {
      if self.pendingSpace && self.textStarted {
        value.write_string(" ")
      }
      self.pendingSpace = false
      self.textStarted = true
      value.write_char(character)
    }
  }
  self.content(value.to_string(), context)
}

///|
fn HtmlInput::walk(
  self : HtmlInput,
  id : Int,
  context : HtmlContext,
  depth : Int,
) -> Unit raise @failure.Failure {
  self.output.visit(depth)
  match self.document.get_node(id) {
    Some(TextNode(text)) => self.text(text, context)
    Some(ElementNode(element)) => {
      let tag = element.tag_name
      // Remove executable/metadata subtrees without interpreting their attributes or text.
      if html_ignored_element(tag) {
        return
      }
      guard element.ns is HTML &&
        [
          "html", "body", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote",
          "ul", "ol", "li", "pre", "span", "b", "strong", "i", "em", "u", "s", "strike",
          "del", "sup", "sub", "code", "a", "br", "img", "table",
        ].contains(tag) else {
        @failure.reject(
          "unsupported-input",
          "HTML element is not supported: " + tag,
        )
      }
      let mut context = html_style(self.document, id, context)
      if context.hidden || self.document.has_attribute(id, "hidden") {
        return
      }
      if tag == "table" {
        self.table(id, context, depth)
        return
      }
      if tag == "img" {
        self.paragraph(context)
        self.close_link()
        guard context.link is None || self.output.mode == "text" else {
          @failure.reject(
            "unsupported-input", "Linked HTML images require editing support",
          )
        }
        if self.pendingSpace && self.textStarted {
          self.content(" ", { ..context, link: None, })
        }
        let alt = self.document.get_attribute(id, "alt").unwrap_or("")
        self.output.image(
          self.document.get_attribute(id, "src").unwrap_or(""),
          alt,
          self.document.get_attribute(id, "title").unwrap_or(""),
          width?=html_picture_dimension(self.document, id, "width"),
          height?=html_picture_dimension(self.document, id, "height"),
        )
        self.pendingSpace = false
        self.textStarted = self.textStarted ||
          self.output.mode != "text" ||
          !alt.is_empty()
        return
      }
      if tag == "a" {
        if self.document.get_attribute(id, "href") is Some(target) {
          let target = target.trim().to_owned()
          check_hyperlink_target(target)
          guard !target.has_prefix("#") else {
            @failure.reject(
              "unsupported-input", "HTML local links require imported bookmarks",
            )
          }
          context = {
            ..context,
            link: Some(
              (target, self.document.get_attribute(id, "title").unwrap_or("")),
            ),
          }
        }
      }
      if tag == "br" {
        self.paragraph(context)
        self.close_link()
        self.output.add("<od:r><od:br/></od:r>")
        self.pendingSpace = false
        self.textStarted = false
        return
      }
      let block = [
        "div", "p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "ul", "ol",
        "li", "pre",
      ].contains(tag)
      if block {
        self.close_paragraph()
      }
      if tag == "blockquote" {
        context = { ..context, quote: context.quote + 1, }
      }
      if tag == "ul" || tag == "ol" {
        guard !self.document.has_attribute(id, "reversed") else {
          @failure.reject(
            "unsupported-input", "HTML reversed lists are not supported",
          )
        }
        let start = @string.parse_int(
          self.document.get_attribute(id, "start").unwrap_or("1"),
        ) catch {
          _ => @failure.reject("unsupported-input", "Invalid HTML list start")
        }
        guard start >= 1 && start <= 65536 else {
          @failure.reject("limit-exceeded", "HTML list start exceeds budget")
        }
        let number = self.output.number(
          context.level,
          start,
          if tag == "ul" {
            "bullet"
          } else {
            "decimal"
          },
        )
        context = {
          ..context,
          list: Some((number, context.level)),
          level: context.level + 1,
        }
      }
      if tag == "li" {
        guard context.list is Some(_) &&
          !self.document.has_attribute(id, "value") else {
          @failure.reject(
            "unsupported-input", "HTML list item requires an ordinary list counter",
          )
        }
        context = { ..context, first: Ref(true), }
      }
      let before = self.output.paragraphs
      for child in element.children {
        self.walk(child, context, depth + 1)
      }
      if block {
        if self.output.paragraphs == before &&
          ["p", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "li"].contains(tag) {
          self.paragraph(context)
        }
        self.close_paragraph()
      }
    }
    _ => ()
  }
}

///|
/// Imports declared HTML semantics without executing code or fetching external resources.
pub fn Session::paste_html(
  self : Session,
  revision : Int,
  selection : Selection,
  html : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images~ : @layout.Images? = None,
  mode~ : String = "source",
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  let fragment = self.html_fragment(html, mode)
  self.paste_markup_fragment(
    revision, selection, fragment, mode, probe, profile, images,
  )
}

///|
fn Session::html_fragment(
  self : Session,
  html : String,
  mode : String,
) -> String raise @failure.Failure {
  check_markup_mode(mode)
  guard !html.trim().is_empty() &&
    html.length() <= 65536 &&
    html.iter().filter(c => c == '<').count() <= 2048 else {
    @failure.reject("limit-exceeded", "HTML exceeds source or tag budget")
  }
  let document = @html5.parse(html)
  guard document.nodes.length() <= 4096 && document.body_element >= 0 else {
    @failure.reject("limit-exceeded", "HTML exceeds node budget")
  }
  let output = MarkupInput::new(
    self.opc.budget.entry_bytes.min(history_byte_limit / 2),
    mode~,
  )
  let input : HtmlInput = {
    output,
    document,
    open: false,
    pendingSpace: false,
    textStarted: false,
    link: None,
    inTable: false,
  }
  let context : HtmlContext = {
    format: CharacterFormat::new(),
    align: "left",
    rtl: false,
    preserve: false,
    hidden: false,
    quote: 0,
    level: 0,
    list: None,
    first: Ref(false),
    heading: 0,
    link: None,
  }
  input.walk(document.document_element, context, 0)
  input.close_paragraph()
  output.finish()
}
