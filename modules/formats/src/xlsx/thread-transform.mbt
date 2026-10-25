///|
fn update_thread_addresses(
  threads : SheetThreads,
  addresses : Map[String, Address?],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
) -> Unit raise @failure.Failure {
  guard threads.tree is Some(tree) else { return }
  let changes : Array[@xml.SourceChange] = []
  for message in threads.messages {
    guard addresses.get(message.address.name()) is Some(next) else { continue }
    if next == Some(message.address) {
      continue
    }
    if next is Some(address) {
      // Replies may inherit the root address without storing a ref attribute.
      if message.node.attribute("ref") is Some(_) {
        changes.append(
          metadata_changes(message.node, [("ref", address.name())]),
        )
      }
    } else {
      changes.push(sheet_node_removal(tree, message.node))
    }
  }
  if !changes.is_empty() {
    let (document, edit) = tree.document.edit_source(changes)
    let part = threads.part.unwrap()
    parts[part] = document
    edits.push((part, edit))
  }
}
