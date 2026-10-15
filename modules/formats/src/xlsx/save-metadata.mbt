///|
fn metadata_changes(
  node : @xml.Node,
  values : Array[(String, String)],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  let additions = StringBuilder()
  for (name, value) in values {
    if node.attribute(name) == Some(value) {
      continue
    }
    if node.attributes
      .iter()
      .find_first(attribute => {
        attribute.name == name && attribute.uri.is_empty()
      })
      is Some(attribute) {
      changes.push({
        node: node.id,
        offset: attribute.start - node.start,
        length: attribute.end - attribute.start,
        xml: escaped_attribute(value),
      })
    } else {
      additions <+ " \{name}=\"\{escaped_attribute(value)}\""
    }
  }
  if !additions.to_string().is_empty() {
    changes.push({
      node: node.id,
      offset: node.opening_end - node.start - (if node.empty { 2 } else { 1 }),
      length: 0,
      xml: additions.to_string(),
    })
  }
  changes
}

///|
fn metadata_attributes(
  document : @xml.Document,
  node : @xml.Node,
  values : Array[(String, String)],
) -> @xml.Document raise @failure.Failure {
  let changes = metadata_changes(node, values)
  if changes.is_empty() {
    document
  } else {
    document.edit_source(changes).0
  }
}

///|
fn Session::save_metadata(
  self : Session,
  replacements : Map[String, Bytes],
) -> Array[String] raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  let root = tree.root("workbook")
  let workbook = if tree.one(root.id, "calcPr") is Some(node) {
    metadata_attributes(self.workbook, node, [
      ("fullCalcOnLoad", "1"),
      ("forceFullCalc", "1"),
      ("calcMode", "auto"),
    ])
  } else {
    let prefix = root.qualified[:root.qualified.length() - 8].to_owned()
    let content = "<\{prefix}calcPr fullCalcOnLoad=\"1\" forceFullCalc=\"1\" calcMode=\"auto\"/>"
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(node => {
        node.uri == spreadsheet_uri &&
        [
          "oleSize", "customWorkbookViews", "pivotCaches", "smartTagPr", "smartTagTypes",
          "webPublishing", "fileRecoveryPr", "webPublishObjects", "extLst",
        ].contains(node.name)
      })
    let change : @xml.SourceChange = if next is Some(next) {
      {
        node: root.id,
        offset: next.start - root.start,
        length: 0,
        xml: content,
      }
    } else {
      insertion(root, content)
    }
    self.workbook.edit_source([change]).0
  }
  replacements[self.main] = workbook.bytes()
  let removed : Array[String] = []
  for rel in self.opc.relationships() {
    if rel.owner != self.main || rel.kind != relationship_uri + "calcChain" {
      continue
    }
    guard !rel.external else {
      @failure.reject(
        "malformed-xlsx", "External calculation chain relationship",
      )
    }
    removed.push(rel.target)
    let chain_segments = rel.target
      .split("/")
      .map(segment => segment.to_owned())
      .collect()
    let chain_leaf = chain_segments.pop().unwrap()
    chain_segments.push("_rels")
    chain_segments.push(chain_leaf + ".rels")
    let chain_relations = chain_segments.join("/")
    if self.opc.content_type(chain_relations) is Some(_) {
      removed.push(chain_relations)
    }
    let segments = self.main
      .split("/")
      .map(segment => segment.to_owned())
      .collect()
    let leaf = segments.pop().unwrap()
    segments.push("_rels")
    segments.push(leaf + ".rels")
    let part = segments.join("/")
    let original = self.opc.xml(part)
    let document = if replacements.get(part) is Some(bytes) {
      @xml.Document::parse(
        bytes,
        part,
        self.budget.xml_depth,
        self.budget.entry_bytes,
      )
    } else {
      original
    }
    let root = document.nodes()[0]
    let changes : Array[@xml.SourceChange] = document
      .nodes()
      .iter()
      .filter(node => {
        node.parent == root.id && node.attribute("Id") == Some(rel.id)
      })
      .map(node => {
        let change : @xml.SourceChange = {
          node: root.id,
          offset: node.start - root.start,
          length: node.end - node.start,
          xml: "",
        }
        change
      })
      .collect()
    replacements[part] = document.edit_source(changes).0.bytes()
  }
  if !removed.is_empty() {
    let part = "[Content_Types].xml"
    let document = self.opc.xml(part)
    let root = document.nodes()[0]
    let changes : Array[@xml.SourceChange] = document
      .nodes()
      .iter()
      .filter(node => {
        node.parent == root.id &&
        node
        .attribute("PartName")
        .map(name => removed.contains(name[1:].to_owned()))
        .unwrap_or(false)
      })
      .map(node => {
        let change : @xml.SourceChange = {
          node: root.id,
          offset: node.start - root.start,
          length: node.end - node.start,
          xml: "",
        }
        change
      })
      .collect()
    if !changes.is_empty() {
      replacements[part] = document.edit_source(changes).0.bytes()
    }
  }
  removed
}
