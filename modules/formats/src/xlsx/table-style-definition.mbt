///|
fn validate_table_style_name(name : String) -> Unit raise @failure.Failure {
  guard !name.is_empty() &&
    name.length() <= 255 &&
    name.trim() == name &&
    @xml.valid_text(name) &&
    name.iter().all(c => c >= ' ' && c != '\u007f') else {
    @failure.reject("invalid-operation", "Invalid custom table style name")
  }
}

///|
fn table_style_elements(
  elements : Array[TableStyleElement],
) -> Array[TableStyleElement] raise @failure.Failure {
  guard elements.length() <= 13 else {
    @failure.reject(
      "limit-exceeded", "Custom table styles support at most 13 regions",
    )
  }
  let entries : Map[String, TableStyleElement] = Map([])
  for element in elements {
    guard table_element_order().contains(element.kind) &&
      !entries.contains(element.kind) &&
      element.size >= 1 &&
      element.size <= 1048576 else {
      @failure.reject(
        "invalid-operation", "Invalid or repeated custom table style region",
      )
    }
    element.format.validate()
    CellFormat::new(left=element.vertical, right=element.horizontal).validate()
    entries[element.kind] = {
      ..element,
      size: if element.kind.has_suffix("Stripe") {
        element.size
      } else {
        1
      },
    }
  }
  table_element_order().iter().filter_map(kind => entries.get(kind)).to_array()
}

///|
fn Session::edit_table_style_definition(
  self : Session,
  sheet : String,
  original : String?,
  name : String,
  elements : Array[TableStyleElement]?,
) -> Json raise @failure.Failure {
  let reason = self.sheet_rename_reason(structure=false, tables=true)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let current = self.sheets[self.sheet_index(sheet)]
  guard !current.locked && current.state == "visible" else {
    @failure.reject("protected-content", "Worksheet is protected")
  }
  let deleting = elements is None
  if !deleting || !name.is_empty() {
    validate_table_style_name(name)
  }
  let catalog = self.custom_table_styles(self.parts)
  let before = original.map(old => {
    validate_table_style_name(old)
    let style = catalog
      .get(old.to_upper())
      .unwrap_or_error(
        @failure.Failure(
          code="invalid-operation",
          part=sheet,
          offset=-1,
          message="Custom table style no longer exists",
        ),
      )
    guard style.reason.is_empty() else {
      @failure.reject("protected-content", style.reason)
    }
    style
  })
  guard !deleting || before is Some(_) else {
    @failure.reject(
      "invalid-operation", "Deleting requires a custom table style",
    )
  }
  if !deleting {
    let reserved = ["Light", "Medium", "Dark"].any(family => {
      let count = match family {
        "Light" => 21
        "Medium" => 28
        _ => 11
      }
      Array::makei(count, index => "TableStyle\{family}\{index+1}").any(stock => {
        stock.to_upper() == name.to_upper()
      })
    })
    guard before
      .map(style => style.name.to_upper() == name.to_upper())
      .unwrap_or(false) ||
      (catalog.get(name.to_upper()) is None && !reserved) else {
      @failure.reject("invalid-operation", "Table style name is already in use")
    }
    guard before is Some(_) || catalog.length() < 256 else {
      @failure.reject("limit-exceeded", "Custom table styles exceed 256")
    }
  } else if !name.is_empty() {
    guard before
      .map(style => style.name.to_upper() != name.to_upper())
      .unwrap_or(false) else {
      @failure.reject(
        "invalid-operation", "Deleted style cannot replace itself",
      )
    }
    if catalog.get(name.to_upper()) is Some(style) {
      guard style.reason.is_empty() else {
        @failure.reject("protected-content", style.reason)
      }
    } else {
      guard table_style_index(Some(name)) is Some(_) else {
        @failure.reject(
          "invalid-operation", "Replacement table style is unknown",
        )
      }
    }
  }
  let name = if deleting {
    catalog.get(name.to_upper()).map(style => style.name).unwrap_or(name)
  } else {
    name
  }
  let elements = elements.map(table_style_elements).unwrap_or([])
  if !deleting &&
    before is Some(style) &&
    style.name == name &&
    style.elements.length() == elements.length() &&
    elements.all(element => {
      style.elements
      .get(element.kind)
      .map(old => old.json() == element.json())
      .unwrap_or(false)
    }) {
    return self.query()
  }
  let affected = self
    .table_definitions(self.sheets, self.workbook, self.parts)
    .filter(table => {
      table.style
      .map(style => {
        before
        .map(old => old.name.to_upper() == style.to_upper())
        .unwrap_or(false)
      })
      .unwrap_or(false)
    })
  for table in affected {
    ignore(self.table_for_edit(table.sheet, table.id))
  }
  let reused : Map[String, Int?] = Map([])
  let changed : Array[TableStyleElement] = []
  if before is Some(style) {
    let path = self.styles_part(self.parts).unwrap()
    let tree = Tree::new(self.part_xml(path))
    let parent = tree.one(tree.root("styleSheet").id, "tableStyles").unwrap()
    let node = tree
      .all(parent.id, "tableStyle")
      .iter()
      .find_first(node => node.attribute("name") == Some(style.name))
      .unwrap()
    let source = tree.document.source()[node.start:node.end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      @failure.reject(
        "protected-content", "Custom table style source annotations are protected",
      )
    }
    if deleting &&
      parent
      .attribute("defaultPivotStyle")
      .map(value => value.to_upper() == style.name.to_upper())
      .unwrap_or(false) {
      @failure.reject(
        "protected-content", "Default pivot style requires pivot style editing",
      )
    }
    for element in elements {
      if style.elements
        .get(element.kind)
        .map(old => old.json() == element.json())
        .unwrap_or(false) {
        reused[element.kind] = tree
          .all(node.id, "tableStyleElement")
          .iter()
          .find_first(node => node.attribute("type") == Some(element.kind))
          .unwrap()
          .attribute("dxfId")
          .map(value => natural(value, 4095))
      }
    }
  }
  for element in elements {
    if !reused.contains(element.kind) {
      changed.push(element)
    }
  }
  let plan = self.derive_conditional_styles(
    changed.map(element => element.format),
    inner=changed.map(element => [element.vertical, element.horizontal]),
  )
  let path = self
    .styles_part(plan.parts)
    .unwrap_or_else(() => {
      let (path, metadata) = self.new_styles_part()
      for (part, document, edit) in metadata {
        plan.parts[part] = document
        plan.edits.push((part, edit))
      }
      let document = @xml.Document::parse(
        empty_cell_styles(),
        path,
        self.budget.xml_depth,
        self.budget.entry_bytes,
      )
      plan.parts[path] = document
      plan.created_parts[path] = document
      path
    })
  let document = plan.parts.get(path).unwrap_or_else(() => self.part_xml(path))
  let tree = Tree::new(document)
  let root = tree.root("styleSheet")
  let parent = tree.one(root.id, "tableStyles")
  if parent is Some(parent) {
    conditional_node(
      tree,
      parent,
      ["count", "defaultTableStyle", "defaultPivotStyle"],
      ["tableStyle"],
    )
  }
  let node = before.bind(style => {
    parent.bind(parent => {
      tree
      .all(parent.id, "tableStyle")
      .iter()
      .find_first(node => node.attribute("name") == Some(style.name))
    })
  })
  let indices : Map[String, Int?] = Map([])
  for index, element in changed {
    indices[element.kind] = plan.indices[index]
  }
  let markup = elements
    .map(element => {
      let index = reused
        .get(element.kind)
        .unwrap_or_else(() => indices[element.kind])
      "<od:tableStyleElement type=\"\{element.kind}\"\{if element.kind.has_suffix("Stripe") { " size=\"" + element.size.to_string() + "\"" } else { "" }}\{index.map(index => " dxfId=\"" + index.to_string() + "\"").unwrap_or("")}/>"
    })
    .join("")
  let pivot = node
    .map(node => flag(node, "pivot", fallback=true))
    .unwrap_or(false)
  let markup = "<od:tableStyle xmlns:od=\"\{spreadsheet_uri}\" name=\"\{escaped_attribute(name)}\" table=\"1\" pivot=\"\{if pivot { 1 } else { 0 }}\" count=\"\{elements.length()}\">\{markup}</od:tableStyle>"
  let changes : Array[@xml.SourceChange] = []
  if parent is Some(parent) {
    if node is Some(node) {
      changes.push({
        node: parent.id,
        offset: node.start - parent.start,
        length: node.end - node.start,
        xml: if deleting {
          ""
        } else {
          markup
        },
      })
    } else {
      changes.push(insertion(parent, markup))
    }
    let count = tree.all(parent.id, "tableStyle").length() +
      (if deleting { -1 } else if node is None { 1 } else { 0 })
    let attributes = [("count", count.to_string())]
    for key in ["defaultTableStyle", "defaultPivotStyle"] {
      if parent
        .attribute(key)
        .map(value => {
          before
          .map(style => style.name.to_upper() == value.to_upper())
          .unwrap_or(false)
        })
        .unwrap_or(false) {
        attributes.push(
          (key, if name.is_empty() { "TableStyleMedium2" } else { name }),
        )
      }
    }
    changes.append(metadata_changes(parent, attributes))
  } else {
    let markup = "<od:tableStyles xmlns:od=\"\{spreadsheet_uri}\" count=\"1\">\{markup}</od:tableStyles>"
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => ["colors", "extLst"].contains(node.name))
    changes.push(
      if next is Some(next) {
        {
          node: root.id,
          offset: next.start - root.start,
          length: 0,
          xml: markup,
        }
      } else {
        insertion(root, markup)
      },
    )
  }
  let (document, edit) = document.edit_source(join_insertions(changes))
  guard document.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Custom table styles exceed history budget",
    )
  }
  plan.parts[path] = document
  if plan.created_parts.contains(path) {
    plan.created_parts[path] = document
  } else {
    plan.edits.push((path, edit))
  }
  for table in affected {
    if table.style == Some(name) {
      continue
    }
    let document = self.part_xml(table.part)
    let tree = table_edit_tree(table, document)
    let node = tree.one(tree.root("table").id, "tableStyleInfo").unwrap()
    let (document, edit) = document.edit_source(
      metadata_changes(node, [("name", name)]),
    )
    plan.parts[table.part] = document
    plan.edits.push((table.part, edit))
  }
  let sheets = self.sheets.copy()
  let calculation = self.calculate(
    sheets,
    self.calculation,
    [],
    self.workbook,
    parts=plan.parts,
  )
  self.commit(
    sheets,
    self.workbook,
    calculation,
    plan.edits,
    self.selection,
    parts=plan.parts,
    created_parts=plan.created_parts,
  )
  self.query()
}
