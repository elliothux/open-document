///|
fn Session::sheet_edit_reason(
  self : Session,
  structure~ : Bool = true,
  analysis~ : Bool = false,
) -> String {
  try {
    if !self.read_only.is_empty() {
      return self.read_only
    }
    let tree = Tree::new(self.workbook)
    let root = tree.root("workbook")
    if structure &&
      tree
      .one(root.id, "workbookProtection")
      .map(node => flag(node, "lockStructure"))
      .unwrap_or(false) {
      return "Workbook structure is protected"
    }
    for node in tree.children.get(root.id).unwrap_or([]) {
      if analysis &&
        node.name == "extLst" &&
        node.uri == spreadsheet_uri &&
        self.analysis_workbook_extension(tree, node) {
        continue
      }
      if node.uri != spreadsheet_uri ||
        (
          ["extLst", "customWorkbookViews"].contains(node.name) &&
          !tree.children.get(node.id).unwrap_or([]).is_empty()
        ) {
        return "Workbook extensions or custom views require sheet structure support"
      }
    }
    if tree.one(root.id, "definedNames") is Some(names) {
      for name in tree.all(names.id, "definedName") {
        if name.attribute("localSheetId") is Some(scope) {
          ignore(natural(scope, self.sheets.length() - 1))
        }
        let tokens = formula_tokens(name.text)
        for index, token in tokens {
          if token is Operator("!") && index > 0 {
            if (tokens[index - 1] is Quoted(value, true) && value.contains(":")) ||
              (index > 1 && tokens[index - 2] is Operator(":")) {
              return "Three-dimensional name references require sheet structure support"
            }
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn sheet_reference_formula(
  text : String,
  old : String,
  name : String?,
) -> String raise @failure.Failure {
  let spans : Array[(Int, Int)] = []
  let tokens = formula_tokens(text, spans~)
  let quoted = name
    .map(name => "'" + name.replace_all(old="'", new="''") + "'")
    .unwrap_or("#REF!")
  let ranges : Array[(Int, Int)] = []
  let mut units = text.length()
  for index, token in tokens {
    if token is Operator("!") && index > 0 {
      let value = match tokens[index - 1] {
        Word(value) | Quoted(value, true) => value
        _ => continue
      }
      if value.to_lower() == old.to_lower() {
        let range = if name is Some(_) {
          spans[index - 1]
        } else {
          guard index + 1 < tokens.length() &&
            (tokens[index + 1] is Word(_) || tokens[index + 1] is Numeric(_, _)) else {
            @failure.reject(
              "protected-content", "Unsupported deleted worksheet reference",
            )
          }
          let mut last = index + 1
          if tokens.get(last + 1) is Some(Operator(":")) {
            guard tokens.get(last + 2) is Some(Word(_) | Numeric(_, _)) else {
              @failure.reject(
                "protected-content", "Unsupported deleted worksheet range",
              )
            }
            last += 2
          }
          (spans[index - 1].0, spans[last].1)
        }
        units += quoted.length() - (range.1 - range.0)
        ranges.push(range)
      }
    }
  }
  guard units <= 8192 else {
    @failure.reject("limit-exceeded", "Renamed formula exceeds source budget")
  }
  if ranges.is_empty() {
    return text
  }
  let out = StringBuilder()
  let mut cursor = 0
  for (start, end) in ranges {
    out.write_view(text[cursor:start])
    out.write_string(quoted)
    cursor = end
  }
  out.write_view(text[cursor:])
  out.to_string()
}

///|
fn Session::sheet_rename_reason(
  self : Session,
  structure~ : Bool = true,
  tables~ : Bool = false,
  pivots~ : Bool = false,
  sparklines~ : Bool = false,
  pictures~ : Bool = false,
  charts~ : Bool = false,
  analysis~ : Bool = false,
  threads~ : Bool = false,
) -> String {
  try {
    let reason = self.sheet_edit_reason(structure~, analysis~)
    if !reason.is_empty() {
      return reason
    }
    let analysis_parts = if analysis { self.analysis_parts() } else { [] }
    for rel in self.relationships() {
      if analysis &&
        !rel.external &&
        analysis_parts.contains(rel.target) &&
        (
          (
            rel.owner == self.main &&
            [
              relationship_uri + "pivotCacheDefinition",
              slicer_relationship_uri + "slicerCache",
              timeline_relationship_uri + "TimelineCache",
            ].contains(rel.kind)
          ) ||
          (
            self.sheets.any(sheet => sheet.id == rel.owner) &&
            [
              relationship_uri + "pivotTable",
              slicer_relationship_uri + "slicer",
              timeline_relationship_uri + "Timeline",
            ].contains(rel.kind)
          )
        ) {
        continue
      }
      if rel.owner == self.main &&
        !(threads && rel.kind == thread_relationship_uri + "person") &&
        !(pivots && rel.kind == relationship_uri + "pivotCacheDefinition") &&
        !["worksheet", "styles", "sharedStrings", "theme", "calcChain"].any(kind => {
          rel.kind == relationship_uri + kind
        }) {
        return "Workbook resource references require renaming support"
      }
      if self.sheets.any(sheet => sheet.id == rel.owner) &&
        !(threads && rel.kind == thread_relationship_uri + "threadedComment") &&
        !(pivots && rel.kind == relationship_uri + "pivotTable") &&
        !(tables && rel.kind == relationship_uri + "table") &&
        !(pictures && rel.kind == relationship_uri + "drawing") &&
        !["hyperlink", "comments", "vmlDrawing"].any(kind => {
          rel.kind == relationship_uri + kind
        }) {
        return "Worksheet resource references require renaming support"
      }
    }
    for sheet in self.sheets {
      ignore(self.read_sheet_notes(sheet, allow_threads=threads))
      if threads {
        self.check_thread_fallbacks(sheet, self.read_sheet_threads(sheet))
      }
      let tree = Tree::new(sheet.document)
      let root = tree.root("worksheet")
      if pictures && tree.one(root.id, "drawing") is Some(_) {
        guard self.font_context is Some((probe, profile)) else {
          return "Measure worksheet picture anchors with an explicit font profile before structural editing"
        }
        self.check_sheet_pictures(sheet, probe, profile, charts~)
      }
      ignore(read_filter(sheet))
      self.check_sort_metadata(tree)
      let filter = tree.one(root.id, "autoFilter")
      let sparkline = if sparklines &&
        sparkline_reason(sheet, self.sheets).is_empty() &&
        tree.one(root.id, "extLst") is Some(extension) &&
        sparkline_extension(tree, extension) {
        Some(extension)
      } else {
        None
      }
      let controls = if analysis &&
        tree.one(root.id, "extLst") is Some(extension) &&
        extension.attributes.is_empty() &&
        extension.text.trim().is_empty() &&
        (
          self.timeline_extension(sheet, tree, extension) ||
          self.slicer_extension(sheet, tree, extension)
        ) {
        Some(extension)
      } else {
        None
      }
      for node in tree.children.get(root.id).unwrap_or([]) {
        if node.uri != spreadsheet_uri ||
          (
            !(tables && node.name == "tableParts") &&
            !(pictures && node.name == "drawing") &&
            ![
              "sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData",
              "mergeCells", "sheetProtection", "pageMargins", "pageSetup", "printOptions",
              "headerFooter", "autoFilter", "sortState", "conditionalFormatting",
              "dataValidations", "hyperlinks", "legacyDrawing", "extLst",
            ].contains(node.name)
          ) {
          return "Worksheet content requires reference-aware renaming"
        }
      }
      for node in tree.document.nodes() {
        if controls is Some(extension) &&
          node.start >= extension.start &&
          node.end <= extension.end {
          continue
        }
        if sparkline is Some(extension) &&
          node.start >= extension.start &&
          node.end <= extension.end {
          continue
        }
        // Known filter labels and visibility provenance contain no sheet references.
        if filter is Some(filter) &&
          node.start >= filter.start &&
          node.end <= filter.end {
          continue
        }
        if node.uri != spreadsheet_uri ||
          (
            node.name == "extLst" &&
            !tree.children.get(node.id).unwrap_or([]).is_empty()
          ) {
          return "Worksheet extensions require reference-aware renaming"
        }
        if node.name == "f" &&
          !["normal", "shared"].contains(
            node.attribute("t").unwrap_or("normal"),
          ) {
          return "Formula groups require renaming support"
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn sheet_reference_changes(
  document : @xml.Document,
  old : String,
  name : String?,
  deleted_scope~ : Int? = None,
  sparklines~ : Bool = false,
  charts~ : Bool = false,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let mut payload = 0L
  for node in document.nodes() {
    let sparkline = sparklines &&
      node.uri == sparkline_formula_uri &&
      node.name == "f"
    let chart = charts && node.uri == chart_uri && node.name == "f"
    if node.uri != spreadsheet_uri && !sparkline && !chart {
      continue
    }
    if (
        [
          "f", "formula", "formula1", "formula2", "definedName", "calculatedColumnFormula",
          "totalsRowFormula",
        ].contains(node.name) ||
        sparkline ||
        chart
      ) &&
      !node.text.is_empty() {
      if node.name == "definedName" &&
        node
        .attribute("localSheetId")
        .map(scope => Some(natural(scope, 255)) == deleted_scope)
        .unwrap_or(false) {
        continue
      }
      let text = sheet_reference_formula(node.text, old, name)
      if text != node.text {
        if chart {
          let source = document.source()[node.opening_end:node.closing_start]
          guard !source.contains("<!--") && !source.contains("<?") else {
            @failure.reject(
              "protected-content", "Chart formula annotations require source-preserving renaming",
            )
          }
        }
        let xml = @xml.escape_text(text)
        let length = node.closing_start - node.opening_end
        payload += (length.to_int64() + xml.length().to_int64()) * 2
        changes.push({
          node: node.id,
          offset: node.opening_end - node.start,
          length,
          xml,
        })
      }
    }
    if node.name == "hyperlink" &&
      node.attribute(
        "id",
        uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
      )
      is None &&
      node.attribute("location") is Some(location) {
      let text = sheet_reference_formula(location, old, name)
      let updates = if name is None && text != location {
        [sheet_node_removal(Tree::new(document), node)]
      } else {
        metadata_changes(node, [("location", text)])
      }
      for change in updates {
        payload += (change.length.to_int64() + change.xml.length().to_int64()) *
          2
      }
      changes.append(updates)
    }
    guard payload <= 4194304 else {
      @failure.reject(
        "limit-exceeded", "Renaming exceeds history payload budget",
      )
    }
  }
  changes
}

///|
fn validate_sheet_name(name : String) -> Unit raise @failure.Failure {
  guard !name.is_empty() &&
    name.length() <= 31 &&
    @xml.valid_text(name) &&
    !name.has_prefix("'") &&
    !name.has_suffix("'") &&
    name
    .iter()
    .all(character => {
      character.to_int() >= 32 &&
      !"[]:*?/\\".contains(String::from_array([character]))
    }) else {
    @failure.reject("invalid-sheet", "Invalid worksheet name")
  }
}

///|
fn Session::rename_sheet(
  self : Session,
  index : Int,
  name : String,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason(
    tables=true,
    sparklines=true,
    pictures=true,
    charts=true,
    analysis=true,
    threads=true,
  )
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let tables = self.sheet_tables()
  validate_sheet_name(name)
  guard !self.sheets.any(sheet => {
    sheet.id != self.sheets[index].id &&
    sheet.name.to_lower() == name.to_lower()
  }) else {
    @failure.reject("invalid-sheet", "Worksheet name already exists")
  }
  let old = self.sheets[index].name
  if name == old {
    return self.query()
  }
  let tree = Tree::new(self.workbook)
  let parent = tree.one(tree.root("workbook").id, "sheets").unwrap()
  let changes = metadata_changes(tree.all(parent.id, "sheet")[index], [
    ("name", name),
  ])
  changes.append(sheet_reference_changes(self.workbook, old, Some(name)))
  let mut payload = changes
    .iter()
    .fold(init=0L, (sum, change) => {
      sum + (change.length.to_int64() + change.xml.length().to_int64()) * 2
    })
  let plans : Array[(Int, Array[@xml.SourceChange])] = []
  for index, sheet in self.sheets {
    let edits = sheet_reference_changes(
      sheet.document,
      old,
      Some(name),
      sparklines=true,
    )
    payload += edits
      .iter()
      .fold(init=0L, (sum, change) => {
        sum + (change.length.to_int64() + change.xml.length().to_int64()) * 2
      })
    guard payload <= 4194304 else {
      @failure.reject(
        "limit-exceeded", "Renaming exceeds history payload budget",
      )
    }
    if !edits.is_empty() {
      plans.push((index, edits))
    }
  }
  let (workbook, edit) = self.workbook.edit_source(changes)
  let edits : Array[(String, @xml.Edit)] = [(self.main, edit)]
  let sheets = self.sheets.copy()
  for (index, changes) in plans {
    let sheet = sheets[index]
    let (document, edit) = sheet.document.edit_source(changes)
    sheets[index] = Sheet::read(
      sheet.id,
      sheet.name,
      sheet.state,
      document,
      self.strings,
      self.styles.length(),
    )
    edits.push((sheet.id, edit))
  }
  let parts = self.parts.copy()
  self.sheet_table_references(tables, old, Some(name), parts, edits)
  self.sheet_chart_references(old, Some(name), parts, edits)
  self.rename_analysis_sources(old, name, parts, edits)
  let sheets = self.ordered_sheets(workbook, sheets, parts)
  ignore({ ..self, workbook, sheets, parts, }.analysis_parts())
  let calculation = self.calculate(sheets, None, [], workbook, parts~)
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    self.selection,
    parts~,
    table_edits=tables.map(table => table.part),
    drawing_selection=self.drawing_selection,
  )
  self.query()
}
