///|
fn Session::delete_layout(
  self : Session,
  part : String,
) -> Json raise @failure.Failure {
  let choice = self.layout_choice(part)
  let (node, id) = self.layout_deletion(choice)
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  let removed : Map[String, @xml.Document] = Map([])
  for name in [part, relationship_part(part)] {
    removed[name] = self.part_document(name)
    parts.remove(name)
  }
  let master = choice.master
  let (document, edit) = master.document.edit_source([
    remove_slide_node(master, node),
  ])
  parts[master.part] = document
  edits.push((master.part, edit))
  for path in [relationship_part(master.part), "[Content_Types].xml"] {
    let original = self.part_document(path)
    let tree = Tree::new(path, original)
    let changes = original
      .nodes()
      .filter(node => {
        if path == "[Content_Types].xml" {
          node.name == "Override" &&
          node
          .attribute("PartName")
          .map(value => {
            value.has_prefix("/") &&
            removed
            .keys()
            .any(name => name.to_lower() == value[1:].to_owned().to_lower())
          })
          .unwrap_or(false)
        } else {
          node.name == "Relationship" && node.attribute("Id") == Some(id)
        }
      })
      .map(node => remove_slide_node(tree, node))
    let (document, edit) = original.edit_source(changes.iter().collect())
    parts[path] = document
    edits.push((path, edit))
  }
  let after = if self.selection.slide == part {
    {
      slide: master.part,
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    }
  } else {
    self.selection
  }
  let removed_parts = [
    ..self.removed,
    ..removed
    .keys()
    .filter(name => self.opc.names.contains(name.to_lower()))
    .to_array(),
  ]
  self.validate_source_target(after.slide, parts, removed=removed_parts)
  self.commit_slides(self.main, self.slides, edits, after, parts~, removed~)
  self.query()
}
