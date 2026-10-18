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
