///|
priv struct Cid {
  glyph : Int
  text : String
}

///|
priv struct FontSubset {
  codes : Map[String, Int]
  cids : Array[Cid]
  remap : @subsetter.GlyphRemapper
}

///|
fn glyph_text(run : @layout.PlacedRun, index : Int) -> String {
  let cluster = run.glyphs[index].cluster
  if index > 0 && run.glyphs[index - 1].cluster == cluster {
    return ""
  }
  let mut end = run.text.length()
  for glyph in run.glyphs {
    if glyph.cluster > cluster {
      end = end.min(glyph.cluster)
    }
  }
  run.text[cluster:end].to_owned()
}

///|
fn cid_key(glyph : Int, text : String) -> String {
  "\{glyph}:\{text}"
}

///|
fn collect_fonts(
  layout : @layout.Layout,
) -> Map[Int, FontSubset] raise @failure.Failure {
  let fonts : Map[Int, FontSubset] = Map([])
  for page in layout.pages {
    for line in page.lines {
      for run in line.runs {
        for index, glyph in run.glyphs {
          let subset = fonts.get_or_init(glyph.font, () => {
            codes: Map([]),
            cids: [{ glyph: 0, text: "", }],
            remap: @subsetter.GlyphRemapper::new(),
          })
          let text = glyph_text(run, index)
          let key = cid_key(glyph.id.reinterpret_as_int(), text)
          if subset.codes.get(key) is None {
            guard subset.cids.length() < 65536 else {
              @failure.reject("limit-exceeded", "PDF CID budget exceeded")
            }
            subset.codes[key] = subset.cids.length()
            subset.cids.push({ glyph: glyph.id.reinterpret_as_int(), text, })
            ignore(subset.remap.remap(glyph.id.reinterpret_as_int()))
          }
        }
      }
    }
  }
  fonts
}

///|
fn install_font(
  document : @pdflite.PdfDocument,
  subset : FontSubset,
  source : Bytes,
  index : Int,
  info : @layout.FontInfo,
  widths : Array[Double],
) -> Int raise @pdfcore.PdfError {
  let bytes = @subsetter.subset(source, 0, subset.remap) catch {
    _ => raise @pdfcore.HardError("TrueType font subsetting failed")
  }
  let base = "ODAAAA+Font\{index}"
  let file = document.add_object(
    stream(bytes, [("Length1", @syntax.PdfInteger(bytes.length()))]),
  )
  let descriptor = document.add_object(
    dict([
      ("Type", tag("FontDescriptor")),
      ("FontName", tag(base)),
      ("Flags", @syntax.PdfInteger(4)),
      (
        "FontBBox",
        @syntax.PdfArray(
          info.bbox.map(value => {
            @syntax.PdfReal(value.to_double() * 1000 / info.upem.to_double())
          }),
        ),
      ),
      ("ItalicAngle", @syntax.PdfReal(info.italicAngle)),
      (
        "Ascent",
        @syntax.PdfReal(info.ascent.to_double() * 1000 / info.upem.to_double()),
      ),
      (
        "Descent",
        @syntax.PdfReal(
          -info.descent.to_double() * 1000 / info.upem.to_double(),
        ),
      ),
      (
        "CapHeight",
        @syntax.PdfReal(
          info.capHeight.to_double() * 1000 / info.upem.to_double(),
        ),
      ),
      ("StemV", @syntax.PdfInteger(80)),
      ("FontFile2", @syntax.PdfIndirect(file)),
    ]),
  )
  let mapping : Array[Byte] = []
  for cid in subset.cids {
    let gid = subset.remap.get(cid.glyph).unwrap_or(0)
    mapping.push((gid >> 8).to_byte())
    mapping.push((gid & 255).to_byte())
  }
  let gid_map = document.add_object(stream(Bytes::from_array(mapping), []))
  let descendant = document.add_object(
    dict([
      ("Type", tag("Font")),
      ("Subtype", tag("CIDFontType2")),
      ("BaseFont", tag(base)),
      (
        "CIDSystemInfo",
        dict([
          ("Registry", @syntax.PdfString(b"Adobe")),
          ("Ordering", @syntax.PdfString(b"Identity")),
          ("Supplement", @syntax.PdfInteger(0)),
        ]),
      ),
      ("FontDescriptor", @syntax.PdfIndirect(descriptor)),
      ("CIDToGIDMap", @syntax.PdfIndirect(gid_map)),
      ("DW", @syntax.PdfInteger(1000)),
      (
        "W",
        @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfArray(widths.map(width => @syntax.PdfReal(width))),
        ]),
      ),
    ]),
  )
  let cmap = StringBuilder()
  cmap.write_string(
    "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /ODUnicode def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n",
  )
  for start = 1; start < subset.cids.length(); start = start + 100 {
    let end = (start + 100).min(subset.cids.length())
    cmap <+ "\{end - start} beginbfchar\n"
    for code in start..<end {
      cmap <+ "<\{hex16(code)}> <\{unicode_hex(subset.cids[code].text)}>\n"
    }
    cmap.write_string("endbfchar\n")
  }
  cmap.write_string(
    "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n",
  )
  let unicode = document.add_object(stream(@utf8.encode(cmap.to_string()), []))
  document.add_object(
    dict([
      ("Type", tag("Font")),
      ("Subtype", tag("Type0")),
      ("BaseFont", tag(base)),
      ("Encoding", tag("Identity-H")),
      ("DescendantFonts", @syntax.PdfArray([@syntax.PdfIndirect(descendant)])),
      ("ToUnicode", @syntax.PdfIndirect(unicode)),
    ]),
  )
}
