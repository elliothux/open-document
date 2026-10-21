///|
priv struct HtmlCell {
  node : Int
  row : Int
  rows : Int
  columns : Int
  context : HtmlContext
}

///|
fn html_table_style(
  document : @html5.Document,
  id : Int,
  name : String,
) -> String? {
  let mut value = document.get_attribute(id, name)
  for
    declaration in document.get_attribute(id, "style").unwrap_or("").split(";") {
    if declaration.split_once(":") is Some((key, item)) &&
      key.trim().to_owned().to_lower() == name {
      value = Some(item.trim().to_owned())
    }
  }
  value
}

///|
fn html_table_span(
  document : @html5.Document,
  id : Int,
  name : String,
  maximum : Int,
) -> Int raise @failure.Failure {
  let value = document.get_attribute(id, name).unwrap_or("1").trim().to_owned()
  let span = @string.parse_int(value) catch {
    _ => @failure.reject("unsupported-input", "Invalid HTML table span")
  }
  guard span >= (if name == "rowspan" { 0 } else { 1 }) && span <= maximum else {
    @failure.reject("limit-exceeded", "HTML table span exceeds grid budget")
  }
  span
}

///|
fn HtmlInput::table_rows(
  self : HtmlInput,
  id : Int,
  context : HtmlContext,
  depth : Int,
) -> Array[(Int, HtmlContext, Int)] raise @failure.Failure {
  guard self.document.get_node(id) is Some(ElementNode(table)) else {
    @failure.reject("unsupported-input", "Missing HTML table")
  }
  let rows : Array[(Int, HtmlContext, Int)] = []
  for child in table.children {
    let tag = self.document.get_tag_name(child).unwrap_or("")
    if tag.is_empty() || html_ignored_element(tag) || tag == "colgroup" {
      continue
    }
    guard ["thead", "tbody", "tfoot"].contains(tag) else {
      @failure.reject(
        "unsupported-input", "HTML tables require ordinary row groups",
      )
    }
    self.output.visit(depth + 1)
    let group = html_style(self.document, child, context)
    if group.hidden || self.document.has_attribute(child, "hidden") {
      continue
    }
    guard self.document.get_node(child) is Some(ElementNode(element)) else {
      @failure.reject("unsupported-input", "Missing HTML row group")
    }
    let visible : Array[(Int, HtmlContext)] = []
    for row in element.children {
      let tag = self.document.get_tag_name(row).unwrap_or("")
      if tag.is_empty() || html_ignored_element(tag) {
        continue
      }
      guard tag == "tr" else {
        @failure.reject("unsupported-input", "HTML row groups require rows")
      }
      self.output.visit(depth + 2)
      let context = html_style(self.document, row, group)
      if !context.hidden && !self.document.has_attribute(row, "hidden") {
        visible.push((row, context))
      }
    }
    let end = rows.length() + visible.length()
    guard end <= 1000 else {
      @failure.reject("limit-exceeded", "HTML table exceeds row budget")
    }
    for (row, context) in visible {
      rows.push((row, context, end))
    }
  }
  guard !rows.is_empty() else {
    @failure.reject("unsupported-input", "HTML table has no visible rows")
  }
  rows
}

///|
fn HtmlInput::table(
  self : HtmlInput,
  id : Int,
  context : HtmlContext,
  depth : Int,
) -> Unit raise @failure.Failure {
  guard !self.inTable else {
    @failure.reject("unsupported-input", "Nested HTML tables require support")
  }
  self.close_paragraph()
  let context = {
    ..context,
    quote: 0,
    level: 0,
    list: None,
    first: Ref(false),
    heading: 0,
  }
  let rows = self.table_rows(id, context, depth)
  let slots = Array::makei(rows.length(), _ => Array::make(63, -1))
  let cells : Array[HtmlCell] = []
  let mut columns = 0
  for r, (node, context, end) in rows {
    guard self.document.get_node(node) is Some(ElementNode(row)) else {
      @failure.reject("unsupported-input", "Missing HTML row")
    }
    let mut column = 0
    for cell in row.children {
      let tag = self.document.get_tag_name(cell).unwrap_or("")
      if tag.is_empty() || html_ignored_element(tag) {
        continue
      }
      guard ["td", "th"].contains(tag) else {
        @failure.reject("unsupported-input", "HTML rows require ordinary cells")
      }
      self.output.visit(depth + 3)
      let context = html_style(self.document, cell, context)
      if context.hidden || self.document.has_attribute(cell, "hidden") {
        continue
      }
      while column < 63 && slots[r][column] >= 0 {
        column += 1
      }
      let across = html_table_span(self.document, cell, "colspan", 63)
      let span = html_table_span(self.document, cell, "rowspan", 1000)
      let down = if span == 0 { end - r } else { span.min(end - r) }
      guard column + across <= 63 else {
        @failure.reject("limit-exceeded", "HTML table exceeds column budget")
      }
      let owner = cells.length()
      for rr in r..<(r + down) {
        for cc in column..<(column + across) {
          guard slots[rr][cc] < 0 else {
            @failure.reject("unsupported-input", "Overlapping HTML cell spans")
          }
          slots[rr][cc] = owner
        }
      }
      cells.push({ node: cell, row: r, rows: down, columns: across, context, })
      column += across
      columns = columns.max(column)
    }
  }
  let widths = self.table_columns(id, depth)
  columns = columns.max(widths.length())
  guard columns > 0 && rows.length().to_int64() * columns.to_int64() <= 4096L else {
    @failure.reject("limit-exceeded", "HTML table exceeds cell budget")
  }
  self.output.add(
    "<od:tbl><od:tblPr>" +
    html_table_width(self.document, id) +
    "<od:tblLayout od:type=\"fixed\"/></od:tblPr><od:tblGrid>",
  )
  let widths = Array::makei(columns, i => widths.get(i).unwrap_or(1440))
  guard widths.fold(init=0, (sum, width) => sum + width) <= 288000 else {
    @failure.reject("limit-exceeded", "HTML table grid exceeds width budget")
  }
  for width in widths {
    self.output.add("<od:gridCol od:w=\"\{width}\"/>")
  }
  self.output.add("</od:tblGrid>")
  self.inTable = true
  for r in 0..<rows.length() {
    self.output.add("<od:tr>")
    for column = 0; column < columns; {
      let cell = slots[r][column]
      let owner = cells.get(cell)
      let span = owner.map(c => c.columns).unwrap_or(1)
      let width = widths[column:column + span].fold(init=0, (sum, width) => {
        sum + width
      })
      self.output.add(
        "<od:tc><od:tcPr><od:tcW od:type=\"dxa\" od:w=\"\{width}\"/>",
      )
      if span > 1 {
        self.output.add("<od:gridSpan od:val=\"\{span}\"/>")
      }
      if owner is Some(cell) {
        if cell.rows > 1 {
          self.output.add(
            "<od:vMerge od:val=\"\{if r == cell.row { "restart" } else { "continue" }}\"/>",
          )
        }
        self.output.add(html_cell_properties(self.document, cell.node, id))
      }
      self.output.add("</od:tcPr>")
      let before = self.output.paragraphs
      let context = owner.map(c => c.context).unwrap_or(context)
      if owner is Some(cell) && cell.row == r {
        guard self.document.get_node(cell.node) is Some(ElementNode(node)) else {
          @failure.reject("unsupported-input", "Missing HTML cell")
        }
        for child in node.children {
          self.walk(child, context, depth + 4)
        }
      }
      if self.output.paragraphs == before {
        self.paragraph(context)
      }
      self.close_paragraph()
      self.output.add("</od:tc>")
      continue column + span
    }
    self.output.add("</od:tr>")
  }
  self.inTable = false
  self.output.add("</od:tbl>")
}

///|
fn HtmlInput::table_columns(
  self : HtmlInput,
  id : Int,
  depth : Int,
) -> Array[Int] raise @failure.Failure {
  guard self.document.get_node(id) is Some(ElementNode(table)) else {
    @failure.reject("unsupported-input", "Missing HTML table")
  }
  let widths : Array[Int] = []
  for child in table.children {
    if self.document.get_tag_name(child) != Some("colgroup") {
      continue
    }
    self.output.visit(depth + 1)
    guard self.document.get_node(child) is Some(ElementNode(group)) else {
      @failure.reject("unsupported-input", "Missing HTML column group")
    }
    let cols = group.children.filter(id => {
      self.document.get_tag_name(id) is Some(_)
    })
    let cols = if cols.is_empty() { [child] } else { cols }
    for col in cols {
      guard col == child || self.document.get_tag_name(col) == Some("col") else {
        @failure.reject(
          "unsupported-input", "HTML column groups require columns",
        )
      }
      if col != child {
        self.output.visit(depth + 2)
      }
      let source = html_table_style(self.document, col, "width")
      let source = if source is Some(_) {
        source
      } else {
        html_table_style(self.document, child, "width")
      }
      let (percent, width) = html_table_measure(source.unwrap_or("72pt"))
      guard !percent else {
        @failure.reject(
          "unsupported-input", "HTML column widths require points or pixels",
        )
      }
      let span = html_table_span(self.document, col, "span", 63)
      guard widths.length() + span <= 63 else {
        @failure.reject("limit-exceeded", "HTML table exceeds column budget")
      }
      for _ in 0..<span {
        widths.push(width)
      }
    }
  }
  widths
}

///|
fn html_table_width(
  document : @html5.Document,
  id : Int,
) -> String raise @failure.Failure {
  let source = html_table_style(document, id, "width")
    .unwrap_or("100%")
    .trim()
    .to_owned()
    .to_lower()
  let (percent, width) = html_table_measure(source)
  "<od:tblW od:type=\"\{if percent { "pct" } else { "dxa" }}\" od:w=\"\{width}\"/>"
}

///|
fn html_table_measure(source : String) -> (Bool, Int) raise @failure.Failure {
  let source = source.trim().to_owned().to_lower()
  let percent = source.has_suffix("%")
  let points = source.has_suffix("pt")
  let pixels = source.has_suffix("px")
  let units = if percent { 1 } else if points || pixels { 2 } else { 0 }
  let value = @string.parse_double(source[:source.length() - units]) catch {
    _ => @failure.reject("unsupported-input", "Invalid HTML table width")
  }
  let width = value *
    (if percent { 50.0 } else if points { 20.0 } else { 15.0 })
  guard !width.is_nan() &&
    !width.is_inf() &&
    width > 0 &&
    width <= (if percent { 5000 } else { 288000 }) else {
    @failure.reject("unsupported-input", "HTML table width exceeds bounds")
  }
  (percent, width.round().to_int().max(1))
}

///|
fn html_cell_properties(
  document : @html5.Document,
  cell : Int,
  table : Int,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  let fill = html_table_style(document, cell, "background-color")
  let fill = if fill is Some(_) {
    fill
  } else {
    document.get_attribute(cell, "bgcolor")
  }
  if fill is Some(color) {
    out.write_string(
      "<od:shd od:val=\"clear\" od:fill=\"\{html_rgb(color.trim().to_owned())}\"/>",
    )
  }
  let align = html_table_style(document, cell, "vertical-align")
  let align = if align is Some(_) {
    align
  } else {
    document.get_attribute(cell, "valign")
  }
  if align is Some(value) {
    let value = value.to_lower()
    guard ["top", "middle", "bottom", "baseline"].contains(value) else {
      @failure.reject("unsupported-input", "Unsupported HTML cell alignment")
    }
    out.write_string(
      "<od:vAlign od:val=\"\{if value == "middle" { "center" } else if value == "baseline" { "top" } else { value }}\"/>",
    )
  }
  if document.get_attribute(table, "border") is Some(value) {
    let width = @string.parse_double(value) catch {
      _ => @failure.reject("unsupported-input", "Invalid HTML table border")
    }
    guard !width.is_nan() && width >= 0 && width <= 16 else {
      @failure.reject("unsupported-input", "HTML table border exceeds bounds")
    }
    if width > 0 {
      out.write_string("<od:tcBorders>")
      for edge in ["top", "left", "bottom", "right"] {
        out.write_string(
          "<od:\{edge} od:val=\"single\" od:sz=\"\{(width * 6).round().to_int().max(2)}\" od:color=\"000000\"/>",
        )
      }
      out.write_string("</od:tcBorders>")
    }
  }
  out.to_string()
}
