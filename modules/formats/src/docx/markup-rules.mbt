///|
fn Session::markup_area(
  self : Session,
  selection : Selection,
  mode : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images?,
) -> (Double, Double) raise @failure.Failure {
  let range = self.paragraph_range(
    WordTree::new(self.document()),
    selection,
    structural=true,
    fields=true,
    math=true,
    tables=true,
    notes=true,
  )
  let flow = self.flow()
  let mut width = column_width_for_position(
    flow,
    range.start,
    Some(probe),
    profile,
    images,
  )
  for table in flow.tables {
    for r, row in table.rows {
      for c, paragraphs in row {
        if paragraphs.any(p => p.id == range.start.paragraph) {
          let layout = @layout.paginate(
            probe,
            flow,
            profile,
            images.unwrap_or_else(() => @layout.Images::new()),
          )
          let cell = layout.pages
            .iter()
            .flat_map(page => page.cellAreas.iter())
            .find_first(cell => cell.paragraphs.contains(range.start.paragraph))
            .unwrap_or_else(() => {
              @failure.reject("invalid-position", "Markup cell has no layout")
            })
          let margins = table.cell_insets(r, c)
          width = cell.width - margins.left - margins.right
        }
      }
    }
  }
  let inset = if mode == "merge" {
    let p = self.formatting_paragraphs(self.document(), [range.start.paragraph])[0]
    p.left + p.right + p.first.max(0)
  } else {
    0.0
  }
  (width, inset)
}

///|
fn MarkupInput::rule(
  self : MarkupInput,
  indent : Int,
  width~ : (Bool, Double) = (true, 1),
  stroke~ : String = "808080",
  weight~ : Double = 1.125,
  align~ : String = "center",
  cell~ : Double? = None,
) -> Unit raise @failure.Failure {
  guard self.drawings < 256 && self.paragraphs < 511 else {
    @failure.reject(
      "limit-exceeded", "Markup rules exceed drawing or paragraph budget",
    )
  }
  self.drawings += 1
  // Keep a boundary paragraph when the receiving prefix or suffix contains text.
  if self.paragraphs == 0 && cell is None {
    self.add("<od:p/>")
    self.paragraphs += 1
  }
  self.paragraphs += 1
  self.afterRule = cell is None
  self.add(
    "<od:p><od:pPr>" +
    list_properties(0, 0) +
    "<od:jc od:val=\"\{align}\"/><od:ind od:left=\"\{indent * 20}\" od:right=\"0\" od:firstLine=\"0\"/></od:pPr>",
  )
  if self.mode != "text" {
    // shortcut: flat native rules; add shading with broader shape effect support.
    let area = self.area.unwrap_or_else(() => {
      let value = (self.available)()
      self.area = Some(value)
      value
    })
    let available = cell.unwrap_or(area.0) -
      (if self.mode == "merge" { area.1 } else { indent.to_double() })
    let length = if width.0 { available * width.1 } else { width.1 }
    guard length > 0 && length <= available + 1.0 / 12700 else {
      @failure.reject(
        "layout-overflow", "Horizontal rule exceeds its text area",
      )
    }
    let (length, height, weight) = check_shape_properties(
      "line",
      (length * 12700).floor() / 12700,
      0,
      "",
      stroke,
      weight,
    )
    self.add(
      "<od:r>" +
      shape_markup(self.drawings, "line", length, height, "", stroke, weight) +
      "</od:r>",
    )
  }
  self.add("</od:p>")
}

///|
fn HtmlInput::rule(
  self : HtmlInput,
  id : Int,
  context : HtmlContext,
) -> Unit raise @failure.Failure {
  self.close_paragraph()
  let (percent, width) = html_rule_measure(
    html_table_style(self.document, id, "width").unwrap_or("100%"),
  )
  let (relative, size) = html_rule_measure(
    html_table_style(self.document, id, "height").unwrap_or(
      self.document.get_attribute(id, "size").unwrap_or("1.5"),
    ),
  )
  guard !relative && size <= 1584 else {
    @failure.reject(
      "unsupported-input", "Invalid HTML horizontal rule thickness",
    )
  }
  let align = html_table_style(self.document, id, "text-align")
    .unwrap_or(self.document.get_attribute(id, "align").unwrap_or("center"))
    .trim()
    .to_owned()
    .to_lower()
  guard ["left", "center", "right"].contains(align) else {
    @failure.reject(
      "unsupported-input", "Invalid HTML horizontal rule alignment",
    )
  }
  self.output.rule(
    context.quote * 18 +
    context.list.map(pair => (pair.1 + 1) * 36).unwrap_or(0),
    width=(percent, width),
    stroke=html_rgb(
      html_table_style(self.document, id, "color")
      .unwrap_or("#808080")
      .trim()
      .to_owned(),
    ),
    weight=size,
    align~,
    cell=context.cellWidth,
  )
}

///|
fn html_rule_measure(source : String) -> (Bool, Double) raise @failure.Failure {
  let source = source.trim().to_owned().to_lower()
  let percent = source.has_suffix("%")
  let points = source.has_suffix("pt")
  let pixels = source.has_suffix("px")
  let suffix = if percent { 1 } else if points || pixels { 2 } else { 0 }
  let number = @string.parse_double(source[:source.length() - suffix]) catch {
    _ =>
      @failure.reject("unsupported-input", "Invalid HTML horizontal rule size")
  }
  let value = number *
    (if percent { 0.01 } else if points { 1.0 } else { 0.75 })
  guard !value.is_nan() &&
    !value.is_inf() &&
    value > 0 &&
    value <= (if percent { 1.0 } else { 14400.0 }) else {
    @failure.reject(
      "unsupported-input", "HTML horizontal rule size exceeds bounds",
    )
  }
  (percent, value)
}
