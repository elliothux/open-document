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
/// Links a variant to its predecessor or gives it an independent XML part.
pub fn Session::set_running_link(
  self : Session,
  revision : Int,
  sectionIndex : Int,
  kind : String,
  variant : String,
  linked : Bool,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let (section, reference, existing) = self.running_target(
    tree, sectionIndex, kind, variant,
  )
  if linked {
    guard sectionIndex > 0 else {
      @failure.reject(
        "invalid-operation", "The first section has no preceding running story",
      )
    }
    guard reference is Some(id) else { return self.edit_state() }
    let node = tree.nodes[id]
    let markup = tree.source[node.start:node.end]
    guard !markup.contains("<!--") && !markup.contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated running reference is protected",
      )
    }
    let owner = section.unwrap()
    let (candidate, edit) = document.edit_source([
      {
        node: owner,
        offset: node.start - tree.nodes[owner].start,
        length: node.end - node.start,
        xml: "",
      },
    ])
    return self.commit_running(
      candidate,
      [edit],
      self.parts.copy(),
      Map([]),
      Map([]),
      probe~,
      profile~,
      images~,
    )
  }
  if (sectionIndex == 0 || reference is Some(_)) &&
    !self.running_shared(tree, existing) {
    return self.edit_state()
  }
  let source = existing.map(part => self.part_xml(part))
  guard source
    .map(xml => xml.source().length() <= history_byte_limit / 2)
    .unwrap_or(true) else {
    @failure.reject(
      "limit-exceeded", "Running area copy exceeds history budget",
    )
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = self.new_word_part(kind, parts, edits, created)
  let copy = @xml.Document::parse(
    source
    .map(xml => xml.bytes())
    .unwrap_or_else(() => {
      @utf8.encode(
        "<w:\{if kind == "header" { "hdr" } else { "ftr" }} xmlns:w='\{word_uri}'><w:p/></w:\{if kind == "header" { "hdr" } else { "ftr" }}>",
      )
    }),
    part,
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  parts[part] = copy
  created[part] = copy
  if existing is Some(existing) {
    let old_rels = running_rels_path(existing)
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
          .find_first(r => r.owner == existing && r.id == id)
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
  let (initial, xml_edits, section) = page_section(document, tree, section)
  let tree = WordTree::new(initial)
  let change = if reference is Some(id) {
    let node = tree.nodes[id]
    let attribute = node.attributes
      .iter()
      .find_first(a => a.uri == running_rel_uri && a.name == "id")
      .unwrap()
    @xml.SourceChange::{
      node: id,
      offset: attribute.start - node.start,
      length: attribute.end - attribute.start,
      xml: property_attribute(relation.id),
    }
  } else {
    tree.running_reference_change(section, kind, variant, relation.id)
  }
  let (candidate, edit) = initial.edit_source([change])
  xml_edits.push(edit)
  self.commit_running(
    candidate,
    xml_edits,
    parts,
    edits,
    created,
    probe~,
    profile~,
    images~,
  )
}
