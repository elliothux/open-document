///|
fn optional_view_intent(
  document : @pdflite.PdfDocument,
  value : @syntax.PdfObject,
) -> Bool raise @failure.Failure {
  let value = resolve(document, value)
  if value == @syntax.PdfNull {
    return true
  }
  let values = match value {
    PdfArray(values) => values
    _ => [value]
  }
  guard values.length() <= 32 &&
    values.all(value => resolve(document, value) is PdfNameObject(_)) else {
    @failure.reject("invalid-pdf", "Invalid optional content intent")
  }
  values.any(value => {
    let value = resolve(document, value)
    is_name(value, "View") || is_name(value, "All")
  })
}

///|
fn optional_content_states(
  document : @pdflite.PdfDocument,
) -> Map[Int32, Bool] raise {
  let states : Map[Int32, Bool] = Map([])
  let catalog = resolve(document, @syntax.PdfIndirect(document.root()))
  let properties = get(document, catalog, "OCProperties")
  if properties == @syntax.PdfNull {
    return states
  }
  guard properties is PdfDictionary(_) &&
    get(document, properties, "OCGs") is PdfArray(groups) &&
    groups.length() <= 256 else {
    @failure.reject(
      "invalid-pdf", "Invalid or oversized optional content group list",
    )
  }
  let config = get(document, properties, "D")
  guard config is PdfDictionary(_) &&
    optional_view_intent(document, raw(config, "Intent")) else {
    @failure.reject(
      "unsupported-pdf", "Optional content requires a default View configuration",
    )
  }
  let base = get(document, config, "BaseState")
  guard base == @syntax.PdfNull || is_name(base, "ON") || is_name(base, "OFF") else {
    @failure.reject(
      "unsupported-pdf", "Unsupported optional content base state",
    )
  }
  for reference in groups {
    @pdfcore.sdk_check(1)
    guard reference is PdfIndirect(id) && !states.contains(id) else {
      @failure.reject(
        "invalid-pdf", "Optional content groups require unique indirect identities",
      )
    }
    let group = resolve(document, reference)
    guard is_name(raw(group, "Type"), "OCG") &&
      get(document, group, "Name") is PdfString(_) else {
      @failure.reject("invalid-pdf", "Invalid optional content group")
    }
    states[id] = !is_name(base, "OFF")
  }
  for (key, visible) in [("ON", true), ("OFF", false)] {
    let members = get(document, config, key)
    if members == @syntax.PdfNull {
      continue
    }
    guard members is PdfArray(members) && members.length() <= 256 else {
      @failure.reject("invalid-pdf", "Invalid optional content state list")
    }
    for item in members {
      guard item is PdfIndirect(id) && states.contains(id) else {
        @failure.reject(
          "invalid-pdf", "Unknown optional content group identity",
        )
      }
      states[id] = visible
    }
  }
  // Read the default on-screen state; UI ordering and print/export usage do not change it.
  let automatic = get(document, config, "AS")
  if automatic != @syntax.PdfNull {
    guard automatic is PdfArray(entries) && entries.length() <= 256 else {
      @failure.reject("invalid-pdf", "Invalid optional content usage list")
    }
    for entry in entries {
      let event = get(document, entry, "Event")
      guard ["View", "Print", "Export"].any(name => is_name(event, name)) else {
        @failure.reject("invalid-pdf", "Invalid optional content usage event")
      }
      if !is_name(event, "View") {
        continue
      }
      guard get(document, entry, "Category") is PdfArray(categories) &&
        categories.all(category => is_name(resolve(document, category), "View")) else {
        @failure.reject(
          "unsupported-pdf", "Dynamic optional content usage is unsupported",
        )
      }
    }
  }
  for reference in groups {
    guard reference is PdfIndirect(id) else {
      abort("Validated optional group")
    }
    let group = resolve(document, reference)
    if !optional_view_intent(document, raw(group, "Intent")) {
      states[id] = true
      continue
    }
    let view = get(document, get(document, group, "Usage"), "View")
    let state = get(document, view, "ViewState")
    if state != @syntax.PdfNull {
      guard is_name(state, "ON") || is_name(state, "OFF") else {
        @failure.reject("invalid-pdf", "Invalid optional content ViewState")
      }
      // Match PDFium's View usage precedence over the initial ON/OFF lists.
      states[id] = is_name(state, "ON")
    }
  }
  states
}

///|
fn ContentContext::optional_visible(
  self : ContentContext,
  source : @syntax.PdfObject,
  depth~ : Int32 = 0,
) -> Bool raise {
  @pdfcore.sdk_check(1)
  guard depth < 32 else {
    @failure.reject(
      "limit-exceeded", "Optional content expression exceeds depth budget",
    )
  }
  if source == @syntax.PdfNull {
    return true
  }
  let document = self.session.document
  let object = resolve(document, source)
  if is_name(raw(object, "Type"), "OCG") {
    if self.optional is None {
      self.optional = Some(optional_content_states(document))
    }
    guard source is PdfIndirect(id) &&
      self.optional.unwrap().get(id) is Some(visible) else {
      @failure.reject("invalid-pdf", "Unregistered optional content group")
    }
    return visible
  }
  if object is PdfArray([operator, .. operands]) {
    guard operands.length() > 0 &&
      operands.length() <= 256 &&
      operands.all(value => {
        value is PdfIndirect(_) || resolve(document, value) is PdfArray(_)
      }) else {
      @failure.reject(
        "invalid-pdf", "Invalid optional content expression arity",
      )
    }
    let values = operands.map(value => {
      self.optional_visible(value, depth=depth + 1)
    })
    return match resolve(document, operator) {
      value if is_name(value, "Not") && values.length() == 1 => !values[0]
      value if is_name(value, "And") => values.all(value => value)
      value if is_name(value, "Or") => values.any(value => value)
      _ =>
        @failure.reject(
          "invalid-pdf", "Invalid optional content expression operator",
        )
    }
  }
  guard is_name(raw(object, "Type"), "OCMD") else {
    @failure.reject(
      "invalid-pdf", "Invalid optional content membership dictionary",
    )
  }
  let expression = raw(object, "VE")
  if expression != @syntax.PdfNull {
    return self.optional_visible(expression, depth=depth + 1)
  }
  let groups = raw(object, "OCGs")
  if groups == @syntax.PdfNull {
    return true
  }
  let members = match resolve(document, groups) {
    PdfArray(members) => members
    _ => [groups]
  }
  guard members.length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Optional content membership exceeds budget",
    )
  }
  if members.is_empty() {
    return true
  }
  guard members.all(value => {
    value is PdfIndirect(_) &&
    is_name(raw(resolve(document, value), "Type"), "OCG")
  }) else {
    @failure.reject("invalid-pdf", "Invalid optional content membership group")
  }
  let values = members.map(value => {
    self.optional_visible(value, depth=depth + 1)
  })
  let policy = get(document, object, "P")
  match policy {
    PdfNull => values.any(value => value)
    value if is_name(value, "AnyOn") => values.any(value => value)
    value if is_name(value, "AllOn") => values.all(value => value)
    value if is_name(value, "AnyOff") => values.any(value => !value)
    value if is_name(value, "AllOff") => values.all(value => !value)
    _ =>
      @failure.reject(
        "invalid-pdf", "Invalid optional content membership policy",
      )
  }
}

///|
fn ContentContext::visible(self : ContentContext) -> Bool {
  self.marked.all(mark => mark.visible)
}

///|
fn ContentContext::begin_marked(
  self : ContentContext,
  visible : Bool,
  replacement : String?,
) -> Unit raise @failure.Failure {
  guard self.marked.length() < 32 else {
    @failure.reject("limit-exceeded", "PDF marked content exceeds depth budget")
  }
  self.marked.push({
    visible: visible && self.visible(),
    glyph: self.extraction.map(data => data.glyphs.length()).unwrap_or(0),
    replacement,
    span: self.spans.length(),
    chunk: self.chunks.length(),
    offset: self.units,
  })
}
