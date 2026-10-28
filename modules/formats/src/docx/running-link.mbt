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
  revision : Int32,
  sectionIndex : Int32,
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
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = self.copy_running_part(kind, existing, parts, edits, created)
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
