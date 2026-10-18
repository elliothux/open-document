///|
fn Session::hyperlink_relation(
  self : Session,
  sheet : Sheet,
  target : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  created : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  let candidate = { ..self, parts, }
  let links = candidate.hyperlink_relations(sheet.id)
  if links
    .values()
    .find_first(r => {
      r.external &&
      r.kind == relationship_uri + "hyperlink" &&
      r.target == target
    })
    is Some(link) {
    return link.id
  }
  let id = for i in 1..<=16384 {
    let id = "odLink\{i}"
    if !links.contains(id) {
      break id
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Hyperlink identities exhausted")
  }
  let path = workbook_relations(sheet.id)
  let path = self.opc.names.get(path.to_lower()).unwrap_or(path)
  let markup = "<od:Relationship xmlns:od=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{id}\" Type=\"\{relationship_uri}hyperlink\" Target=\"\{escaped_attribute(target)}\" TargetMode=\"External\"/>"
  if self.opc.names.contains(path.to_lower()) || parts.contains(path) {
    let document = candidate.part_xml(path)
    let (candidate, edit) = document.edit_source([
      insertion(document.nodes()[0], markup),
    ])
    parts[path] = candidate
    edits.push((path, edit))
  } else {
    let document = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{markup}</Relationships>",
      ),
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    parts[path] = document
    created[path] = document
  }
  id
}

///|
fn hyperlink_fragment(
  tree : Tree,
  node : @xml.Node,
  range : Range,
  target : String?,
  relation : String?,
) -> String raise @failure.Failure {
  let source = tree.document.source()
  let replacements : Array[(Int, Int, String)] = []
  for a in node.attributes {
    if a.uri.is_empty() && a.name == "ref" {
      replacements.push((a.start, a.end, escaped_attribute(range.name())))
    }
    if target is Some(_) &&
      (
        (a.uri.is_empty() && a.name == "location") ||
        (
          a.uri == relationship_uri[:relationship_uri.length() - 1].to_owned() &&
          a.name == "id"
        )
      ) {
      let mut end = a.start - 1
      while source[end] != 61 {
        end -= 1
      }
      while [9, 10, 13, 32].contains(source[end - 1].to_int()) {
        end -= 1
      }
      let mut start = end
      while ![9, 10, 13, 32].contains(source[start - 1].to_int()) {
        start -= 1
      }
      replacements.push((start, a.end + 1, ""))
    }
  }
  let extra = if target is Some(text) {
    if text.has_prefix("#") {
      " location=\"\{escaped_attribute(text[1:].to_owned())}\""
    } else {
      let bindings : Map[String, Bool] = Map([])
      for id = node.id; id >= 0; id = tree.nodes[id].parent {
        for (prefix, _) in tree.nodes[id].namespaces {
          bindings[prefix] = true
        }
      }
      let prefix = for i in 1..<=16384 {
        let prefix = "odLink\{i}"
        if !bindings.contains(prefix) {
          break prefix
        }
      } nobreak {
        @failure.reject(
          "limit-exceeded", "Hyperlink namespace identities exhausted",
        )
      }
      " xmlns:\{prefix}=\"\{relationship_uri[:relationship_uri.length() - 1]}\" \{prefix}:id=\"\{relation.unwrap()}\""
    }
  } else {
    ""
  }
  if !extra.is_empty() {
    let at = node.opening_end - (if node.empty { 2 } else { 1 })
    replacements.push((at, at, extra))
  }
  replacements.sort_by((a, b) => a.0.compare(b.0))
  let out = StringBuilder()
  let mut cursor = node.start
  for (start, end, text) in replacements {
    out.write_view(source[cursor:start])
    out.write_string(text)
    cursor = end
  }
  out.write_view(source[cursor:node.end])
  out.to_string()
}

///|
fn Session::set_hyperlink(
  self : Session,
  id : String,
  source : String,
  target : String?,
) -> Json raise @failure.Failure {
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let range = sheet.merge_target(Range::parse(source))
  let reason = self.hyperlink_reason(sheet, range)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if target is Some(text) {
    check_hyperlink_target(text)
    if text.has_prefix("#") {
      ignore(
        self.hyperlink_destination(
          index,
          { row: range.top, column: range.left, },
          text,
        ),
      )
    }
  }
  let (current, mixed) = self.hyperlink_at(sheet, range)
  if !mixed && current == target {
    return self.query()
  }
  let tree = Tree::new(sheet.document)
  let nodes = hyperlink_nodes(tree)
  let links = self.hyperlink_relations(id)
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let created : Map[String, @xml.Document] = Map([])
  let relation = target
    .filter(t => !t.has_prefix("#"))
    .map(text => self.hyperlink_relation(sheet, text, parts, edits, created))
  let changes : Array[@xml.SourceChange] = []
  let mut remaining = [range]
  let mut count = nodes.length()
  let mut units = 0
  for node in nodes {
    let old = Range::parse(node.attribute("ref").unwrap_or(""))
    if !old.intersects(range) {
      continue
    }
    ignore(hyperlink_target(tree, node, links))
    let output = StringBuilder()
    for piece in old.without(range) {
      output.write_string(hyperlink_fragment(tree, node, piece, None, None))
      count += 1
    }
    if target is Some(_) {
      let overlap : Range = {
        top: old.top.max(range.top),
        bottom: old.bottom.min(range.bottom),
        left: old.left.max(range.left),
        right: old.right.min(range.right),
      }
      output.write_string(
        hyperlink_fragment(tree, node, overlap, target, relation),
      )
      count += 1
    }
    count -= 1
    let markup = output.to_string()
    units += markup.length()
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: markup,
    })
    let next : Array[Range] = []
    for piece in remaining {
      next.append(piece.without(old))
    }
    remaining = next
    guard count <= 4096 && remaining.length() <= 4096 && units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Hyperlink fragments exceed source budget",
      )
    }
  }
  if target is Some(text) {
    let destination = if text.has_prefix("#") {
      "location=\"\{escaped_attribute(text[1:].to_owned())}\""
    } else {
      "xmlns:odRel=\"\{relationship_uri[:relationship_uri.length() - 1]}\" odRel:id=\"\{relation.unwrap()}\""
    }
    let additions = remaining
      .map(piece => {
        "<od:hyperlink xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{piece.name()}\" \{destination}/>"
      })
      .join("")
    count += remaining.length()
    units += additions.length()
    guard count <= 4096 && units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Hyperlink fragments exceed source budget",
      )
    }
    if !additions.is_empty() {
      changes.push(hyperlink_insertion(tree, additions))
    }
  }
  if changes.is_empty() {
    return self.query()
  }
  // Retain container comments even after its final hyperlink is removed.
  let (document, edit) = sheet.document.edit_source(join_insertions(changes))
  edits.push((id, edit))
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    id,
    sheet.name,
    sheet.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}

///|
fn Session::open_hyperlink(
  self : Session,
  id : String,
  source : String,
  source_revision : Int,
) -> Json raise @failure.Failure {
  guard source_revision == self.revision && id == self.selection.0 else {
    @failure.reject(
      "stale-search", "Hyperlink selection changed; query it again",
    )
  }
  let sheet = self.sheets[self.sheet_index(id)]
  let range = sheet.merge_target(self.selection.1)
  guard sheet.merge_target(Range::parse(source)) == range else {
    @failure.reject(
      "stale-search", "Hyperlink selection changed; query it again",
    )
  }
  let (target, mixed) = self.hyperlink_at(sheet, range)
  guard !mixed && target is Some(target) else {
    @failure.reject("invalid-operation", "Select one common hyperlink target")
  }
  let (destination, range) = self.hyperlink_destination(
    self.sheet_index(id),
    { row: range.top, column: range.left, },
    target,
  )
  self.select(self.revision, destination, range.name())
}
