///|
fn Session::protection_reason(self : Session, sheet : Sheet) -> String {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  try {
    let tree = Tree::new(sheet.document)
    let root = tree.root("worksheet")
    let reason = sheet_protection_reason(tree, root.id, selection=false)
    guard reason.is_empty() else { return reason }
    if tree.one(root.id, "sheetProtection") is Some(node) {
      guard sheet.locked else {
        return "Inactive worksheet protection metadata requires editing support"
      }
      conditional_node(
        tree,
        node,
        [
          "sheet", "objects", "scenarios", "formatCells", "formatColumns", "formatRows",
          "insertColumns", "insertRows", "insertHyperlinks", "deleteColumns", "deleteRows",
          "selectLockedCells", "sort", "autoFilter", "pivotTables", "selectUnlockedCells",
          "password", "algorithmName", "hashValue", "saltValue", "spinCount",
        ],
        [],
      )
      let source = tree.document.source()[node.start:node.end]
      guard !source.contains("<!--") && !source.contains("<?") else {
        return "Worksheet protection annotations require editing support"
      }
      ignore(protection_credentials(node))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::protection_query(
  self : Session,
  sheet : Sheet,
) -> Json raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let node = tree.one(tree.root("worksheet").id, "sheetProtection")
  {
    "protected": sheet.locked,
    "passwordRequired": node
    .map(n => {
      ["password", "hashValue", "algorithmName", "saltValue", "spinCount"].any(key => {
        n.attribute(key) is Some(_)
      })
    })
    .unwrap_or(false),
    "reason": self.protection_reason(sheet),
  }
}

///|
fn Session::set_protection(
  self : Session,
  sheet : String,
  enabled : Bool,
  password : String,
  salt : Bytes,
) -> Json raise @failure.Failure {
  @protection.password(password)
  guard salt.length() == (if enabled && !password.is_empty() { 16 } else { 0 }) else {
    @failure.reject(
      "invalid-operation", "Worksheet protection requires a 16-byte random salt for a new password",
    )
  }
  let index = self.sheet_index(sheet)
  let current = self.sheets[index]
  let reason = self.protection_reason(current)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if enabled && current.locked {
    @failure.reject(
      "invalid-operation", "Unprotect the worksheet before changing its password",
    )
  }
  if !enabled && !current.locked {
    return self.query()
  }
  let tree = Tree::new(current.document)
  let root = tree.root("worksheet")
  let changes : Array[@xml.SourceChange] = if enabled {
    let attributes = if password.is_empty() {
      ""
    } else {
      " algorithmName=\"SHA-512\" hashValue=\"\{@base64.encode(@protection.hash(password,salt,100000)[:])}\" saltValue=\"\{@base64.encode(salt[:])}\" spinCount=\"100000\""
    }
    let markup = "<od:sheetProtection xmlns:od=\"\{spreadsheet_uri}\" sheet=\"1\" objects=\"1\" scenarios=\"1\"\{attributes}/>"
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        [
          "protectedRanges", "scenarios", "autoFilter", "sortState", "dataConsolidate",
          "customSheetViews", "mergeCells", "phoneticPr", "conditionalFormatting",
          "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup",
          "headerFooter", "rowBreaks", "colBreaks", "customProperties", "cellWatches",
          "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF",
          "picture", "oleObjects", "controls", "webPublishItems", "tableParts", "extLst",
        ].contains(node.name)
      })
    [
      if next is Some(node) {
        {
          node: root.id,
          offset: node.start - root.start,
          length: 0,
          xml: markup,
        }
      } else {
        insertion(root, markup)
      },
    ]
  } else {
    let node = tree.one(root.id, "sheetProtection").unwrap()
    check_protection_password(node, password)
    [
      {
        node: root.id,
        offset: node.start - root.start,
        length: node.end - node.start,
        xml: "",
      },
    ]
  }
  if enabled {
    let document = current.document.edit_source(changes).0
    let candidate = Tree::new(document)
    let reason = sheet_protection_reason(
      candidate,
      candidate.root("worksheet").id,
    )
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
  }
  self.commit_view(index, changes)
}
