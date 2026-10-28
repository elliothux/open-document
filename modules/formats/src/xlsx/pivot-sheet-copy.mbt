///|
fn Session::copy_sheet_pivots(
  self : Session,
  source : Sheet,
  number : Int32,
  created : Map[String, @xml.Document],
  remapped : Map[String, String],
  types : StringBuilder,
) -> Unit raise @failure.Failure {
  let known = self.pivot_locations()
  let copied = known.filter(pivot => pivot.sheet == source.id)
  if copied.is_empty() {
    return
  }
  guard known.length() + copied.length() <= 16 else {
    @failure.reject(
      "limit-exceeded", "Copied pivots exceed the workbook pivot limit",
    )
  }
  let names = Set::from_array(known.map(pivot => pivot.name.to_lower()))
  let links = self.relationships()
  let directory = self.main.split("/").map(p => p.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  for pivot in copied {
    ignore(
      self.pivot_settings(pivot, shared=true, source_sheet=Some(source.id)),
    )
    guard links.filter(link => !link.external && link.target == pivot.part)
      is [owner] &&
      owner.owner == source.id &&
      owner.kind == relationship_uri + "pivotTable" &&
      links.filter(link => link.owner == pivot.part) is [cache] &&
      !cache.external &&
      cache.target == pivot.cache &&
      cache.kind == relationship_uri + "pivotCacheDefinition" else {
      @failure.reject(
        "protected-content", "Pivot ownership or resources require copying support",
      )
    }
    let name = for i in 1..<=65 {
      let suffix = "_" + i.to_string()
      let mut end = pivot.name.length().min(255 - suffix.length())
      if end > 0 &&
        pivot.name[end - 1] >= 0xd800 &&
        pivot.name[end - 1] <= 0xdbff {
        end -= 1
      }
      let name = pivot.name[:end].to_owned() + suffix
      if !names.contains(name.to_lower()) {
        break name
      }
    } nobreak {
      @failure.reject("limit-exceeded", "Copied pivot names exhausted")
    }
    validate_defined_name(name)
    names.add(name.to_lower())
    let part = for i in 0..<=self.budget.entries {
      let part = prefix + "pivotTables/odSheet\{number}-\{i}.xml"
      if !self.opc.names.contains(part.to_lower()) &&
        !self.parts.contains(part) &&
        !created.contains(part) &&
        !self.opc.names.contains(workbook_relations(part).to_lower()) &&
        !self.parts.contains(workbook_relations(part)) {
        break part
      }
    } nobreak {
      @failure.reject(
        "limit-exceeded", "Copied pivot part identities exhausted",
      )
    }
    let original = self.part_xml(pivot.part)
    let changed = original.edit_source(
        metadata_changes(original.nodes()[0], [("name", name)]),
      ).0
    guard changed.source().length() <= 2097152 else {
      @failure.reject("limit-exceeded", "Copied pivot exceeds history budget")
    }
    created[part] = @xml.Document::parse(
      changed.bytes(),
      part,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
    remapped[pivot.part] = part
    // Native worksheet copies keep the original cache and data source until an explicit source edit.
    created[workbook_relations(part)] = self
      .copy_sheet_relations(pivot.part, part, remapped)
      .unwrap()
    types.write_string(
      "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.pivotTable+xml\"/>",
    )
  }
}
