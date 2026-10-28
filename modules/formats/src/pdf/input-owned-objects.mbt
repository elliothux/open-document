///|
priv struct OwnedPdfObject {
  id : String
  marker : @syntax.PdfObject
  reference : @syntax.PdfObject
  form : @syntax.PdfObject
  kind : String
  placement : PdfPlacement
  foreground : Bool
}

///|
fn PdfSession::owned_objects(
  self : PdfSession,
  page : SourcePage,
) -> Array[OwnedPdfObject] raise {
  let contents = page_contents(
    self.document,
    self.document.lookup_object_or_null(page.number),
  )
  let objects : Array[OwnedPdfObject] = []
  let seen : Map[String, Bool] = Map([])
  for reference in contents {
    let object = resolve(self.document, reference)
    guard object is PdfStreamObject(s) else { continue }
    let marker = raw(s.dictionary, "ODIdentity")
    if marker == @syntax.PdfNull {
      continue
    }
    let identity = pdf_text_string(marker)
    guard identity.length() > 0 &&
      identity.length() <= 64 &&
      !seen.contains(identity) &&
      reference is PdfIndirect(_) else {
      @failure.reject("protected-content", "Ambiguous SDK PDF object identity")
    }
    seen[identity] = true
    guard raw(s.dictionary, "ODPlacement")
      is PdfArray([x, y, width, height, rotation]) else {
      @failure.reject("protected-content", "SDK PDF placement is malformed")
    }
    let placement : PdfPlacement = {
      x: number(x),
      y: number(y),
      width: number(width),
      height: number(height),
      rotation: number(rotation),
    }
    check_pdf_placement(placement)
    let form = raw(s.dictionary, "ODObject")
    let target = resolve(self.document, form)
    guard target is PdfStreamObject(targetStream) &&
      is_name(raw(targetStream.dictionary, "Subtype"), "Form") else {
      @failure.reject(
        "protected-content", "SDK PDF object requires a Form appearance",
      )
    }
    let kind = if is_name(raw(targetStream.dictionary, "ODKind"), "Text") {
      "text"
    } else if is_name(raw(targetStream.dictionary, "ODKind"), "Image") {
      "image"
    } else {
      "unsupported"
    }
    let ops = @pdflite.pdf_parse_content_ops_from_view(
      stream_bytes(self.document, reference),
    )
    guard ops is [Op_q, Op_cm(transform), Op_Do(key), Op_Q] &&
      raw(
        get(self.document, page.resources, "XObject"),
        @utf8.decode_lossy(key.bytes())[1:].to_owned(),
      ) ==
      form else {
      @failure.reject(
        "protected-content", "SDK PDF object content does not match its resource binding",
      )
    }
    let angle = placement.rotation * 3.141592653589793 / 180
    let screen : @layout.Matrix = {
      a: @math.cos(angle),
      b: @math.sin(angle),
      c: -@math.sin(angle),
      d: @math.cos(angle),
      e: placement.x,
      f: placement.y,
    }
    let (bx, by, br, bt) = rectangle(raw(targetStream.dictionary, "BBox"))
    let sx = placement.width / (br - bx)
    let sy = placement.height / (bt - by)
    let expected = page.matrix
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
    guard [
      (transform.a, expected.a),
      (transform.b, expected.b),
      (transform.c, expected.c),
      (transform.d, expected.d),
      (transform.e, expected.e),
      (transform.f, expected.f),
    ].all(pair => (pair.0 - pair.1).abs() <= 0.000001) else {
      @failure.reject(
        "protected-content", "SDK PDF placement does not match its native matrix",
      )
    }
    let foreground = raw(s.dictionary, "ODForeground") !=
      @syntax.PdfBoolean(false)
    objects.push({
      id: page.id + "/object/" + identity,
      marker,
      reference,
      form,
      kind,
      placement,
      foreground,
    })
  }
  objects
}

///|
pub fn PdfSession::objects(
  self : PdfSession,
  revision : Int32,
  id : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check(revision)
  pdf_bound(self.budget, () => {
    let page = self.page(id)
    let objects = self.owned_objects(page)
    let entries : Array[Json] = objects.map(object => {
      let form = resolve(self.document, object.form)
      let dictionary = match form {
        PdfStreamObject(s) => s.dictionary
        _ => dict([])
      }
      let role = raw(dictionary, "ODRole")
      let result : Json = {
        "id": object.id,
        "kind": object.kind,
        "placement": object.placement,
        "foreground": object.foreground,
        "text": if object.kind == "text" {
          pdf_text_string(raw(dictionary, "ODText"))
        } else {
          ""
        },
        "font": if object.kind == "text" {
          pdf_text_string(raw(dictionary, "ODFont"))
        } else {
          ""
        },
        "size": if object.kind == "text" {
          number(raw(dictionary, "ODSize"))
        } else {
          0.0
        },
        "color": if object.kind == "text" {
          pdf_text_string(raw(dictionary, "ODColor"))
        } else {
          ""
        },
        "role": if role is PdfNameObject(name) {
          @utf8.decode_lossy(name.bytes())[1:].to_owned()
        } else {
          "image"
        },
        "readOnlyReason": if object.kind == "unsupported" {
          "Unknown SDK PDF object type"
        } else {
          self.readOnlyReason
        },
      }
      result
    })
    let display = self.build_display(
      id,
      supplied,
      profile,
      @layout.Images::new(),
    )
    defer display.probe.close()
    for target in display.sources {
      entries.push(source_object_json(self, display, target))
    }
    guard entries.length() <= 4096 else {
      @failure.reject("limit-exceeded", "PDF object catalog exceeds budget")
    }
    { "revision": revision, "page": id, "objects": entries }
  })
}

///|
fn PdfSession::owned_object(
  self : PdfSession,
  page : SourcePage,
  id : String,
) -> OwnedPdfObject raise @failure.Failure {
  let objects = pdf_bound(self.budget, () => self.owned_objects(page)).filter(object => {
    object.id == id
  })
  guard objects.length() == 1 && objects[0].kind != "unsupported" else {
    @failure.reject(
      "protected-content", "PDF object is not a supported editable target",
    )
  }
  objects[0]
}

///|
fn PdfTransaction::replace_owned(
  self : PdfTransaction,
  page : SourcePage,
  object : OwnedPdfObject,
  form : @syntax.PdfObject,
  placement : PdfPlacement,
) -> Unit raise {
  let replacement = self.form_block(page, form, placement)
  guard replacement is PdfIndirect(number) &&
    self.object(number) is PdfStreamObject(s) else {
    abort("Expected object content")
  }
  self.objects[number] = @syntax.pdf_stream(
    s.dictionary
    .with_entry(pdf_name("ODIdentity"), object.marker)
    .with_entry(pdf_name("ODForeground"), @syntax.PdfBoolean(object.foreground)),
    s.data,
  )
  let contents = page_contents(self.session.document, self.object(page.number)).map(reference => {
      if reference == object.reference {
        replacement
      } else {
        reference
      }
    },
  )
  self.objects[page.number] = self
    .object(page.number)
    .with_entry(pdf_name("Contents"), @syntax.PdfArray(contents))
}

///|
pub fn PdfSession::replace_text(
  self : PdfSession,
  revision : Int32,
  page : String,
  id : String,
  spec : PdfTextSpec,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  if id.contains("/source/") {
    return self.replace_source_text(revision, page, id, spec, supplied, profile)
  }
  let tx = self.transaction(revision)
  let page = self.page(page)
  let object = self.owned_object(page, id)
  guard object.kind == "text" else {
    @failure.reject("invalid-operation", "Choose a PDF text object")
  }
  pdf_bound(self.budget, () => {
    let form = tx.text_form(spec, supplied, profile)
    let contents = page_contents(self.document, tx.object(page.number)).filter(reference => {
      reference != object.reference
    })
    tx.objects[page.number] = tx
      .object(page.number)
      .with_entry(pdf_name("Contents"), @syntax.PdfArray(contents))
    let replacement = tx.place_form(page, form, spec.placement, spec.foreground)
    guard replacement is PdfIndirect(number) &&
      tx.object(number) is PdfStreamObject(s) else {
      abort("Expected text block")
    }
    tx.objects[number] = @syntax.pdf_stream(
      s.dictionary.with_entry(pdf_name("ODIdentity"), object.marker),
      s.data,
    )
    tx.commit(self.current)
  })
}

///|
pub fn PdfSession::move_object(
  self : PdfSession,
  revision : Int32,
  page : String,
  id : String,
  placement : PdfPlacement,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  if id.contains("/source/") {
    return self.change_source_object(
      revision,
      page,
      id,
      Some(placement),
      supplied,
      profile,
    )
  }
  let tx = self.transaction(revision)
  let page = self.page(page)
  let object = self.owned_object(page, id)
  pdf_bound(self.budget, () => {
    tx.replace_owned(page, object, object.form, placement)
    tx.commit(self.current)
  })
}

///|
pub fn PdfSession::delete_object(
  self : PdfSession,
  revision : Int32,
  page : String,
  id : String,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  if id.contains("/source/") {
    return self.change_source_object(
      revision,
      page,
      id,
      None,
      supplied,
      profile,
    )
  }
  let tx = self.transaction(revision)
  let page = self.page(page)
  let object = self.owned_object(page, id)
  let contents = page_contents(self.document, tx.object(page.number)).filter(reference => {
    reference != object.reference
  })
  tx.objects[page.number] = tx
    .object(page.number)
    .with_entry(pdf_name("Contents"), @syntax.PdfArray(contents))
  tx.commit(self.current)
}
