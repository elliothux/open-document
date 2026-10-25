///|
fn Session::copied_thread_ids(
  self : Session,
  threads : SheetThreads,
  notes : SheetNotes?,
  new_people~ : Array[String] = [],
) -> Map[String, String] raise @failure.Failure {
  let originals = threads.messages.map(m => m.id)
  let seen : Set[String] = Set::from_array(originals)
  for id in new_people {
    if !seen.contains(id) {
      originals.push(id)
      seen.add(id)
    }
  }
  let uids : Set[String] = Set([])
  for note in notes.map(n => n.entries).unwrap_or([]) {
    if note.node.attribute(
        "uid",
        uri="http://schemas.microsoft.com/office/spreadsheetml/2014/revision",
      )
      is Some(value) {
      let id = thread_guid(value)
      guard !uids.contains(id) else {
        @failure.reject(
          "protected-content", "Duplicate comment revision identity",
        )
      }
      uids.add(id)
      if !seen.contains(id) {
        originals.push(id)
        seen.add(id)
      }
    }
  }
  let used = self.thread_ids()
  for id in originals {
    used.add(id)
  }
  for person in threads.people {
    used.add(person.id)
  }
  for link in self.relationships() {
    if !link.external && link.kind == relationship_uri + "comments" {
      for node in self.part_xml(link.target).nodes() {
        for
          value in [
            node.attribute("guid"),
            node.attribute(
              "uid",
              uri="http://schemas.microsoft.com/office/spreadsheetml/2014/revision",
            ),
          ] {
          if value is Some(value) {
            used.add(thread_guid(value)) catch {
              @failure.Failure(..) => ()
            }
          }
        }
      }
    }
  }
  let ids : Map[String, String] = Map([])
  // Collect once and walk the bounded identity space once for a whole sheet.
  for i in 1..<=16384 {
    if ids.length() == originals.length() {
      break
    }
    let next = numbered_thread_id(i)
    if !used.contains(next) {
      ids[originals[ids.length()]] = next
    }
  }
  guard ids.length() == originals.length() else {
    @failure.reject("limit-exceeded", "Copied thread identities exhausted")
  }
  ids
}

///|
fn Session::copy_sheet_threads(
  self : Session,
  threads : SheetThreads,
  number : Int,
  ids : Map[String, String],
  created : Map[String, @xml.Document],
  remapped : Map[String, String],
  types : StringBuilder,
) -> Unit raise @failure.Failure {
  guard threads.part is Some(source) && threads.tree is Some(tree) else {
    return
  }
  guard !self.relationships().any(link => link.owner == source) else {
    @failure.reject(
      "protected-content", "Thread resources require independent copying support",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for message in threads.messages {
    let values = [("id", ids[message.id])]
    if message.parent is Some(parent) {
      values.push(("parentId", ids[parent]))
    }
    changes.append(metadata_changes(message.node, values))
  }
  let bytes = if changes.is_empty() {
    tree.document.bytes()
  } else {
    tree.document.edit_source(changes).0.bytes()
  }
  let directory = self.main.split("/").map(p => p.to_owned()).to_array()
  ignore(directory.pop())
  let prefix = if directory.is_empty() { "" } else { directory.join("/") + "/" }
  let part = for i in 0..<=self.budget.entries {
    let part = prefix + "threadedComments/odSheet\{number}-\{i}.xml"
    if !self.opc.names.contains(part.to_lower()) &&
      !self.parts.contains(part) &&
      !created.contains(part) &&
      !self.opc.names.contains(workbook_relations(part).to_lower()) &&
      !self.parts.contains(workbook_relations(part)) {
      break part
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Copied thread part identities exhausted")
  }
  created[part] = @xml.Document::parse(
    bytes,
    part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  remapped[source] = part
  types.write_string(
    "<od:Override xmlns:od=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/\{escaped_attribute(part)}\" ContentType=\"application/vnd.ms-excel.threadedcomments+xml\"/>",
  )
  if self.copy_sheet_relations(source, part, remapped) is Some(document) {
    created[workbook_relations(part)] = document
  }
}
