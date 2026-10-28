///|
pub(all) struct PdfAnnotationStyle {
  placement : PdfPlacement
  color : String
  opacity : Double
  border : Double
  author : String
  text : String
}

///|
fn PdfSession::annotation_target(
  self : PdfSession,
  page : SourcePage,
  identity : String,
) -> Int32 raise @failure.Failure {
  let refs = annotation_refs(
    self.document,
    self.document.lookup_object_or_null(page.number),
  )
  for reference in refs {
    if reference is PdfIndirect(number) &&
      "\{number}:\{self.generations.get(number).unwrap_or(0)}" == identity {
      let object = self.document.lookup_object_or_null(number)
      let reason = annotation_reason(object)
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
      }
      self.check_annotation_relationships(page, number)
      return number
    }
  }
  @failure.reject("invalid-operation", "Unknown PDF annotation")
}

///|
fn check_annotation_style(
  page : SourcePage,
  style : PdfAnnotationStyle,
) -> Unit raise @failure.Failure {
  check_pdf_placement(style.placement)
  check_pdf_text(style.author)
  check_pdf_text(style.text)
  let p = style.placement
  guard p.rotation == 0 &&
    p.x >= 0 &&
    p.y >= 0 &&
    p.x + p.width <= page.width &&
    p.y + p.height <= page.height &&
    style.color.length() == 6 &&
    style.color
    .iter()
    .all(c => "0123456789abcdefABCDEF".contains(c.to_string())) &&
    style.opacity >= 0 &&
    style.opacity <= 1 &&
    style.border >= 0 &&
    style.border <= 100 else {
    @failure.reject(
      "invalid-operation", "Annotation geometry or style is invalid",
    )
  }
}

///|
fn annotation_placement(
  page : SourcePage,
  object : @syntax.PdfObject,
) -> PdfPlacement raise @failure.Failure {
  let (x, y, r, t) = rectangle(raw(object, "Rect"))
  let (a, b) = page.matrix.point(x, y)
  let (c, d) = page.matrix.point(r, t)
  {
    x: a.min(c),
    y: b.min(d),
    width: (c - a).abs(),
    height: (d - b).abs(),
    rotation: 0,
  }
}

///|
fn annotation_points_json(
  page : SourcePage,
  value : @syntax.PdfObject,
) -> Array[Double] raise @failure.Failure {
  guard value is PdfArray(points) &&
    points.length() % 2 == 0 &&
    points.length() <= 32768 else {
    @failure.reject(
      "protected-content", "Annotation coordinates are unsupported",
    )
  }
  let result : Array[Double] = []
  for i = 0; i < points.length(); i = i + 2 {
    let (x, y) = page.matrix.point(number(points[i]), number(points[i + 1]))
    result.append([x, y])
  }
  result
}

///|
pub fn PdfSession::annotation_details(
  self : PdfSession,
  revision : Int32,
  id : String,
  annotation : String,
) -> Json raise @failure.Failure {
  self.check(revision)
  pdf_bound(self.budget, () => {
    let page = self.page(id)
    let n = self.annotation_target(page, annotation)
    let object = self.document.lookup_object_or_null(n)
    guard raw(object, "Subtype") is PdfNameObject(subtype) else {
      @failure.reject("protected-content", "Annotation subtype is malformed")
    }
    let kind = @utf8.decode_lossy(subtype.bytes())[1:].to_owned()
    let color = raw(object, "C")
    let color = if color == @syntax.PdfNull {
      if kind == "Text" {
        "FFD926"
      } else if kind == "Highlight" {
        "FFFF00"
      } else {
        "000000"
      }
    } else {
      guard color is PdfArray(items) && items.length() == 3 else {
        @failure.reject("protected-content", "Annotation color is unsupported")
      }
      rgb(items.map(number))
    }
    let alpha = raw(object, "CA")
    let border = get(self.document, get(self.document, object, "BS"), "W")
    let strokes = match get(self.document, object, "InkList") {
      PdfArray(paths) => paths.map(path => annotation_points_json(page, path))
      PdfNull => []
      _ => @failure.reject("protected-content", "Ink strokes are malformed")
    }
    let points = if raw(object, "L") == @syntax.PdfNull {
      []
    } else {
      annotation_points_json(page, raw(object, "L"))
    }
    let parent = raw(object, "IRT")
    {
      "revision": revision,
      "page": id,
      "annotation": annotation,
      "kind": kind,
      "style": {
        "placement": annotation_placement(page, object),
        "color": color,
        "opacity": if alpha == @syntax.PdfNull {
          1.0
        } else {
          number(alpha)
        },
        "border": if border == @syntax.PdfNull {
          1.0
        } else {
          number(border)
        },
        "author": if raw(object, "T") == @syntax.PdfNull {
          ""
        } else {
          pdf_text_string(raw(object, "T"))
        },
        "text": if raw(object, "Contents") == @syntax.PdfNull {
          ""
        } else {
          pdf_text_string(raw(object, "Contents"))
        },
      },
      "points": points,
      "strokes": strokes,
      "arrow": raw(object, "LE") ==
      @syntax.PdfArray([tag("None"), tag("OpenArrow")]),
      "replyTo": match parent {
        PdfIndirect(number) =>
          "\{number}:\{self.generations.get(number).unwrap_or(0)}"
        _ => ""
      },
      "signature": raw(object, "ODSignature") == @syntax.PdfBoolean(true),
    }
  })
}

///|
pub fn PdfSession::edit_annotation(
  self : PdfSession,
  revision : Int32,
  id : String,
  annotation : String,
  style : PdfAnnotationStyle,
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  let page = self.page(id)
  check_annotation_style(page, style)
  pdf_bound(self.budget, () => {
    let number = self.annotation_target(page, annotation)
    let mut object = tx.object(number)
    let old = annotation_placement(page, object)
    let p = style.placement
    let sx = p.width / old.width
    let sy = p.height / old.height
    let screen : @layout.Matrix = {
      a: sx,
      b: 0,
      c: 0,
      d: sy,
      e: p.x - old.x * sx,
      f: p.y - old.y * sy,
    }
    let transform = page.matrix.inverse().then(screen).then(page.matrix)
    let (x, y) = page.matrix.inverse().point(p.x, p.y)
    let (r, t) = page.matrix.inverse().point(p.x + p.width, p.y + p.height)
    object = object
      .with_entry(
        pdf_name("Rect"),
        pdf_rectangle(x.min(r), y.min(t), x.max(r), y.max(t)),
      )
      .with_entry(
        pdf_name("C"),
        @syntax.PdfArray(
          [0, 2, 4].map(i => @syntax.PdfReal(channel(style.color, i))),
        ),
      )
      .with_entry(pdf_name("CA"), @syntax.PdfReal(style.opacity))
      .with_entry(
        pdf_name("BS"),
        dict([("W", @syntax.PdfReal(style.border)), ("S", tag("S"))]),
      )
      .with_entry(pdf_name("T"), pdf_string(style.author))
      .with_entry(pdf_name("Contents"), pdf_string(style.text))
    for key in ["QuadPoints", "L", "Vertices"] {
      if raw(object, key) != @syntax.PdfNull {
        object = object.with_entry(
          pdf_name(key),
          transform_pdf_points(raw(object, key), transform),
        )
      }
    }
    if raw(object, "InkList") is PdfArray(paths) {
      object = object.with_entry(
        pdf_name("InkList"),
        @syntax.PdfArray(
          paths.map(path => transform_pdf_points(path, transform)),
        ),
      )
    }
    tx.objects[number] = if is_name(raw(object, "Subtype"), "Stamp") {
      stamp_annotation_appearance(tx, object)
    } else {
      annotation_appearance(tx, object)
    }
    tx.commit(self.current)
  })
}
