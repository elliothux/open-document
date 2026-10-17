///|
fn Session::running_shared(
  self : Session,
  tree : WordTree,
  part : String?,
) -> Bool raise @failure.Failure {
  guard part is Some(part) else { return false }
  let mut count = 0
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri == word_uri &&
      ["headerReference", "footerReference"].contains(node.name) {
      let kind = if node.name == "headerReference" {
        "header"
      } else {
        "footer"
      }
      if self.running_part(tree, id, kind) == part {
        count += 1
      }
    }
  }
  count > 1
}

///|
fn running_rels_path(part : String) -> String {
  let segments = part.split("/").map(s => s.to_owned()).to_array()
  let leaf = segments.pop().unwrap()
  segments.push("_rels")
  segments.push(leaf + ".rels")
  segments.join("/")
}

///|
/// Gives one explicitly referenced running variant an independent XML part.
pub fn Session::unlink_running_area(
  self : Session,
  revision : Int,
  kind : String,
  variant : String,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let (_, reference, existing) = self.running_target(tree, kind, variant)
  if !self.running_shared(tree, existing) {
    return self.edit_state()
  }
  let source = self.part_xml(existing.unwrap())
  guard source.source().length() <= history_byte_limit / 2 else {
    @failure.reject(
      "limit-exceeded", "Running area copy exceeds history budget",
    )
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = self.new_word_part(kind, parts, edits, created)
  let copy = @xml.Document::parse(
    source.bytes(),
    part,
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  parts[part] = copy
  created[part] = copy
  let old_rels = running_rels_path(existing.unwrap())
  let old_rels = self.opc.names.get(old_rels.to_lower()).unwrap_or(old_rels)
  if self.parts.contains(old_rels) ||
    self.opc.names.contains(old_rels.to_lower()) {
    let relationships = self.relationships()
    let rels = self.part_xml(old_rels)
    let changes : Array[@xml.SourceChange] = []
    for node in rels.nodes() {
      if node.parent != 0 {
        continue
      }
      let id = node.attribute("Id").unwrap()
      let relation = relationships
        .iter()
        .find_first(r => r.owner == existing.unwrap() && r.id == id)
        .unwrap()
      if !relation.external {
        let target = node.attributes
          .iter()
          .find_first(a => a.uri.is_empty() && a.name == "Target")
          .unwrap()
        changes.push({
          node: node.id,
          offset: target.start - node.start,
          length: target.end - target.start,
          xml: property_attribute("/" + relation.target),
        })
      }
    }
    let (rebased, _) = rels.edit_source(changes)
    let path = running_rels_path(part)
    let copy = @xml.Document::parse(
      rebased.bytes(),
      path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[path] = copy
    created[path] = copy
    let types = self.opc.names["[content_types].xml"]
    let (updated, edit) = append_part_xml(
      parts[types],
      "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{property_attribute(path)}\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
    )
    parts[types] = updated
    edits[types].push(edit)
  }
  let view = { ..self, parts, }
  let relation = view
    .relationships()
    .iter()
    .find_first(r => {
      r.owner == self.main &&
      r.target == part &&
      r.kind == running_rel_uri + "/" + kind
    })
    .unwrap()
  let id = reference.unwrap()
  let node = tree.nodes[id]
  let attribute = node.attributes
    .iter()
    .find_first(a => a.uri == running_rel_uri && a.name == "id")
    .unwrap()
  let (candidate, edit) = document.edit_source([
    {
      node: id,
      offset: attribute.start - node.start,
      length: attribute.end - attribute.start,
      xml: property_attribute(relation.id),
    },
  ])
  self.commit_running(
    candidate,
    [edit],
    parts,
    edits,
    created,
    probe~,
    profile~,
    images~,
  )
}
