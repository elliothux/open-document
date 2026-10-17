///|
fn header_sections(
  source : String,
  page : Int,
  total : Int,
  sheet : String,
) -> Array[String] raise @failure.Failure {
  guard source.length() <= 255 && @xml.valid_text(source) else {
    @failure.reject(
      "invalid-header-footer", "Header/footer text must contain at most 255 valid XML text units",
    )
  }
  let sections = [StringBuilder(), StringBuilder(), StringBuilder()]
  let mut section = 1
  let mut offset = 0
  while offset < source.length() {
    let character = source.get_char(offset).unwrap()
    offset += if character.to_int() > 0xffff { 2 } else { 1 }
    if character != '&' {
      sections[section].write_char(character)
      continue
    }
    guard offset < source.length() else {
      @failure.reject("unsupported-print", "Escape a literal ampersand as &&")
    }
    let code = source[offset]
    offset += 1
    match code {
      76 => section = 0
      67 => section = 1
      82 => section = 2
      38 => sections[section].write_char('&')
      80 => sections[section].write_string(page.to_string())
      78 => sections[section].write_string(total.to_string())
      65 => sections[section].write_string(sheet)
      _ =>
        @failure.reject(
          "unsupported-print", "Unsupported header/footer control code",
        )
    }
  }
  sections.map(section => section.to_string())
}

///|
fn print_first_page(sheet : Sheet) -> Int raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let node = tree.one(tree.root("worksheet").id, "pageSetup")
  let first = if node.map(n => flag(n, "useFirstPageNumber")).unwrap_or(false) {
    print_integer(node, "firstPageNumber", 1)
  } else {
    1
  }
  guard first >= 1 && first <= 2147482623 else {
    @failure.reject(
      "unsupported-print", "Print page number exceeds supported bounds",
    )
  }
  first
}

///|
fn Session::paint_header_footer(
  self : Session,
  sheet : String,
  settings : HeaderFooter,
  setup : @layout.PageSetup,
  scale : Double,
  ordinal : Int,
  number : Int,
  total : Int,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Array[@layout.PositionedPrimitive], Int) raise @failure.Failure {
  let (header, footer) = if settings.differentFirst && ordinal == 0 {
    (settings.firstHeader, settings.firstFooter)
  } else if settings.differentOddEven && ordinal % 2 == 1 {
    (settings.evenHeader, settings.evenFooter)
  } else {
    (settings.oddHeader, settings.oddFooter)
  }
  if header.is_empty() && footer.is_empty() {
    return ([], 0)
  }
  let scale = if settings.scaleWithDoc { scale } else { 1.0 }
  let left = (if settings.alignWithMargins {
      setup.left
    } else {
      17.8 * 72 / 25.4
    }) /
    scale
  let right = (if settings.alignWithMargins {
      setup.right
    } else {
      17.8 * 72 / 25.4
    }) /
    scale
  let width = setup.width / scale - left - right
  guard width > 0 && width <= 14400 else {
    @failure.reject(
      "print-overflow", "Header/footer width exceeds supported page area",
    )
  }
  let page : PagePaint = {
    width: setup.width,
    height: setup.height,
    fills: [],
    bars: [],
    strokes: [],
    texts: [],
  }
  let mut units = 0
  for (value, footer) in [(header, false), (footer, true)] {
    for alignment, text in header_sections(value, number, total, sheet) {
      if text.is_empty() {
        continue
      }
      units += text.length()
      let block = probe.text_block(
        text,
        @layout.TextStyle::new(self.normal_font, self.normal_size, "000000"),
        profile,
        width,
        true,
      )
      let top = if footer {
        (setup.height - settings.footerMargin) / scale - block.height
      } else {
        settings.headerMargin / scale
      }
      guard top >= 0 &&
        top + block.height <= setup.height / scale &&
        block.widths.all(w => w <= width + 0.000001) else {
        @failure.reject(
          "print-overflow", "Header/footer content exceeds the page",
        )
      }
      for index, text in block.texts {
        let x = left +
          (if alignment == 2 {
            width - block.widths[index]
          } else if alignment == 1 {
            (width - block.widths[index]) / 2
          } else {
            0
          })
        page.texts.push(
          (
            {
              ..text,
              runs: text.runs.map(run => {
                ..run,
                x: run.x + x,
                baseline: run.baseline + top,
              }),
            },
            {
              x: 0,
              y: 0,
              width: setup.width / scale,
              height: setup.height / scale,
            },
          ),
        )
      }
    }
  }
  let primitives = page.positioned().primitives
  if primitives.is_empty() {
    return ([], units)
  }
  (
    if scale == 1 {
      primitives
    } else {
      [
        @layout.Transform({ a: scale, b: 0, c: 0, d: scale, e: 0, f: 0, }),
        ..primitives,
        @layout.Restore,
      ]
    },
    units,
  )
}
