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
  let sections = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri && tree.nodes[id].name == "sectPr"
  })
  let section = sections.last()
  let (first, even) = self.running_options(tree, section)
  let marks : Map[String, WatermarkSource] = Map([])
  for id in section.map(id => tree.children[id]).unwrap_or([]) {
    let node = tree.nodes[id]
    if node.uri == word_uri && node.name == "headerReference" {
      let variant = node.attribute("type", uri=word_uri).unwrap_or("")
      if (variant == "first" && !first) || (variant == "even" && !even) {
        continue
      }
      let part = self.running_part(tree, id, "header")
      let story = WordTree::new(self.part_xml(part))
      let blocks = story.children[0].filter(id => story.watermark_block(id))
      guard blocks.length() <= 1 else {
        @failure.reject("protected-content", "Duplicate header watermarks")
      }
      if blocks is [id] {
        marks[variant] = story.watermark_source(id)
      }
    }
  }
  if marks.is_empty() {
    return base
  }
  guard sections.length() <= 1 else {
    @failure.reject(
      "unsupported-layout", "Multi-section watermarks require support",
    )
  }
  let source_page = section
    .map(id => tree.page_values(id, default_page_setup()))
    .unwrap_or(default_page_setup())
  let page = {
    ..source_page,
    width: layout.pages[0].width,
    height: layout.pages[0].height,
  }
  let numbering = tree.page_numbering(section)
  let paints : Map[String, Array[@layout.PositionedPrimitive]] = Map([])
  for variant, mark in marks {
    let value = mark.value
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
    paints[variant] = [
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
  {
    ..base,
    fonts: probe.font_info(),
    pages: base.pages.mapi((index, page) => {
      let paint = paints
        .get(numbering.variant(index, first, even))
        .unwrap_or([])
      let background = if layout.background.to_lower() == "ffffff" {
        0
      } else {
        1
      }
      {
        ..page,
        primitives: [
          ..page.primitives[:background],
          ..paint,
          ..page.primitives[background:],
        ],
      }
    }),
  }
}
