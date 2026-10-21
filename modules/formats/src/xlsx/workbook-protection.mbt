///|
fn Session::workbook_protection_reason(self : Session) -> String {
  if !self.read_only.is_empty() {
    return self.read_only
  }
  try {
    let tree = Tree::new(self.workbook)
    let root = tree.root("workbook")
    if tree.one(root.id, "workbookProtection") is Some(node) {
      conditional_node(
        tree,
        node,
        [
          "lockStructure", "lockWindows", "lockRevision", "workbookPassword", "workbookAlgorithmName",
          "workbookHashValue", "workbookSaltValue", "workbookSpinCount",
        ],
        [],
      )
      let source = tree.document.source()[node.start:node.end]
      guard node.text.trim().is_empty() &&
        !source.contains("<!--") &&
        !source.contains("<?") else {
        return "Workbook protection text or annotations require editing support"
      }
      ignore(flag(node, "lockStructure"))
      guard !flag(node, "lockWindows") && !flag(node, "lockRevision") else {
        return "Workbook window or revision protection requires editing support"
      }
      ignore(protection_credentials(node, workbook=true))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::workbook_protection_query(
  self : Session,
) -> Json raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  let nodes = tree.all(tree.root("workbook").id, "workbookProtection")
  let locked = nodes.any(node => flag(node, "lockStructure") catch { _ => true })
  {
    "protected": locked,
    "passwordRequired": locked &&
    nodes.any(node => {
      [
        "workbookPassword", "workbookAlgorithmName", "workbookHashValue", "workbookSaltValue",
        "workbookSpinCount",
      ].any(key => node.attribute(key) is Some(_))
    }),
    "reason": self.workbook_protection_reason(),
  }
}

///|
fn Session::set_workbook_protection(
  self : Session,
  enabled : Bool,
  password : String,
  salt : Bytes,
) -> Json raise @failure.Failure {
  @protection.password(password)
  guard salt.length() == (if enabled && !password.is_empty() { 16 } else { 0 }) else {
    @failure.reject(
      "invalid-operation", "Workbook protection requires a 16-byte random salt for a new password",
    )
  }
  let reason = self.workbook_protection_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let tree = Tree::new(self.workbook)
  let root = tree.root("workbook")
  let node = tree.one(root.id, "workbookProtection")
  let locked = node.map(n => flag(n, "lockStructure")).unwrap_or(false)
  if enabled && locked {
    @failure.reject(
      "invalid-operation", "Unprotect the workbook before changing its password",
    )
  }
  if !enabled && !locked {
    return self.query()
  }
  let markup = if enabled {
    let attributes = if password.is_empty() {
      ""
    } else {
      " workbookAlgorithmName=\"SHA-512\" workbookHashValue=\"\{@base64.encode(@protection.hash(password,salt,100000)[:])}\" workbookSaltValue=\"\{@base64.encode(salt[:])}\" workbookSpinCount=\"100000\""
    }
    "<od:workbookProtection xmlns:od=\"\{spreadsheet_uri}\" lockStructure=\"1\"\{attributes}/>"
  } else {
    check_protection_password(node.unwrap(), password, workbook=true)
    ""
  }
  let change : @xml.SourceChange = if node is Some(node) {
    {
      node: root.id,
      offset: node.start - root.start,
      length: node.end - node.start,
      xml: markup,
    }
  } else {
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(n => {
        !["fileVersion", "fileSharing", "workbookPr"].contains(n.name)
      })
    if next is Some(node) {
      {
        node: root.id,
        offset: node.start - root.start,
        length: 0,
        xml: markup,
      }
    } else {
      insertion(root, markup)
    }
  }
  let (workbook, edit) = self.workbook.edit_source([change])
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    self.sheets.copy(),
    workbook,
    self.calculation.unwrap(),
    [(self.main, edit)],
    self.selection,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
