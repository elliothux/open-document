///|
fn watermark_color(
  color : String,
  opacity : Double,
  background : String,
) -> String {
  let digits = "0123456789abcdef"
  let result = StringBuilder()
  for i in 0..<3 {
    let first = try! @string.parse_int(color[i * 2:i * 2 + 2], base=16)
    let second = try! @string.parse_int(background[i * 2:i * 2 + 2], base=16)
    let value = (first.to_double() * opacity +
      second.to_double() * (1 - opacity))
      .round()
      .to_int()
    result.write_char(digits.get_char(value / 16).unwrap())
    result.write_char(digits.get_char(value % 16).unwrap())
  }
  result.to_string()
}

///|
/// Produces the document's shared vector output, including repeated header watermarks.
pub fn Session::page_positioned(
  self : Session,
  layout : @layout.Layout,
  probe : @layout.TextProbe,
) -> @layout.PositionedDocument raise @failure.Failure {
  guard layout.revision == self.revision else {
    @failure.reject("stale-layout", "Watermarks require the current layout")
  }
  let tree = WordTree::new(self.display_document())
  let base = layout.positioned()
  if !tree.order.any(id => {
      tree.nodes[id].uri == word_uri && tree.nodes[id].name == "headerReference"
    }) {
    return base
  }
  let sections = tree.page_sections()
  let headers = self.watermark_headers(tree)
  let marks : Map[String, WatermarkSource?] = Map([])
  guard layout.pageSections.length() == base.pages.length() &&
    layout.sectionNumbering.length() == sections.length() else {
    @failure.reject(
      "stale-layout", "Watermarks require page section identities",
    )
  }
  let paints : Map[(Int, String), Array[@layout.PositionedPrimitive]] = Map([])
  let pages = base.pages.mapi((index, positioned) => {
    guard layout.pageSections[index] is Some((section, localPage)) else {
      return positioned
    }
    let (first, even) = self.running_options(tree, sections[section])
    let variant = layout.sectionNumbering[section].variant(
      localPage, first, even,
    )
    guard headers[section].get(variant) is Some(part) else { return positioned }
    if !marks.contains(part) {
      marks[part] = WordTree::new(self.part_xml(part))
        .header_watermark()
        .map(mark => { ..mark, value: self.watermark_value(part, mark.value), })
    }
    guard marks[part] is Some(mark) else { return positioned }
    let paint = if paints.get((section, variant)) is Some(paint) {
      paint
    } else {
      let source_page = sections[section]
        .map(id => tree.page_values(id, default_page_setup()))
        .unwrap_or(default_page_setup())
      let page = {
        ..source_page,
        width: positioned.width,
        height: positioned.height,
      }
      let paint = watermark_paint(mark, page, layout, probe)
      paints[(section, variant)] = paint
      paint
    }
    let background = if layout.background.to_lower() == "ffffff" {
      0
    } else {
      1
    }
    {
      ..positioned,
      primitives: [
        ..positioned.primitives[:background],
        ..paint,
        ..positioned.primitives[background:],
      ],
    }
  })
  { ..base, fonts: probe.font_info(), pages, }
}

///|
fn watermark_paint(
  mark : WatermarkSource,
  page : @layout.PageSetup,
  layout : @layout.Layout,
  probe : @layout.TextProbe,
) -> Array[@layout.PositionedPrimitive] raise @failure.Failure {
  if mark.value is Picture(Resource(key), width, height, opacity) {
    return [
      @layout.Image(
        {
          key,
          x: page.left + (page.width - page.left - page.right - width) / 2,
          y: page.top + (page.height - page.top - page.bottom - height) / 2,
          width,
          height,
        },
        opacity,
      ),
    ]
  }
  guard mark.value is Text(value) else {
    @failure.reject("invalid-operation", "Unresolved watermark image")
  }
  let block = probe.text_block(
    value.text,
    value.style(
      color=watermark_color(value.color, value.opacity, layout.background),
    ),
    layout.profile,
    14400,
    false,
  )
  let angle = if value.diagonal { -@math.PI / 4 } else { 0.0 }
  let x = page.left + (page.width - page.left - page.right) / 2
  let y = page.top + (page.height - page.top - page.bottom) / 2
  let c = @math.cos(angle)
  let s = @math.sin(angle)
  [
    @layout.Transform({
      a: c,
      b: s,
      c: -s,
      d: c,
      e: x - c * block.widths[0] / 2 + s * block.height / 2,
      f: y - s * block.widths[0] / 2 - c * block.height / 2,
    }),
    ..block.lines.flatten(),
    @layout.Restore,
  ]
}
