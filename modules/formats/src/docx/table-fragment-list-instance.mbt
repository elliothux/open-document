///|
fn NumberingContext::fragment_instance(
  self : NumberingContext,
  source : @xml.Document,
  tree : WordTree,
  original : Int32,
  copied : Int32,
  underline : Bool,
  first : Bool,
  limit : Int32,
) -> String raise @failure.Failure {
  let definition = self.definition(original)
  let output = StringBuilder()
  output.write_string(
    "<od:num xmlns:od=\"\{word_uri}\" od:numId=\"\{copied}\"><od:abstractNumId od:val=\"\{definition.abstract_id}\"/>",
  )
  for index in 0..<9 {
    // Reapplying a start override on another style variant would reset the shared counter.
    let start = if first { definition.overrides.get(index) } else { None }
    let markup = definition.levels
      .get(index)
      .map(level => {
        let inherited = tree
          .child(level.node, "rPr")
          .bind(p => tree.child(p, "u"))
          is None
        if !inherited &&
          definition.base_levels.get(index).map(base => base.node) ==
          Some(level.node) {
          return ""
        }
        let document = fragment_numbering_document(
          tree.standalone_markup(source, level.node),
          limit,
        )
        let level_tree = WordTree::new(document)
        let changes : Array[@xml.SourceChange] = []
        if inherited {
          let props = CharacterFormat::new(underline=Set(underline)).properties()
          let markup = formatted_properties(
            level_tree, document, 0, "rPr", props,
          )
          if properties_change(level_tree, document, 0, "rPr", markup)
            is Some(change) {
            changes.push(change)
          }
        }
        let candidate = if changes.is_empty() {
          document
        } else {
          document.edit_source(changes).0
        }
        candidate.source()
      })
      .unwrap_or("")
    if start is None && markup.is_empty() {
      continue
    }
    output.write_string("<od:lvlOverride od:ilvl=\"\{index}\">")
    if start is Some(start) {
      output.write_string("<od:startOverride od:val=\"\{start}\"/>")
    }
    output.write_string(markup)
    output.write_string("</od:lvlOverride>")
  }
  output.write_string("</od:num>")
  output.to_string()
}
