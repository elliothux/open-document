///|
fn diagram_font_object(object : Object, size : Double) -> Object {
  let cached = object.diagram_font is Some(Cached(_, _))
  let body = match object.diagram_font.unwrap() {
    Layout(_, _, margin) => {
      let inset = size * margin
      {
        ..object.body,
        left: inset,
        right: inset,
        top: inset,
        bottom: inset,
        fit: "none",
      }
    }
    Cached(insets, _) => cached_font_body(object, size, insets)
  }
  {
    ..object,
    body,
    paragraphs: object.paragraphs.map(p => {
      ..p,
      // Cached paragraphs keep their line and before spacing; native layouts use the SmartArt defaults.
      spacing: if cached {
        p.spacing
      } else {
        Auto(216)
      },
      before: if cached {
        p.before
      } else {
        Points(0)
      },
      after: Points(size * 0.42),
      runs: p.runs.map(r => {
        ..r,
        parts: r.parts.map(part => ({ ..part.0, size, }, part.1)),
      }),
    }),
  }
}

///|
fn fit_diagram_text(
  objects : Array[Object],
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Array[Object] raise @failure.Failure {
  let sizes : Map[String, Double] = Map([])
  let maximums : Map[String, Double] = Map([])
  for object in objects {
    guard object.diagram_font is Some(font) else { continue }
    let (minimum, maximum, placeholder) = match font {
      Layout(minimum, maximum, _) => (minimum, maximum, false)
      Cached(_, placeholder) => (5.0, 65.0, placeholder)
    }
    let geometry = object.geometry.unwrap()
    let mut low = minimum.ceil().to_int() - 1
    let mut high = maximum.floor().to_int() + 1
    while high - low > 1 {
      let middle = (high + low) / 2
      let candidate = diagram_font_object(object, middle.to_double())
      let fits = try {
        match font {
          Cached(_, _) => cached_font_fits(candidate, probe, profile)
          Layout(_, _, _) => {
            let (lines, height) = measure_text(
              candidate, geometry, probe, profile, 1,
            )
            height <= geometry.height &&
            !lines.is_empty() &&
            lines.all(line => line.content_width() <= line.areaWidth + 0.01)
          }
        }
      } catch {
        @failure.Failure(code="layout-overflow", ..) => false
        error => raise error
      }
      if fits {
        low = middle
      } else {
        high = middle
      }
    }
    guard low.to_double() >= minimum else {
      @failure.reject(
        "layout-overflow", "SmartArt text cannot fit its minimum font size",
      )
    }
    maximums[object.id] = low.to_double()
    if !placeholder {
      sizes[object.parent] = sizes
        .get(object.parent)
        .unwrap_or(maximum)
        .min(low.to_double())
    }
  }
  objects.map(object => {
    if object.diagram_font is Some(font) {
      let minimum = match font {
        Layout(minimum, _, _) => minimum
        Cached(_, _) => 5.0
      }
      let size = sizes.get(object.parent).unwrap_or(65).min(maximums[object.id])
      guard size >= minimum else {
        @failure.reject(
          "layout-overflow", "SmartArt cannot satisfy shared font constraints",
        )
      }
      diagram_font_object(object, size)
    } else {
      object
    }
  })
}
