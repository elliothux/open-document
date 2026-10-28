///|
fn navigation_blocked(reason : String) -> Json {
  { "kind": "blocked", "page": "", "uri": "", "reason": reason }
}

///|
fn PdfSession::named_destination(
  self : PdfSession,
  key : String,
  tree : @syntax.PdfObject,
  depth : Int32,
) -> @syntax.PdfObject raise {
  @pdfcore.sdk_depth(depth)
  let node = resolve(self.document, tree)
  let names = get(self.document, node, "Names")
  if names is PdfArray(entries) {
    guard entries.length() % 2 == 0 else {
      @failure.reject("invalid-pdf", "Invalid PDF destination name tree")
    }
    for i = 0; i < entries.length(); i = i + 2 {
      if pdf_text_string(entries[i]) == key {
        return entries[i + 1]
      }
    }
  }
  if get(self.document, node, "Kids") is PdfArray(kids) {
    for child in kids {
      let found = self.named_destination(key, child, depth + 1)
      if found != @syntax.PdfNull {
        return found
      }
    }
  }
  @syntax.PdfNull
}

///|
fn PdfSession::navigation_target(
  self : PdfSession,
  object : @syntax.PdfObject,
) -> Json raise {
  let action = get(self.document, object, "A")
  let mut destination = raw(object, "Dest")
  if action != @syntax.PdfNull {
    if is_name(raw(action, "S"), "URI") {
      let uri = pdf_text_string(get(self.document, action, "URI"))
      let lower = uri.to_lower()
      if uri.length() <= 2048 &&
        ["https://", "http://", "mailto:"].any(prefix => {
          lower.has_prefix(prefix) && uri.length() > prefix.length()
        }) &&
        uri
        .iter()
        .all(c => {
          !c.is_whitespace() &&
          c.to_int() > 32 &&
          c.to_int() != 127 &&
          c != '\\'
        }) {
        return { "kind": "uri", "page": "", "uri": uri, "reason": "" }
      }
      return navigation_blocked("Unsafe or unsupported PDF URI")
    }
    if !is_name(raw(action, "S"), "GoTo") {
      return navigation_blocked("PDF action is not executed")
    }
    destination = raw(action, "D")
  }
  destination = resolve(self.document, destination)
  let key = match destination {
    PdfNameObject(name) => Some(@utf8.decode_lossy(name.bytes())[1:].to_owned())
    PdfString(_) => Some(pdf_text_string(destination))
    _ => None
  }
  if key is Some(key) {
    let catalog = resolve(
      self.document,
      @syntax.PdfIndirect(self.document.root()),
    )
    let old = get(self.document, catalog, "Dests")
    destination = raw(old, key)
    if destination == @syntax.PdfNull {
      destination = self.named_destination(
        key,
        get(self.document, get(self.document, catalog, "Names"), "Dests"),
        0,
      )
    }
    destination = resolve(self.document, destination)
  }
  if destination is PdfDictionary(_) {
    destination = get(self.document, destination, "D")
  }
  if destination is PdfArray([target, ..]) {
    for index, page in self.pages {
      if target == @syntax.PdfIndirect(page.number) ||
        target == @syntax.PdfInteger(index) {
        return { "kind": "page", "page": page.id, "uri": "", "reason": "" }
      }
    }
  }
  navigation_blocked("PDF destination is missing or unsupported")
}

///|
pub fn PdfSession::navigation(self : PdfSession) -> Json raise @failure.Failure {
  self.check(self.revision)
  pdf_bound(self.budget, () => {
    let outlines : Array[Json] = []
    let links : Array[Json] = []
    let seen : Map[Int32, Bool] = Map([])
    fn walk(reference : @syntax.PdfObject, level : Int32) -> Unit raise {
      @pdfcore.sdk_depth(level)
      let mut current = reference
      while current != @syntax.PdfNull {
        guard current is PdfIndirect(id) &&
          !seen.contains(id) &&
          seen.length() < 1024 else {
          @failure.reject(
            "limit-exceeded", "PDF outline is cyclic or exceeds budget",
          )
        }
        seen[id] = true
        let object = resolve(self.document, current)
        let title = pdf_text_string(get(self.document, object, "Title"))
        check_pdf_text(title)
        outlines.push({
          "id": "\{id}",
          "title": title,
          "level": level,
          "target": self.navigation_target(object),
        })
        walk(raw(object, "First"), level + 1)
        current = raw(object, "Next")
      }
    }
    let catalog = resolve(
      self.document,
      @syntax.PdfIndirect(self.document.root()),
    )
    walk(raw(get(self.document, catalog, "Outlines"), "First"), 0)
    for page in self.pages {
      for
        index, reference in annotation_refs(
          self.document,
          self.document.lookup_object_or_null(page.number),
        ) {
        let object = resolve(self.document, reference)
        if !is_name(raw(object, "Subtype"), "Link") {
          continue
        }
        guard links.length() < 4096 else {
          @failure.reject("limit-exceeded", "PDF links exceed budget")
        }
        let (x, y, r, t) = rectangle(get(self.document, object, "Rect"))
        let (a, b) = page.matrix.point(x, y)
        let (c, d) = page.matrix.point(r, t)
        links.push({
          "id": "\{page.id}:\{index}",
          "page": page.id,
          "x": a.min(c),
          "y": b.min(d),
          "width": (c - a).abs(),
          "height": (d - b).abs(),
          "target": self.navigation_target(object),
        })
      }
    }
    { "revision": self.revision, "outlines": outlines, "links": links }
  })
}
