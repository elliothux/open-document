///|
pub(all) struct PdfPlacement {
  x : Double
  y : Double
  width : Double
  height : Double
  rotation : Double
} derive(ToJson)

///|
pub extend PdfPlacement with ToJson::{to_json}

///|
pub(all) struct PdfTextSpec {
  placement : PdfPlacement
  text : String
  font : String
  size : Double
  color : String
  role : String
  foreground : Bool
} derive(ToJson)

///|
pub extend PdfTextSpec with ToJson::{to_json}

///|
fn check_pdf_placement(value : PdfPlacement) -> Unit raise @failure.Failure {
  guard [value.x, value.y, value.width, value.height, value.rotation].all(n => {
      !n.is_nan() && !n.is_inf() && n.abs() <= 14400
    }) &&
    value.width > 0 &&
    value.height > 0 else {
    @failure.reject(
      "invalid-position", "PDF object placement exceeds the page geometry budget",
    )
  }
}

///|
fn page_contents(
  document : @pdflite.PdfDocument,
  page : @syntax.PdfObject,
) -> Array[@syntax.PdfObject] raise @failure.Failure {
  let value = raw(page, "Contents")
  match resolve(document, value) {
    PdfNull => []
    PdfArray(items) => items.copy()
    _ => [value]
  }
}

///|
fn PdfTransaction::form_block(
  self : PdfTransaction,
  page : SourcePage,
  form : @syntax.PdfObject,
  placement : PdfPlacement,
) -> @syntax.PdfObject raise {
  check_pdf_placement(placement)
  let angle = placement.rotation * 3.141592653589793 / 180
  let screen : @layout.Matrix = {
    a: @math.cos(angle),
    b: @math.sin(angle),
    c: -@math.sin(angle),
    d: @math.cos(angle),
    e: placement.x,
    f: placement.y,
  }
  let formObject = if form is PdfIndirect(number) {
    self.object(number)
  } else {
    form
  }
  guard formObject is PdfStreamObject(formStream) else {
    @failure.reject("invalid-operation", "PDF object requires a Form")
  }
  let (bx, by, br, bt) = rectangle(raw(formStream.dictionary, "BBox"))
  let sx = placement.width / (br - bx)
  let sy = placement.height / (bt - by)
  let transform = page.matrix
    .inverse()
    .then(screen)
    .then({
      a: sx,
      b: 0,
      c: 0,
      d: -sy,
      e: -bx * sx,
      f: placement.height + by * sy,
    })
  let object = self.object(page.number)
  let resources = resolve(self.session.document, raw(object, "Resources"))
  let resources = if resources == @syntax.PdfNull {
    page.resources.deep_copy()
  } else {
    resources.deep_copy()
  }
  let xobjects = get(self.session.document, resources, "XObject")
  let xobjects = if xobjects == @syntax.PdfNull {
    dict([])
  } else {
    xobjects.deep_copy()
  }
  let block = self.add(@syntax.PdfNull)
  guard block is PdfIndirect(id) else { abort("Expected content identity") }
  let key = "ODObject\{id}"
  let resources = resources.with_entry(
    pdf_name("XObject"),
    xobjects.with_entry(pdf_name(key), form),
  )
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_q,
    @content.Op_cm(geometry_matrix(transform)),
    @content.Op_Do(pdf_name(key)),
    @content.Op_Q,
  ]
  let content = stream(@pdflite.pdf_content_bytes_of_ops(ops), [
    ("ODIdentity", @syntax.PdfString(@utf8.encode(id.to_string()))),
    ("ODObject", form),
    (
      "ODPlacement",
      @syntax.PdfArray([
        @syntax.PdfReal(placement.x),
        @syntax.PdfReal(placement.y),
        @syntax.PdfReal(placement.width),
        @syntax.PdfReal(placement.height),
        @syntax.PdfReal(placement.rotation),
      ]),
    ),
  ])
  self.objects[id] = content
  self.objects[page.number] = object.with_entry(
    pdf_name("Resources"),
    resources,
  )
  block
}

///|
fn PdfTransaction::place_form(
  self : PdfTransaction,
  page : SourcePage,
  form : @syntax.PdfObject,
  placement : PdfPlacement,
  foreground : Bool,
) -> @syntax.PdfObject raise {
  let block = self.form_block(page, form, placement)
  guard block is PdfIndirect(blockNumber) &&
    self.object(blockNumber) is PdfStreamObject(blockStream) else {
    abort("Expected object block")
  }
  self.objects[blockNumber] = @syntax.pdf_stream(
    blockStream.dictionary.with_entry(
      pdf_name("ODForeground"),
      @syntax.PdfBoolean(foreground),
    ),
    blockStream.data,
  )
  let object = self.object(page.number)
  let contents = page_contents(self.session.document, object)
  if foreground {
    let mut nesting = 0
    let mut inText = false
    for
      op in @pdflite.pdf_parse_content_ops_from_view(
        content_bytes(self.session.document, raw(object, "Contents")),
      ) {
      match op {
        Op_q => nesting += 1
        Op_Q => nesting -= 1
        Op_BT => {
          guard !inText else {
            @failure.reject(
              "protected-content", "Nested PDF text objects are protected",
            )
          }
          inText = true
        }
        Op_ET => inText = false
        _ => ()
      }
      guard nesting >= 0 && nesting <= 32 else {
        @failure.reject(
          "protected-content", "Unbalanced PDF graphics state is protected",
        )
      }
    }
    guard nesting == 0 && !inText else {
      @failure.reject(
        "protected-content", "Unbalanced PDF page content is protected",
      )
    }
    contents.insert(0, self.add(stream(b"q\n", [])))
    contents.push(self.add(stream(b"\nQ\n", [])))
    contents.push(block)
  } else {
    contents.insert(0, block)
  }
  self.objects[page.number] = object.with_entry(
    pdf_name("Contents"),
    @syntax.PdfArray(contents),
  )
  block
}

///|
fn PdfTransaction::text_form(
  self : PdfTransaction,
  spec : PdfTextSpec,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> @syntax.PdfObject raise {
  check_pdf_placement(spec.placement)
  check_pdf_text(spec.text)
  guard !spec.text.is_empty() &&
    spec.size > 0 &&
    spec.size <= 14400 &&
    spec.color.length() == 6 &&
    spec.color.iter().all(c => "0123456789abcdefABCDEF".contains(c.to_string())) &&
    ["text", "watermark", "header", "footer", "page-number"].contains(spec.role) else {
    @failure.reject(
      "invalid-text", "PDF text requires content, a bounded size, RGB color and a known role",
    )
  }
  let probe = @layout.TextProbe::new()
  defer probe.close()
  for index, info in supplied.font_info() {
    ignore(probe.add_font(supplied.font_bytes(index), info.identity))
  }
  let block = probe.text_block(
    spec.text,
    @layout.TextStyle::new(spec.font, spec.size, spec.color),
    profile,
    spec.placement.width,
    true,
  )
  guard block.height <= spec.placement.height &&
    block.widths.all(width => width <= spec.placement.width) else {
    @failure.reject(
      "text-overflow", "PDF text does not fit the requested text box",
    )
  }
  let primitives : Array[@layout.PositionedPrimitive] = []
  for line in block.lines {
    primitives.append(line)
  }
  let positioned : @layout.PositionedDocument = {
    links: [],
    pages: [
      {
        width: spec.placement.width,
        height: spec.placement.height,
        primitives,
      },
    ],
    fonts: probe.font_info(),
  }
  let bytes = write(
    positioned,
    probe,
    @layout.Images::new(),
    self.session.budget.outputBytes.min(8388608),
  )
  let source = @pdflite.pdf_read_classic_document_from_view(bytes)
  let pages = read_pages(
    source,
    Map(source.parsed_object_entries().map(entry => (entry.0, entry.1))),
    self.session.budget,
  )
  let resources = import_object(self, source, pages[0].resources, Map([]), 0)
  let form = appearance_stream(
    content_bytes(
      source,
      raw(source.lookup_object_or_null(pages[0].number), "Contents"),
    ),
    spec.placement.width,
    spec.placement.height,
    resources,
  )
  guard form is PdfStreamObject(value) else { abort("Expected text Form") }
  let dictionary = value.dictionary
    .with_entry(pdf_name("ODKind"), tag("Text"))
    .with_entry(pdf_name("ODText"), pdf_string(spec.text))
    .with_entry(pdf_name("ODFont"), pdf_string(spec.font))
    .with_entry(pdf_name("ODSize"), @syntax.PdfReal(spec.size))
    .with_entry(pdf_name("ODColor"), pdf_string(spec.color))
    .with_entry(pdf_name("ODRole"), tag(spec.role))
  self.add(@syntax.pdf_stream(dictionary, value.data))
}

///|
pub fn PdfSession::add_text(
  self : PdfSession,
  revision : Int32,
  pages : Array[String],
  spec : PdfTextSpec,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard !pages.is_empty() && pages.length() <= self.budget.pages else {
    @failure.reject("invalid-page", "Choose PDF pages for text insertion")
  }
  pdf_bound(self.budget, () => {
    let common = if spec.role == "page-number" {
      None
    } else {
      Some(tx.text_form(spec, supplied, profile))
    }
    let seen : Map[String, Bool] = Map([])
    for index, id in pages {
      guard !seen.contains(id) else {
        @failure.reject("invalid-page", "Duplicate PDF overlay page")
      }
      seen[id] = true
      let form = match common {
        Some(form) => form
        None =>
          tx.text_form(
            {
              ..spec,
              text: spec.text.replace_all(
                old="{page}",
                new=(index + 1).to_string(),
              ),
            },
            supplied,
            profile,
          )
      }
      ignore(
        tx.place_form(self.page(id), form, spec.placement, spec.foreground),
      )
    }
    tx.commit(self.current)
  })
}

///|
pub fn PdfSession::add_image(
  self : PdfSession,
  revision : Int32,
  page : String,
  placement : PdfPlacement,
  width : Int32,
  height : Int32,
  rgba : Bytes,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  replace~ : String = "",
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  check_pdf_placement(placement)
  guard width > 0 &&
    height > 0 &&
    width <= 4096 &&
    height <= 4096 &&
    width.to_int64() * height.to_int64() * 4 == rgba.length().to_int64() &&
    rgba.length() <= 16777216 else {
    @failure.reject("invalid-image", "PDF image requires bounded RGBA pixels")
  }
  pdf_bound(self.budget, () => {
    let rgb = Bytes::makei(width * height * 3, i => rgba[i / 3 * 4 + i % 3])
    let alpha = Bytes::makei(width * height, i => rgba[i * 4 + 3])
    let entries : Array[(String, @syntax.PdfObject)] = [
      ("Type", tag("XObject")),
      ("Subtype", tag("Image")),
      ("Width", @syntax.PdfInteger(width)),
      ("Height", @syntax.PdfInteger(height)),
      ("ColorSpace", tag("DeviceRGB")),
      ("BitsPerComponent", @syntax.PdfInteger(8)),
    ]
    if alpha.iter().any(value => value != 255) {
      entries.push(
        (
          "SMask",
          tx.add(
            stream(alpha, [
              ("Type", tag("XObject")),
              ("Subtype", tag("Image")),
              ("Width", @syntax.PdfInteger(width)),
              ("Height", @syntax.PdfInteger(height)),
              ("ColorSpace", tag("DeviceGray")),
              ("BitsPerComponent", @syntax.PdfInteger(8)),
            ]),
          ),
        ),
      )
    }
    let image = tx.add(stream(rgb, entries))
    let form = appearance_stream(
      @pdflite.pdf_content_bytes_of_ops([
        @content.Op_q,
        @content.Op_cm({
          a: placement.width,
          b: 0,
          c: 0,
          d: placement.height,
          e: 0,
          f: 0,
        }),
        @content.Op_Do(pdf_name("Image")),
        @content.Op_Q,
      ]),
      placement.width,
      placement.height,
      dict([("XObject", dict([("Image", image)]))]),
    )
    guard form is PdfStreamObject(value) else { abort("Expected image Form") }
    let form = tx.add(
      @syntax.pdf_stream(
        value.dictionary.with_entry(pdf_name("ODKind"), tag("Image")),
        value.data,
      ),
    )
    let page = self.page(page)
    if replace.is_empty() {
      ignore(tx.place_form(page, form, placement, true))
    } else if replace.contains("/source/") {
      tx.replace_source_image(page, replace, form, placement, supplied, profile)
    } else {
      let object = self.owned_object(page, replace)
      guard object.kind == "image" else {
        @failure.reject("invalid-operation", "Choose a PDF image object")
      }
      tx.replace_owned(page, object, form, placement)
    }
    tx.commit(self.current)
  })
}
