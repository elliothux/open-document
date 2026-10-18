///|
pub(all) struct NameSettings {
  original : String?
  name : String
  scope : String?
  formula : String
}

///|
fn validate_defined_name(name : String) -> Unit raise @failure.Failure {
  let upper = name.to_upper()
  let address = try Address::parse(name) catch {
    _ => None
  } noraise {
    _ => Some(true)
  }
  let rc = upper.split("C").to_array()
  let r1c1 = rc is [row, column] &&
    row.has_prefix("R") &&
    row[1:].iter().all(c => c >= '0' && c <= '9') &&
    column.iter().all(c => c >= '0' && c <= '9')
  guard name_identifier(name) &&
    @xml.valid_text(name) &&
    !["R", "C", "TRUE", "FALSE"].contains(upper) &&
    !upper.has_prefix("_XLNM.") &&
    address is None &&
    !r1c1 else {
    @failure.reject("invalid-name", "Invalid or reserved defined name")
  }
}

///|
fn name_node_reason(node : @xml.Node, document : @xml.Document) -> String {
  try {
    validate_defined_name(node.attribute("name").unwrap_or(""))
    ignore(flag(node, "hidden"))
    guard !node.empty &&
      node.text.length() <= 8192 &&
      !document.source()[node.opening_end:node.closing_start].contains("<") else {
      return "Defined name source requires editing support"
    }
    ignore(
      parse_formula(
        node.text.strip_prefix("=").unwrap_or(node.text[:]).to_owned(),
      ),
    )
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::name_scope(
  self : Session,
  scope : String?,
) -> Int raise @failure.Failure {
  scope.map(id => self.sheet_index(id)).unwrap_or(-1)
}

///|
fn Session::name_entries(
  self : Session,
  workbook : @xml.Document,
) -> Array[Json] raise @failure.Failure {
  let entries : Array[Json] = []
  let tree = Tree::new(workbook)
  ignore(read_named_definitions(workbook, self.sheets.length()))
  let mut units = 0
  if tree.one(tree.root("workbook").id, "definedNames") is Some(parent) {
    for node in tree.all(parent.id, "definedName") {
      let scope = node
        .attribute("localSheetId")
        .map(value => natural(value, self.sheets.length() - 1))
      units += node.attribute("name").unwrap_or("").length() +
        node.text.length() +
        scope.map(index => self.sheets[index].id.length()).unwrap_or(0)
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Defined name catalog exceeds budget")
      }
      entries.push({
        "name": node.attribute("name").unwrap_or(""),
        "scope": scope
        .map(index => Json(self.sheets[index].id))
        .unwrap_or(Json::null()),
        "formula": node.text,
        "hidden": flag(node, "hidden") catch {
          @failure.Failure(..) => true
        },
        "readOnlyReason": name_node_reason(node, workbook),
      })
    }
  }
  entries
}

///|
fn Session::names_query(self : Session) -> Json {
  {
    "entries": self.name_entries(self.workbook),
    "readOnlyReason": self.sheet_rename_reason(structure=false, tables=true),
  } catch {
    @failure.Failure(message~, ..) =>
      { "entries": [], "readOnlyReason": message }
  }
}

///|
fn Session::select_name(
  self : Session,
  name : String,
  scope : String?,
) -> Json raise @failure.Failure {
  let context = self.name_scope(scope)
  let names = {
    ..read_named_definitions(self.workbook, self.sheets.length()),
    tables: self.table_definitions(self.sheets, self.workbook, self.parts),
  }
  guard names.sources.contains((context, name.to_upper())) else {
    @failure.reject("invalid-name", "Unknown defined name in this scope")
  }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names,
  }
  let target = scope.map(id => self.sheets[self.sheet_index(id)].name)
  let expression = Named(target, name).resolve_names(
    self.sheets,
    context,
    self.focus,
    work,
  )
  guard expression is Reference(sheet, first, last) else {
    @failure.reject(
      "invalid-name", "Defined name does not refer to a rectangle",
    )
  }
  let index = referenced_sheet(self.sheets, context, sheet)
  self.select(
    self.revision,
    self.sheets[index].id,
    first.range(last.unwrap_or(first)).name(),
  )
}

///|
fn name_reference_formula(
  text : String,
  context : Int,
  sheets : Array[Sheet],
  names : NamedDefinitions,
  scope : Int,
  old : String,
  name : String,
  work : FormulaWork,
) -> String raise @failure.Failure {
  work.spend(amount=text.length())
  let spans : Array[(Int, Int)] = []
  let tokens = formula_tokens(text, spans~)
  let out = StringBuilder()
  let mut cursor = 0
  let mut units = text.length()
  for index, token in tokens {
    guard token is Word(word) &&
      word.to_upper() == old.to_upper() &&
      !(tokens.get(index + 1) is Some(Operator("!" | "(") | Brackets(_))) else {
      continue
    }
    let target = if index >= 2 && tokens[index - 1] is Operator("!") {
      match tokens[index - 2] {
        Word(sheet) | Quoted(sheet, true) =>
          referenced_sheet(sheets, context, Some(sheet))
        _ =>
          @failure.reject(
            "protected-content", "Unsupported defined name qualifier",
          )
      }
    } else {
      context
    }
    let bound = if names.sources.contains((target, old.to_upper())) {
      target
    } else {
      -1
    }
    if bound != scope {
      continue
    }
    guard scope != -1 ||
      target == -1 ||
      !names.sources.contains((target, name.to_upper())) else {
      @failure.reject(
        "invalid-name", "Renamed workbook name would be shadowed by a worksheet name",
      )
    }
    let (start, end) = spans[index]
    units += name.length() - (end - start)
    guard units <= 8192 else {
      @failure.reject("limit-exceeded", "Renamed formula exceeds source budget")
    }
    out.write_view(text[cursor:start])
    out.write_string(name)
    cursor = end
  }
  out.write_view(text[cursor:])
  let result = out.to_string()
  work.spend(amount=result.length())
  result
}

///|
fn Session::edit_name(
  self : Session,
  settings : NameSettings,
  delete~ : Bool = false,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason(structure=false, tables=true)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let tables = self.sheet_tables()
  validate_defined_name(settings.name)
  guard !tables.any(table => table.name.to_upper() == settings.name.to_upper()) else {
    @failure.reject(
      "invalid-name", "Defined names cannot use an existing table name",
    )
  }
  let scope = self.name_scope(settings.scope)
  let tree = Tree::new(self.workbook)
  let root = tree.root("workbook")
  let parent = tree.one(root.id, "definedNames")
  let nodes = parent.map(node => tree.all(node.id, "definedName")).unwrap_or([])
  let current = nodes
    .iter()
    .find_first(node => {
      node
      .attribute("name")
      .map(value => {
        Some(value.to_upper()) == settings.original.map(String::to_upper)
      })
      .unwrap_or(false) &&
      node
      .attribute("localSheetId")
      .map(value => natural(value, self.sheets.length() - 1))
      .unwrap_or(-1) ==
      scope
    })
  guard settings.original is None || current is Some(_) else {
    @failure.reject("invalid-name", "Unknown defined name in this scope")
  }
  if current is Some(node) {
    let reason = name_node_reason(node, self.workbook)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
  }
  let names = {
    ..read_named_definitions(self.workbook, self.sheets.length()),
    tables,
  }
  guard !names.sources.contains((scope, settings.name.to_upper())) ||
    settings.original.map(String::to_upper) == Some(settings.name.to_upper()) else {
    @failure.reject("invalid-name", "Defined name already exists in this scope")
  }
  let formula = settings.formula
    .strip_prefix("=")
    .unwrap_or(settings.formula[:])
    .to_owned()
  if !delete {
    guard !formula.is_empty() &&
      formula.length() <= 8192 &&
      @xml.valid_text(formula) else {
      @failure.reject("invalid-name", "Invalid defined name formula")
    }
  }
  if !delete &&
    current is Some(node) &&
    node.attribute("name") == Some(settings.name) &&
    node.text.strip_prefix("=").unwrap_or(node.text[:]) == formula {
    return self.query()
  }
  let changes : Array[@xml.SourceChange] = []
  let rename_work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: self.focus,
    names,
  }
  let rename = settings.original.bind(old => {
    if old != settings.name && !delete {
      Some(old)
    } else {
      None
    }
  })
  for node in nodes {
    if current.map(current => current.id == node.id).unwrap_or(false) {
      if delete {
        changes.push(sheet_node_removal(tree, node))
        continue
      }
      changes.append(metadata_changes(node, [("name", settings.name)]))
    }
    let source = if current
      .map(current => current.id == node.id)
      .unwrap_or(false) {
      if node.text.strip_prefix("=").unwrap_or(node.text[:]) == formula {
        node.text
      } else {
        formula
      }
    } else {
      node.text
    }
    let text = if rename is Some(old) {
      name_reference_formula(
        source,
        -1,
        self.sheets,
        names,
        scope,
        old,
        settings.name,
        rename_work,
      )
    } else {
      source
    }
    changes.append(axis_text_change(tree, node, text))
  }
  if current is None {
    let local_id = if scope >= 0 { " localSheetId=\"\{scope}\"" } else { "" }
    let content = "<od:definedName xmlns:od=\"\{spreadsheet_uri}\" name=\"\{escaped_attribute(settings.name)}\"\{local_id}>\{@xml.escape_text(formula)}</od:definedName>"
    changes.push(
      if parent is Some(parent) {
        insertion(parent, content)
      } else {
        let next = tree.children[root.id]
          .iter()
          .find_first(node => {
            [
              "calcPr", "oleSize", "customWorkbookViews", "pivotCaches", "smartTagPr",
              "smartTagTypes", "webPublishing", "fileRecoveryPr", "webPublishObjects",
              "extLst",
            ].contains(node.name)
          })
        let content = "<od:definedNames xmlns:od=\"\{spreadsheet_uri}\">\{content}</od:definedNames>"
        if next is Some(next) {
          {
            node: root.id,
            offset: next.start - root.start,
            length: 0,
            xml: content,
          }
        } else {
          insertion(root, content)
        }
      },
    )
  }
  let (workbook, edit) = self.workbook.edit_source(changes)
  let candidate_names = {
    ..read_named_definitions(workbook, self.sheets.length()),
    tables,
  }
  ignore(self.name_entries(workbook))
  if !delete {
    let work : FormulaWork = {
      remaining: 1048576,
      date1904: self.date1904,
      origin: { row: 1, column: 1, },
      names: candidate_names,
    }
    let target = settings.scope.map(id => self.sheets[self.sheet_index(id)].name)
    let expression = Named(target, settings.name).resolve_names(
      self.sheets,
      scope,
      work.origin,
      work,
    )
    expression.dependencies(self.sheets, scope.max(0), work, [], 0)
  }
  let sheets = self.sheets.copy()
  let edits : Array[(String, @xml.Edit)] = [(self.main, edit)]
  if delete {
    let after : FormulaWork = {
      remaining: 1048576,
      date1904: self.date1904,
      origin: self.focus,
      names: candidate_names,
    }
    for index, sheet in sheets {
      let changes = deleted_name_hyperlinks(
        Tree::new(sheet.document),
        sheets,
        index,
        rename_work,
        after,
      )
      if !changes.is_empty() {
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
    }
  }
  if rename is Some(old) {
    for index, sheet in sheets {
      let changes : Array[@xml.SourceChange] = []
      let tree = Tree::new(sheet.document)
      for node in sheet.document.nodes() {
        if node.uri != spreadsheet_uri {
          continue
        }
        let value = if ["f", "formula", "formula1", "formula2"].contains(
            node.name,
          ) &&
          !node.text.is_empty() {
          Some(node.text)
        } else if node.name == "hyperlink" &&
          node.attribute(
            "id",
            uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
          )
          is None {
          node.attribute("location")
        } else {
          None
        }
        if value is Some(source) {
          let text = name_reference_formula(
            source,
            index,
            self.sheets,
            names,
            scope,
            old,
            settings.name,
            rename_work,
          )
          if text == source {
            continue
          }
          if node.name == "hyperlink" {
            changes.append(metadata_changes(node, [("location", text)]))
          } else {
            changes.append(axis_text_change(tree, node, text))
          }
        }
      }
      if !changes.is_empty() {
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
    }
  }
  let parts = self.parts.copy()
  if rename is Some(old) {
    for table in tables {
      let source = self.part_xml(table.part)
      let tree = table_edit_tree(table, source)
      let changes : Array[@xml.SourceChange] = []
      for node in source.nodes() {
        if node.uri == spreadsheet_uri &&
          ["calculatedColumnFormula", "totalsRowFormula"].contains(node.name) &&
          !node.text.is_empty() {
          let text = name_reference_formula(
            node.text,
            self.sheet_index(table.sheet),
            self.sheets,
            names,
            scope,
            old,
            settings.name,
            rename_work,
          )
          if text != node.text {
            changes.append(axis_text_change(tree, node, text))
          }
        }
      }
      if !changes.is_empty() {
        let (document, edit) = source.edit_source(changes)
        parts[table.part] = document
        edits.push((table.part, edit))
      }
    }
  }
  let calculation = self.calculate(sheets, None, [], workbook, parts~)
  edits.append(self.cache_edits(sheets, calculation))
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    workbook,
    calculation,
    edits,
    self.selection,
    parts~,
    table_edits=tables.map(table => table.part),
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
