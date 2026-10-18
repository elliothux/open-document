///|
fn note_source(
  address : Address,
  text : String,
  author : Int,
) -> String raise @failure.Failure {
  "<od:comment xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{address.name()}\" authorId=\"\{author}\"><od:text><od:t xml:space=\"preserve\">\{encode_text(text)}</od:t></od:text></od:comment>"
}

///|
fn note_body(
  tree : Tree,
  note : CellNote,
  text : String,
) -> String raise @failure.Failure {
  let value = "<odNote:t xmlns:odNote=\"\{spreadsheet_uri}\" xml:space=\"preserve\">\{encode_text(text)}</odNote:t>"
  guard tree.all(note.body.id, "r").get(0) is Some(run) else { return value }
  let source = tree.document.source()
  let opening = if run.empty {
    source[run.start:run.opening_end - 2].to_owned() + ">"
  } else {
    source[run.start:run.opening_end].to_owned()
  }
  let style = tree
    .one(run.id, "rPr")
    .map(n => source[n.start:n.end].to_owned())
    .unwrap_or("")
  opening + style + value + "</\{run.qualified}>"
}

///|
fn insert_note_vml(
  document : @xml.Document,
  relation : String,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let markup = "<od:legacyDrawing xmlns:od=\"\{spreadsheet_uri}\" xmlns:odRel=\"\{relationship_uri[:relationship_uri.length()-1]}\" odRel:id=\"\{escaped_attribute(relation)}\"/>"
  let next = tree.children
    .get(root.id)
    .unwrap_or([])
    .iter()
    .find_first(node => {
      [
        "legacyDrawingHF", "picture", "oleObjects", "controls", "webPublishItems",
        "tableParts", "extLst",
      ].contains(node.name)
    })
  let change : @xml.SourceChange = if next is Some(node) {
    { node: root.id, offset: node.start - root.start, length: 0, xml: markup, }
  } else {
    insertion(root, markup)
  }
  document.edit_source([change])
}
