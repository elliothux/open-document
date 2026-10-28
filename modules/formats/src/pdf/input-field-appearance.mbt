///|
fn import_object(
  tx : PdfTransaction,
  source : @pdflite.PdfDocument,
  value : @syntax.PdfObject,
  imported : Map[Int32, Int32],
  depth : Int32,
) -> @syntax.PdfObject raise @failure.Failure {
  guard depth < 64 else {
    @failure.reject(
      "limit-exceeded", "Appearance resource depth exceeds budget",
    )
  }
  match value {
    PdfIndirect(number) => {
      if imported.get(number) is Some(id) {
        return @syntax.PdfIndirect(id)
      }
      guard tx.add(@syntax.PdfNull) is PdfIndirect(id) else {
        @failure.reject("invalid-pdf", "Cannot allocate appearance object")
      }
      imported[number] = id
      tx.objects[id] = import_object(
        tx,
        source,
        source.lookup_object_or_null(number),
        imported,
        depth + 1,
      )
      @syntax.PdfIndirect(id)
    }
    PdfArray(items) =>
      @syntax.PdfArray(
        items.map(item => import_object(tx, source, item, imported, depth + 1)),
      )
    PdfDictionary(entries) =>
      @syntax.PdfDictionary(
        entries.map(pair => {
          (pair.0, import_object(tx, source, pair.1, imported, depth + 1))
        }),
      )
    PdfStreamObject(stream) =>
      @syntax.PdfStreamObject({
        dictionary: import_object(
          tx,
          source,
          stream.dictionary,
          imported,
          depth + 1,
        ),
        data: stream.data,
      })
    _ => value
  }
}

///|
fn widget_color(
  object : @syntax.PdfObject,
  key : String,
) -> String raise @failure.Failure {
  let color = raw(object, key)
  if color == @syntax.PdfNull || color is PdfArray([]) {
    return ""
  }
  guard color is PdfArray(items) && (items.length() == 1 || items.length() == 3) else {
    @failure.reject("protected-content", "Widget color is unsupported")
  }
  rgb(items.map(number))
}

///|
fn field_appearance(
  tx : PdfTransaction,
  field : FormField,
  widget_id : Int32,
  page : SourcePage,
  text : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> @syntax.PdfObject raise {
  let document = tx.session.document
  let widget = tx.object(widget_id)
  let (x, y, r, t) = rectangle(get(document, widget, "Rect"))
  let width = r - x
  let height = t - y
  guard width <= 14400 && height <= 14400 else {
    @failure.reject(
      "limit-exceeded", "PDF field appearance dimensions exceed budget",
    )
  }
  let mk = get(document, widget, "MK")
  if mk is PdfDictionary(entries) {
    for (key, value) in entries {
      guard [pdf_name("BC"), pdf_name("BG")].contains(key) ||
        (key == pdf_name("R") && integer(resolve(document, value)) == 0) else {
        @failure.reject(
          "protected-content", "Widget appearance property is unsupported",
        )
      }
    }
  } else {
    guard mk == @syntax.PdfNull else {
      @failure.reject("invalid-pdf", "Invalid widget appearance dictionary")
    }
  }
  let background = widget_color(mk, "BG")
  let border_color = widget_color(mk, "BC")
  let bs = get(document, widget, "BS")
  let mut border = 1.0
  let mut dash : Array[Double] = []
  if bs != @syntax.PdfNull {
    let value = get(document, bs, "W")
    if value != @syntax.PdfNull {
      border = number(value)
    }
    let style = get(document, bs, "S")
    guard style == @syntax.PdfNull || is_name(style, "S") || is_name(style, "D") else {
      @failure.reject("protected-content", "Widget border style is unsupported")
    }
    if is_name(style, "D") {
      let value = get(document, bs, "D")
      dash = match value {
        PdfArray(items) => items.map(number)
        PdfNull => [3.0]
        _ => @failure.reject("invalid-pdf", "Invalid widget border dash")
      }
    }
  } else {
    let value = get(document, widget, "Border")
    if value != @syntax.PdfNull {
      guard value is PdfArray(items) &&
        (items.length() == 3 || items.length() == 4) &&
        number(items[0]) == 0 &&
        number(items[1]) == 0 else {
        @failure.reject(
          "protected-content", "Rounded widget border is unsupported",
        )
      }
      border = number(items[2])
      if items.length() == 4 {
        guard items[3] is PdfArray(values) else {
          @failure.reject("invalid-pdf", "Invalid widget border dash")
        }
        dash = values.map(number)
      }
    }
  }
  check_style({ ..@layout.DrawStyle::default(), dash, }, border)
  guard dash.is_empty() else {
    @failure.reject(
      "protected-content", "Dashed text widget border is unsupported",
    )
  }
  let padding = border + 2
  guard width > padding * 2 && height > padding * 2 else {
    @failure.reject("invalid-text", "PDF field has no available text area")
  }
  guard field.attributes.get("DA") is Some(PdfString(da)) else {
    @failure.reject(
      "protected-content", "Text field requires a default appearance",
    )
  }
  let ops = @pdflite.pdf_parse_content_ops_from_view(da)
  let mut font_name : @pdfcore.PdfName? = None
  let mut size = 0.0
  let mut color = "000000"
  for op in ops {
    match op {
      Op_Tf(name, font_size) => {
        font_name = Some(name)
        size = font_size
      }
      Op_g(gray) => color = rgb([gray])
      Op_rg(r, g, b) => color = rgb([r, g, b])
      _ =>
        @failure.reject(
          "protected-content", "Text field default appearance is unsupported",
        )
    }
  }
  guard font_name is Some(font_name) && size >= 0 && size <= 14400 else {
    @failure.reject(
      "protected-content", "Text field requires a bounded font size",
    )
  }
  let alignment = field.attributes.get("Q").map(integer).unwrap_or(0)
  guard [0, 1, 2].contains(alignment) else {
    @failure.reject("protected-content", "Unsupported text field alignment")
  }
  let probe = @layout.TextProbe::new()
  defer probe.close()
  for index, info in supplied.font_info() {
    ignore(probe.add_font(supplied.font_bytes(index), info.identity))
  }
  let identity = if @layout.font_profile_identity(profile, "form")
    is Some(identity) {
    ignore(probe.font_index(identity))
    identity
  } else if field.attributes.get("ODFont") is Some(family) &&
    @layout.font_profile_identity(profile, pdf_text_string(family))
    is Some(identity) {
    ignore(probe.font_index(identity))
    identity
  } else {
    let catalog = resolve(document, @syntax.PdfIndirect(document.root()))
    let form = get(document, catalog, "AcroForm")
    let resources = get(document, form, "DR")
    let resources = if resources == @syntax.PdfNull {
      page.resources
    } else {
      resources
    }
    let font = font_resource(
      document,
      resources,
      font_name,
      probe,
      supplied,
      profile,
      [],
    )
    guard font.index is Some(index) else {
      @failure.reject(
        "missing-font", "Text field requires an explicit embeddable font",
      )
    }
    probe.font_info()[index].identity
  }
  let font_profile = profile.copy()
  font_profile["form"] = identity
  // A blank variable-text widget still needs an embedded default font.
  let text = if text.is_empty() { " " } else { text }
  let mut chosen : @layout.TextBlock? = None
  let mut listRows : Array[(String, Bool)] = []
  let mut rowHeight = 0.0
  let initial = if size == 0 { 12.0.min(height - padding * 2) } else { size }
  for attempt in 0..<9 {
    let current = initial - attempt.to_double()
    if current < 4 || (size > 0 && attempt > 0) {
      break
    }
    let style = @layout.TextStyle::new("form", current, color)
    let text = if field.kind == "list" {
      let selected : Array[String] = match field.value {
        Array(values) =>
          values.filter_map(value => {
            match value {
              String(text) => Some(text)
              _ => None
            }
          })
        _ => []
      }
      rowHeight = probe.text_block(
          "M",
          style,
          font_profile,
          width - padding * 2,
          false,
        ).height
      let count = ((height - padding * 2) / rowHeight).to_int().max(1)
      let mut start = 0
      for index, option in field.options {
        if selected.contains(option.0) {
          start = index
          break
        }
      }
      listRows = field.options[start:(start + count).min(field.options.length())].map(option => {
          (option.1, selected.contains(option.0))
        },
      )
      listRows.map(row => row.0).join("\n")
    } else {
      text
    }
    let block = probe.text_block(
      text,
      style,
      font_profile,
      width - padding * 2,
      field.multiline && field.kind != "list",
    )
    if block.height <= height - padding * 2 &&
      (field.kind == "list" || block.widths.all(w => w <= width - padding * 2)) {
      chosen = Some(block)
      break
    }
  }
  guard chosen is Some(block) else {
    @failure.reject("text-overflow", "Text does not fit PDF field appearance")
  }
  let primitives : Array[@layout.PositionedPrimitive] = []
  if !background.is_empty() {
    primitives.push(
      @layout.Rectangle({ x: 0, y: 0, width, height, color: background, }),
    )
  }
  if border > 0 {
    primitives.push(
      @layout.Stroke(
        {
          x: border / 2,
          y: border / 2,
          width: width - border,
          height: height - border,
        },
        if border_color.is_empty() {
          "000000"
        } else {
          border_color
        },
        border,
      ),
    )
  }
  primitives.push(
    @layout.Clip({
      x: padding,
      y: padding,
      width: width - padding * 2,
      height: height - padding * 2,
    }),
  )
  for index, line in block.lines {
    if field.kind == "list" && index < listRows.length() && listRows[index].1 {
      primitives.push(
        @layout.Rectangle({
          x: padding,
          y: padding + index.to_double() * rowHeight,
          width: width - padding * 2,
          height: rowHeight,
          color: "BDD7EE",
        }),
      )
    }
    let offset = if alignment == 1 {
      (width - padding * 2 - block.widths[index]) / 2
    } else if alignment == 2 {
      width - padding * 2 - block.widths[index]
    } else {
      0.0
    }
    primitives.push(
      @layout.Transform({
        a: 1,
        b: 0,
        c: 0,
        d: 1,
        e: padding + offset,
        f: padding,
      }),
    )
    primitives.append(line)
    primitives.push(@layout.Restore)
  }
  primitives.push(@layout.Restore)
  let positioned : @layout.PositionedDocument = {
    links: [],
    pages: [{ width, height, primitives, }],
    fonts: probe.font_info(),
  }
  let bytes = write(
    positioned,
    probe,
    @layout.Images::new(),
    tx.session.budget.outputBytes.min(8388608),
  )
  let source = @pdflite.pdf_read_classic_document_from_view(bytes)
  let pages = read_pages(
    source,
    Map(source.parsed_object_entries().map(entry => (entry.0, entry.1))),
    tx.session.budget,
  )
  let source_page = source.lookup_object_or_null(pages[0].number)
  let imported : Map[Int32, Int32] = Map([])
  let resources = import_object(tx, source, pages[0].resources, imported, 0)
  tx.add(
    appearance_stream(
      content_bytes(source, raw(source_page, "Contents")),
      width,
      height,
      resources,
    ),
  )
}
