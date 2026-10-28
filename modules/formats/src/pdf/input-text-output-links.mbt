///|
priv struct PdfOutputLink {
  x : Double
  y : Double
  right : Double
  bottom : Double
  href : String
  label : String
}

///|
fn output_attribute(value : String) -> String raise @failure.Failure {
  @xml.escape_text(value)
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&#39;")
}

///|
fn PdfSession::output_links(
  self : PdfSession,
  id : String,
  ids : Array[String],
  warnings : Array[String],
  index : Int32,
) -> Array[PdfOutputLink] raise {
  let page = self.page(id)
  let links : Array[PdfOutputLink] = []
  for
    reference in annotation_refs(
      self.document,
      self.document.lookup_object_or_null(page.number),
    ) {
    let object = resolve(self.document, reference)
    if !is_name(raw(object, "Subtype"), "Link") {
      continue
    }
    guard links.length() < 4096 else {
      @failure.reject("limit-exceeded", "PDF output links exceed budget")
    }
    let target = self.navigation_target(object)
    let (href, label) = match target {
      { "kind": String("uri"), "uri": String(uri), .. } => (uri, uri)
      { "kind": String("page"), "page": String(target), .. } => {
        let mut position = -1
        for i, id in ids {
          if id == target {
            position = i
          }
        }
        if position < 0 {
          read_warning(
            warnings,
            "Page \{index}: a link to an unselected page was omitted",
          )
          continue
        }
        ("#pdf-page-\{position + 1}", "Page \{position + 1}")
      }
      _ => {
        read_warning(
          warnings,
          "Page \{index}: an unsafe or unsupported link was omitted",
        )
        continue
      }
    }
    let (x, y, r, b) = rectangle(get(self.document, object, "Rect"))
    let (a, c) = page.matrix.point(x, y)
    let (d, e) = page.matrix.point(r, b)
    links.push({
      x: a.min(d),
      y: c.min(e),
      right: a.max(d),
      bottom: c.max(e),
      href,
      label,
    })
  }
  links
}

///|
fn output_line(
  line : PdfReadLine,
  text : String,
  links : Array[PdfOutputLink],
  used : Map[Int32, Bool],
  markdown : Bool,
) -> String raise @failure.Failure {
  let escaped = if markdown {
    markdown_text(text)
  } else {
    @xml.escape_text(text)
  }
  for index, link in links {
    if line.rotation.abs() < 0.01 &&
      line.x >= link.x - 1 &&
      line.x + line.width <= link.right + 1 &&
      line.y >= link.y - 2 &&
      line.y + line.height <= link.bottom + 2 {
      used[index] = true
      // Safe HTML links also work inside Markdown without ambiguous URL delimiters.
      return "<a href=\"\{output_attribute(link.href)}\">\{@xml.escape_text(text)}</a>"
    }
  }
  escaped
}

///|
fn output_list_marker(text : String) -> (String, String, Int32) {
  for prefix in ["• ", "- ", "* "] {
    if text.has_prefix(prefix) && text.length() > prefix.length() {
      return ("ul", text[prefix.length():].to_owned(), 0)
    }
  }
  let mut offset = 0
  let mut number = 0
  while offset < text.length() &&
        offset < 4 &&
        text[offset] >= '0' &&
        text[offset] <= '9' {
    number = number * 10 + text[offset].to_int() - 48
    offset += 1
  }
  if offset > 0 &&
    number > 0 &&
    offset + 2 < text.length() &&
    (text[offset] == '.' || text[offset] == ')') &&
    text[offset + 1] == ' ' {
    ("ol", text[offset + 2:].to_owned(), number)
  } else {
    ("", text, 0)
  }
}
