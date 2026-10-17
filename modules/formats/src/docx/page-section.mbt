///|
fn page_section(
  document : @xml.Document,
  tree : WordTree,
  section : Int?,
) -> (@xml.Document, Array[@xml.Edit], Int) raise @failure.Failure {
  if section is Some(id) {
    return (document, [], id)
  }
  let body = tree.child(0, "body").unwrap()
  let node = tree.nodes[body]
  let markup = "<od:sectPr xmlns:od=\"\{word_uri}\"/>"
  let change : @xml.SourceChange = if node.empty {
    {
      node: body,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{markup}</\{node.qualified}>",
    }
  } else {
    {
      node: body,
      offset: node.closing_start - node.start,
      length: 0,
      xml: markup,
    }
  }
  let (candidate, edit) = document.edit_source([change])
  (candidate, [edit], WordTree::new(candidate).child(body, "sectPr").unwrap())
}
