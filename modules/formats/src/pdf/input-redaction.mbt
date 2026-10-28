///|
priv struct RedactionPlan {
  pages : Array[@layout.PositionedPage]
  probe : @layout.TextProbe
  images : @layout.Images
  affected : Array[Json]
  warnings : Array[String]
  expectedText : Array[String]
  expectedImages : Array[Array[Bytes]]
  textGroups : Array[PdfTextGroup]
}

///|
fn RedactionPlan::close(self : RedactionPlan) -> Unit {
  self.probe.close()
  self.images.clear()
}

///|
fn PdfSession::redaction_widgets(
  self : PdfSession,
  regions : Array[PdfRedactionRegion],
) -> Unit raise @failure.Failure {
  for page in self.pages {
    let selected = regions.filter(region => region.page == page.id)
    if selected.is_empty() {
      continue
    }
    for
      reference in annotation_refs(
        self.document,
        self.document.lookup_object_or_null(page.number),
      ) {
      let object = resolve(self.document, reference)
      if !is_name(raw(object, "Subtype"), "Widget") {
        continue
      }
      let (x, y, r, t) = rectangle(get(self.document, object, "Rect"))
      let (a, b) = page.matrix.point(x, y)
      let (c, d) = page.matrix.point(r, t)
      let bounds : RedactionBounds = {
        x: a.min(c),
        y: b.min(d),
        width: (c - a).abs(),
        height: (d - b).abs(),
      }
      guard !selected.any(region => redaction_intersects(bounds, region)) else {
        @failure.reject(
          "protected-content", "Redaction intersecting an interactive form widget is protected",
        )
      }
    }
  }
}

///|
fn PdfSession::redaction_plan(
  self : PdfSession,
  revision : Int32,
  regions : Array[PdfRedactionRegion],
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded? : @layout.Images,
) -> RedactionPlan raise @failure.Failure {
  self.redaction_regions(revision, regions)
  pdf_bound(self.budget, () => {
    self.redaction_widgets(regions)
    let source : Array[PdfExtraction] = []
    defer (for page in source {
      page.close()
    })
    let usages : Map[Int32, Int32] = Map([])
    let masks : Map[Int32, Int32] = Map([])
    for page in self.pages {
      let extraction = self.extract_page(
        revision,
        page.id,
        supplied,
        profile,
        decoded?,
      )
      source.push(extraction)
      guard extraction.displayComplete else {
        @failure.reject(
          "protected-content", "Redaction requires complete interpretation of every page",
        )
      }
      for image in extraction.images {
        if image.reference >= 0 {
          usages[image.reference] = usages.get(image.reference).unwrap_or(0) + 1
          if raw(self.document.lookup_object_or_null(image.reference), "SMask")
            is PdfIndirect(mask) {
            masks[mask] = masks.get(mask).unwrap_or(0) + 1
          }
        }
      }
    }
    let probe = @layout.TextProbe::new()
    errdefer probe.close()
    let images = @layout.Images::new()
    errdefer images.clear()
    let fontIds : Map[String, Int32] = Map([])
    let pages : Array[@layout.PositionedPage] = []
    let affected : Array[Json] = []
    let expectedText : Array[String] = []
    let expectedImages : Array[Array[Bytes]] = []
    let textGroups : Array[PdfTextGroup] = []
    for pageIndex, extraction in source {
      let selected = regions.filter(region => region.page == extraction.page)
      let removed : Map[Int32, Bool] = Map([])
      let groups : Map[Int32, RedactionBounds] = Map([])
      let removedGroups : Map[Int32, Bool] = Map([])
      for glyph in extraction.glyphs {
        let bounds = redaction_glyph_bounds(glyph)
        groups[glyph.group] = groups
          .get(glyph.group)
          .map(before => redaction_union(before, bounds))
          .unwrap_or(bounds)
        // Substituted outlines cannot bound the actual source font's ink.
        guard glyph.annotation || !glyph.substituted else {
          @failure.reject(
            "protected-content", "Redaction requires exact source fonts; substituted text is protected",
          )
        }
        if glyph.annotation ||
          glyph.invisible ||
          (
            glyph.inkQuad.is_empty() &&
            !glyph.encodedText.iter().all(c => c.is_whitespace())
          ) ||
          selected.any(region => redaction_intersects(bounds, region)) {
          removedGroups[glyph.group] = true
        }
      }
      let fonts : Map[Int32, Int32] = Map([])
      let text = StringBuilder()
      for glyph in extraction.glyphs {
        if removedGroups.contains(glyph.group) {
          if glyph.primitive >= 0 {
            removed[glyph.primitive] = true
          }
          continue
        }
        let bounds = redaction_glyph_bounds(glyph)
        guard glyph.mapped &&
          !glyph.clipped &&
          glyph.cleanReason.is_empty() &&
          glyph.primitive >= 0 &&
          redaction_on_page(bounds, extraction.width, extraction.height) else {
          @failure.reject(
            "protected-content",
            if glyph.cleanReason.is_empty() {
              "A surviving glyph is hidden, clipped or cannot be reconstructed safely"
            } else {
              glyph.cleanReason
            },
          )
        }
        if !fonts.contains(glyph.fontIndex) {
          let info = extraction.probe.font_info()[glyph.fontIndex]
          let font = if fontIds.get(info.sha256) is Some(font) {
            font
          } else {
            let font = probe.add_font(
              extraction.probe.font_bytes(glyph.fontIndex),
              "clean-font-\{fontIds.length()}",
            )
            fontIds[info.sha256] = font
            font
          }
          fonts[glyph.fontIndex] = font
        }
        text.write_string(glyph.encodedText)
      }
      for group, _ in removedGroups {
        affected.push(
          redaction_affected(extraction.page, "text-group", groups[group]),
        )
      }
      for path in extraction.paths {
        let bounds = redaction_path_bounds(
          path.path,
          if path.stroke.is_empty() {
            0
          } else {
            path.width / 2 * path.style.miter.max(1)
          },
        )
        if path.annotation ||
          selected.any(region => redaction_intersects(bounds, region)) {
          removed[path.primitive] = true
          affected.push(
            redaction_affected(
              extraction.page,
              if path.annotation {
                "annotation"
              } else {
                "path"
              },
              bounds,
            ),
          )
        } else {
          guard !path.clipped &&
            path.cleanReason.is_empty() &&
            redaction_on_page(bounds, extraction.width, extraction.height) else {
            @failure.reject(
              "protected-content",
              if path.cleanReason.is_empty() {
                "A surviving path is clipped or extends outside its page"
              } else {
                path.cleanReason
              },
            )
          }
        }
      }
      let imageKeys : Map[String, String] = Map([])
      let pageImages : Array[Bytes] = []
      for imageIndex, image in extraction.images {
        let bounds = redaction_bounds(image.quad)
        if image.annotation || image.opacity == 0 {
          removed[image.primitive] = true
          affected.push(
            redaction_affected(
              extraction.page,
              if image.annotation {
                "annotation"
              } else {
                "hidden-image"
              },
              bounds,
            ),
          )
          continue
        }
        let touched = selected.any(region => {
          redaction_intersects(bounds, region)
        })
        if touched {
          guard image.reference < 0 ||
            usages.get(image.reference).unwrap_or(0) == 1 else {
            @failure.reject(
              "protected-content", "Redaction of a reused image is protected",
            )
          }
          if image.reference >= 0 &&
            raw(self.document.lookup_object_or_null(image.reference), "SMask")
            is PdfIndirect(mask) {
            guard masks.get(mask).unwrap_or(0) == 1 else {
              @failure.reject(
                "protected-content", "Redaction of a reused image mask is protected",
              )
            }
          }
          guard image.simpleForm else {
            @failure.reject(
              "protected-content", "Redaction of an image inside a complex Form is protected",
            )
          }
        }
        guard image.jpeg is None &&
          !image.rgba.is_empty() &&
          !image.clipped &&
          image.cleanReason.is_empty() &&
          redaction_on_page(bounds, extraction.width, extraction.height) else {
          @failure.reject(
            "protected-content",
            if image.jpeg is Some(_) {
              "Decode all source JPEG images before redaction"
            } else if image.cleanReason.is_empty() {
              "A surviving image is clipped or cannot be reconstructed safely"
            } else {
              image.cleanReason
            },
          )
        }
        let (pixels, changed) = redaction_image_pixels(
          image,
          if touched {
            selected
          } else {
            []
          },
        )
        let key = "clean-page-\{pageIndex}-image-\{imageIndex}"
        images.add(key, image.pixelWidth, image.pixelHeight, pixels)
        imageKeys[image.key] = key
        pageImages.push(pixels)
        if changed is Some(changed) {
          affected.push(
            redaction_affected(extraction.page, "image-pixels", changed),
          )
        }
      }
      guard affected.length() <= 65536 else {
        @failure.reject(
          "limit-exceeded", "Redaction preview exceeds the affected object budget",
        )
      }
      let known : Map[Int32, Bool] = Map([])
      for glyph in extraction.glyphs {
        if glyph.primitive >= 0 {
          known[glyph.primitive] = true
        }
      }
      for image in extraction.images {
        if image.primitive >= 0 {
          known[image.primitive] = true
        }
      }
      for path in extraction.paths {
        if path.primitive >= 0 {
          known[path.primitive] = true
        }
      }
      let primitives : Array[@layout.PositionedPrimitive] = []
      for index, primitive in extraction.primitives {
        if removed.contains(index) {
          continue
        }
        match primitive {
          Text(_) | Image(_, _) | Path(_, _, _, _, _) => {
            guard known.contains(index) else {
              @failure.reject(
                "protected-content", "An untracked drawing item protects redaction",
              )
            }
          }
          Rectangle(fill) => {
            guard fill.x == 0 &&
              fill.y == 0 &&
              fill.width == extraction.width &&
              fill.height == extraction.height &&
              fill.color.to_lower() == "ffffff" else {
              @failure.reject(
                "protected-content", "An untracked fill protects redaction",
              )
            }
          }
          Transform(_) | Clip(_) | ClipPath(_, _) | Restore => ()
          _ =>
            @failure.reject(
              "protected-content", "An unsupported drawing item protects redaction",
            )
        }
        primitives.push(redaction_primitive(primitive, fonts, imageKeys))
      }
      for region in selected {
        primitives.push(
          @layout.Rectangle({
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height,
            color: "000000",
          }),
        )
      }
      let primitives = redaction_prune_scopes(primitives)
      textGroups.append(
        redaction_text_groups(
          pageIndex,
          extraction.glyphs,
          removedGroups,
          primitives,
        ),
      )
      pages.push({
        width: extraction.width,
        height: extraction.height,
        primitives,
      })
      expectedText.push(text.to_string())
      expectedImages.push(pageImages)
    }
    {
      pages,
      probe,
      images,
      affected,
      expectedText,
      expectedImages,
      textGroups,
      warnings: [
        "The original PDF and its history still contain the original content; only the exported copy is cleaned",
        "Text groups and paths may be removed beyond the selected rectangle; image removal covers whole intersecting pixels",
        "Annotations, interactive fields, links, metadata, attachments and old revisions are omitted from the cleaned copy",
        "Other occurrences of the same information are not automatically redacted; select them separately",
      ],
    }
  })
}

///|
pub fn PdfSession::preview_redaction(
  self : PdfSession,
  revision : Int32,
  regions : Array[PdfRedactionRegion],
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded? : @layout.Images,
) -> Json raise @failure.Failure {
  self.redaction_regions(revision, regions)
  try {
    let plan = self.redaction_plan(
      revision,
      regions,
      supplied,
      profile,
      decoded?,
    )
    defer plan.close()
    {
      "revision": revision,
      "regions": regions,
      "affected": plan.affected,
      "warnings": plan.warnings,
      "readOnlyReason": "",
    }
  } catch {
    @failure.Failure(
      code="stale-revision"
      | "closed-session"
      | "invalid-selection"
      | "limit-exceeded",
      ..
    ) as failure => raise failure
    @failure.Failure(message~, ..) =>
      {
        "revision": revision,
        "regions": regions,
        "affected": [],
        "warnings": [],
        "readOnlyReason": message,
      }
  }
}

///|
fn PdfSession::verify_redaction(
  self : PdfSession,
  bytes : Bytes,
  plan : RedactionPlan,
  regions : Array[PdfRedactionRegion],
) -> Unit raise @failure.Failure {
  let result = PdfSession::open(bytes, self.budget)
  defer result.close()
  guard result.pages.length() == plan.pages.length() else {
    @failure.reject(
      "redaction-failed", "Clean output page count does not match its candidate",
    )
  }
  let catalog = resolve(
    result.document,
    @syntax.PdfIndirect(result.document.root()),
  )
  for
    key in [
      "Metadata", "Names", "AcroForm", "Outlines", "StructTreeRoot", "OpenAction",
      "AA", "PieceInfo",
    ] {
    guard raw(catalog, key) == @syntax.PdfNull else {
      @failure.reject(
        "redaction-failed", "Clean output unexpectedly retained a source payload",
      )
    }
  }
  for key in ["Info", "Prev", "Encrypt"] {
    guard raw(result.document.trailer_dict(), key) == @syntax.PdfNull else {
      @failure.reject(
        "redaction-failed", "Clean output unexpectedly retained source trailer data",
      )
    }
  }
  let supplied = @layout.TextProbe::new()
  defer supplied.close()
  for index, page in result.pages {
    let extraction = result.extract_page(0, page.id, supplied, Map([]))
    defer extraction.close()
    guard extraction.displayComplete &&
      extraction.textComplete &&
      extraction.width == plan.pages[index].width &&
      extraction.height == plan.pages[index].height else {
      @failure.reject(
        "redaction-failed", "Clean output could not be reinterpreted completely",
      )
    }
    let text = extraction.glyphs.map(glyph => glyph.encodedText).join("")
    guard text == plan.expectedText[index] else {
      @failure.reject(
        "redaction-failed", "Clean output text does not match its surviving glyphs",
      )
    }
    let selected = regions.filter(region => region.page == self.pages[index].id)
    for glyph in extraction.glyphs {
      let intersects = if glyph.inkQuad.is_empty() {
        !glyph.encodedText.iter().all(c => c.is_whitespace())
      } else {
        let bounds = redaction_bounds(glyph.inkQuad)
        selected.any(region => redaction_intersects(bounds, region))
      }
      guard !glyph.invisible && !intersects else {
        @failure.reject(
          "redaction-failed", "Clean output retained text in a redacted region",
        )
      }
    }
    guard extraction.images.length() == plan.expectedImages[index].length() else {
      @failure.reject(
        "redaction-failed", "Clean output image count does not match its candidate",
      )
    }
    for imageIndex, image in extraction.images {
      guard image.jpeg is None &&
        image.rgba == plan.expectedImages[index][imageIndex] else {
        @failure.reject(
          "redaction-failed", "Clean output pixels do not match the cleaned image data",
        )
      }
    }
  }
}

///|
/// Produce an independent, freshly written copy. Source bytes, state, selection
/// and undo history are never mutated by either preview or export.
pub fn PdfSession::export_redaction(
  self : PdfSession,
  revision : Int32,
  regions : Array[PdfRedactionRegion],
  supplied : @layout.TextProbe,
  profile : Map[String, String],
  decoded? : @layout.Images,
) -> (Bytes, Array[String]) raise @failure.Failure {
  self.redaction_regions(revision, regions)
  pdf_bound(self.budget, () => {
    let plan = self.redaction_plan(
      revision,
      regions,
      supplied,
      profile,
      decoded?,
    )
    defer plan.close()
    let positioned : @layout.PositionedDocument = {
      pages: plan.pages,
      fonts: plan.probe.font_info(),
      links: [],
    }
    let bytes = write(
      positioned,
      plan.probe,
      plan.images,
      self.budget.outputBytes,
      clean_fonts=true,
      text_groups=plan.textGroups,
    )
    self.verify_redaction(bytes, plan, regions)
    (bytes, plan.warnings)
  })
}
