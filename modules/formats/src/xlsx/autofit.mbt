///|
priv struct FitWork {
  mut axes : Int
  mut cells : Int
  mut units : Int
  formulas : FormulaWork
}

///|
fn Session::fit_sizes(
  self : Session,
  current : Sheet,
  sheets : Array[Sheet],
  index : Int,
  calculation : Calculation,
  styles : Array[CellStyle],
  axes : Array[Int],
  probe : @layout.TextProbe,
  profile : Map[String, String],
  work : FitWork,
  rows~ : Bool,
  grow~ : Bool = false,
  parts~ : Map[String, @xml.Document] = self.parts,
) -> Map[Int, Double] raise @failure.Failure {
  work.axes += axes.length()
  guard work.axes <= 4096 else {
    @failure.reject("limit-exceeded", "Automatic fitting exceeds 4096 axes")
  }
  let tree = Tree::new(current.document)
  let root = tree.root("worksheet")
  let conditional = self.conditional_rules(
    current,
    index,
    sheets,
    work.formulas,
    parts~,
  )
  guard conditional.reason.is_empty() else {
    @failure.reject("protected-content", conditional.reason)
  }
  ignore(read_filter(current))
  // shortcut: Measure table effects when their rendering is implemented.
  for node in tree.children.get(root.id).unwrap_or([]) {
    if node.uri != spreadsheet_uri ||
      (
        ["tableParts", "pivotTableParts", "extLst"].contains(node.name) &&
        !tree.children.get(node.id).unwrap_or([]).is_empty()
      ) {
      @failure.reject(
        "protected-content", "Worksheet effects require automatic fitting support",
      )
    }
  }
  let digit = self.digit_width(probe, profile)
  let hidden : Map[(Int, Int), Double] = Map([])
  if tree.one(root.id, "cols") is Some(columns) {
    for col in tree.all(columns.id, "col") {
      if flag(col, "hidden") {
        hidden[(
          natural(col.attribute("min").unwrap_or(""), 16384),
          natural(col.attribute("max").unwrap_or(""), 16384),
        )] = col
          .attribute("width")
          .map(value => dimension(value, 255))
          .unwrap_or(current.dimensions.columns.default_size)
      }
    }
  }
  // Hidden columns keep their underlying width when measuring wrapped row text.
  let dimensions = {
    ..current.dimensions,
    columns: {
      ..current.dimensions.columns,
      spans: current.dimensions.columns.spans.map(span => {
        ..span,
        size: hidden.get((span.first, span.last)).unwrap_or(span.size),
      }),
    },
  }.resolved(digit)
  let format = tree.one(root.id, "sheetFormatPr")
  let fallback = if rows {
    format
    .bind(node => node.attribute("defaultRowHeight"))
    .map(value => dimension(value, 409.5))
    .unwrap_or(15)
  } else {
    current.dimensions.columns.default_size
  }
  let sizes : Map[Int, Double] = Map([])
  for axis in axes {
    sizes[axis] = if rows { fallback } else { 0.0 }
  }
  for cell in current.cells.values() {
    let axis = if rows { cell.address.row } else { cell.address.column }
    if !sizes.contains(axis) {
      continue
    }
    let range = current.cell_range(cell.address)
    if cell.address.row != range.top ||
      cell.address.column != range.left ||
      (if rows { range.top != range.bottom } else { range.left != range.right }) {
      continue
    }
    let style = conditional.applied(
      styles[current.style_at(cell.address)],
      cell.address,
      sheets,
      index,
      calculation.values,
      work.formulas,
    )
    guard cell.read_only.is_empty() && style.diagnostic.is_empty() else {
      @failure.reject(
        "protected-content",
        "Unsupported cell layout: " + cell.address.name(),
      )
    }
    let value = calculation.values
      .get((index, cell.address.name()))
      .unwrap_or(cell.value)
    guard cell.formula is None || value != Blank else {
      @failure.reject(
        "protected-content", "Uncalculated cell requires automatic fitting support",
      )
    }
    if grow && (value == Blank || value is Text(_)) {
      continue
    }
    let text = formatted(value, style.format, self.date1904)
    if rows &&
      text.is_empty() &&
      style.font == self.normal_font &&
      style.size == self.normal_size {
      continue
    }
    if !rows && text.is_empty() {
      continue
    }
    work.cells += 1
    work.units += text.length()
    guard work.cells <= 4096 && work.units <= 262144 else {
      @failure.reject("limit-exceeded", "Automatic fitting text exceeds budget")
    }
    let width = dimensions.columns.position(range.right + 1) -
      dimensions.columns.position(range.left)
    // ONLYOFFICE uses a single line height for a wrapped horizontal merge.
    let content = if text.is_empty() ||
      (rows && range.left != range.right && style.wrap) {
      " "
    } else {
      text
    }
    let block = probe.text_block(
      content,
      @layout.TextStyle::new(style.font, style.size, style.color),
      profile,
      (width - 4.5).max(0.75).min(14400),
      style.wrap && !grow,
    )
    let measured = if rows {
      ((block.height + 3) / 0.75).ceil() * 0.75
    } else {
      block.widths.fold(init=0.0, (a, b) => a.max(b))
    }
    sizes[axis] = sizes[axis].max(measured)
  }
  for axis in axes {
    let measured = sizes[axis]
    sizes[axis] = if rows {
      measured.min(409.5)
    } else if measured == 0 {
      fallback
    } else {
      let pixels = ((measured + 4.5) / 0.75).ceil() - 5
      ((pixels * 256 / digit - (128.0 / digit).floor()).ceil() / 256)
      .max(1.0 / 256)
      .min(255)
    }
    if grow {
      sizes[axis] = sizes[axis].max(current.dimensions.columns.size(axis))
    }
  }
  sizes
}

///|
fn Sheet::fitted_changes(
  self : Sheet,
  sizes : Map[Int, Double],
  rows~ : Bool,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(self.document)
  if rows {
    return self.row_height_changes(tree, sizes, best_fit=true)
  }
  let axes = sizes.keys().to_array()
  axes.sort()
  let spans : Array[AxisSpan] = []
  for axis in axes {
    let size = sizes[axis]
    if spans.last() is Some(span) && span.size == size && span.last + 1 == axis {
      spans[spans.length() - 1] = { ..span, last: axis, }
    } else {
      spans.push({ first: axis, last: axis, size, })
    }
  }
  self.column_width_changes(
    tree,
    axes[0],
    axes.last().unwrap(),
    spans,
    best_fit=true,
  )
}

///|
/// Fit current displayed values, then keep automatic axes updated in later transactions.
pub fn Session::auto_fit(
  self : Session,
  revision : Int,
  sheet : String,
  first : Int,
  last : Int,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  rows~ : Bool,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard first >= 1 &&
    last >= first &&
    last <= (if rows { 1048576 } else { 16384 }) else {
    @failure.reject("invalid-operation", "Invalid automatic dimension range")
  }
  guard last - first < 4096 else {
    @failure.reject("limit-exceeded", "Automatic fitting exceeds 4096 axes")
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.dimension_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let work : FitWork = {
    axes: 0,
    cells: 0,
    units: 0,
    formulas: {
      remaining: 1048576,
      date1904: self.date1904,
      origin: { row: 1, column: 1, },
    },
  }
  let sizes = self.fit_sizes(
    current,
    self.sheets,
    index,
    self.calculation.unwrap(),
    self.styles,
    Array::makei(last - first + 1, offset => first + offset),
    probe,
    profile,
    work,
    rows~,
  )
  let changes = current.fitted_changes(sizes, rows~)
  let (document, edit) = current.document.edit_source(changes)
  if document.source() == current.document.source() {
    self.font_context = Some((probe, profile.copy()))
    return self.query()
  }
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    current.id,
    current.name,
    current.state,
    document,
    self.strings,
    self.styles.length(),
  )
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(current.id, edit)],
    self.selection,
    font_context=Some((probe, profile.copy())),
    fit_work=work,
  )
  self.query()
}
