///|
fn renamed_formula(
  text : String,
  old : String,
  name : String,
) -> String raise @failure.Failure {
  let spans : Array[(Int, Int)] = []
  let tokens = formula_tokens(text, spans~)
  let quoted = "'" + name.replace_all(old="'", new="''") + "'"
  let ranges : Array[(Int, Int)] = []
  let mut units = text.length()
  for index, token in tokens {
    if token is Operator("!") && index > 0 {
      let value = match tokens[index - 1] {
        Word(value) | Quoted(value, true) => value
        _ => continue
      }
      if value.to_lower() == old.to_lower() {
        let range = spans[index - 1]
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
fn Session::sheet_rename_reason(self : Session) -> String {
  try {
    let reason = self.sheet_edit_reason()
    if !reason.is_empty() {
      return reason
    }
    for rel in self.opc.relationships() {
      if rel.owner == self.main &&
        !["worksheet", "styles", "sharedStrings", "theme", "calcChain"].any(kind => {
          rel.kind == relationship_uri + kind
        }) {
        return "Workbook resource references require renaming support"
      }
      if self.sheets.any(sheet => sheet.id == rel.owner) &&
        !["hyperlink", "comments"].any(kind => {
          rel.kind == relationship_uri + kind
        }) {
        return "Worksheet resource references require renaming support"
      }
    }
    for sheet in self.sheets {
      let tree = Tree::new(sheet.document)
      let root = tree.root("worksheet")
      for node in tree.children.get(root.id).unwrap_or([]) {
        if node.uri != spreadsheet_uri ||
          ![
            "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData", "mergeCells",
            "sheetProtection", "pageMargins", "pageSetup", "printOptions", "headerFooter",
            "autoFilter", "conditionalFormatting", "dataValidations", "hyperlinks",
            "extLst",
          ].contains(node.name) {
          return "Worksheet content requires reference-aware renaming"
        }
      }
      for node in tree.document.nodes() {
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
fn rename_reference_changes(
  document : @xml.Document,
  old : String,
  name : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let mut payload = 0L
  for node in document.nodes() {
    if node.uri != spreadsheet_uri {
      continue
    }
    if ["f", "formula", "formula1", "formula2", "definedName"].contains(
        node.name,
      ) &&
      !node.text.is_empty() {
      let text = renamed_formula(node.text, old, name)
      if text != node.text {
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
    if node.name == "hyperlink" && node.attribute("location") is Some(location) {
      let text = renamed_formula(location, old, name)
      let updates = metadata_changes(node, [("location", text)])
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
fn Session::rename_sheet(
  self : Session,
  index : Int,
  name : String,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
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
  changes.append(rename_reference_changes(self.workbook, old, name))
  let mut payload = changes
    .iter()
    .fold(init=0L, (sum, change) => {
      sum + (change.length.to_int64() + change.xml.length().to_int64()) * 2
    })
  let plans : Array[(Int, Array[@xml.SourceChange])] = []
  for index, sheet in self.sheets {
    let edits = rename_reference_changes(sheet.document, old, name)
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
      self.style_count,
    )
    edits.push((sheet.id, edit))
  }
  let sheets = self.ordered_sheets(workbook, sheets)
  let calculation = Calculation::build(sheets, None, [])
  self.commit(sheets, workbook, calculation, edits, self.selection)
  self.query()
}
