///|
fn Session::copy_running_part(
  self : Session,
  kind : String,
  existing : String?,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> String raise @failure.Failure {
  let source = existing.map(part => self.part_xml(part))
  guard source
    .map(xml => xml.source().length() <= history_byte_limit / 2)
    .unwrap_or(true) else {
    @failure.reject(
      "limit-exceeded", "Running area copy exceeds history budget",
    )
  }
  let view = { ..self, parts, }
  let part = view.new_word_part(kind, parts, edits, created)
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
  part
}
