///|
fn transform_conditional_rules(
  tree : Tree,
  container : @xml.Node,
  after : Array[Range],
  source_position : (Address) -> Address?,
  transform : (String) -> String raise @failure.Failure,
  work : RuleShiftWork,
) -> (Array[@xml.SourceChange], Int) raise @failure.Failure {
  shift_rule_clone_guard(tree, container)
  let rules = tree.all(container.id, "cfRule")
  let output = StringBuilder()
  let mut changed = false
  let mut count = 0
  for rule in rules {
    let removals : Array[@xml.SourceChange] = rules
      .filter(n => n.id != rule.id)
      .map(n => {
        node: container.id,
        offset: n.start - container.start,
        length: n.end - n.start,
        xml: "",
      })
    let wrapper = @xml.Document::parse(
      @utf8.encode(
        "<worksheet xmlns=\"\{spreadsheet_uri}\">" +
        style_markup(tree, container, changes=removals) +
        "</worksheet>",
      ),
      "cell-rule-fragment",
      128,
      work.limit,
    )
    let fragment = Tree::new(wrapper)
    let (changes, fragments) = transform_rule_changes(
      fragment,
      fragment.all(fragment.root("worksheet").id, "conditionalFormatting")[0],
      after,
      source_position,
      transform,
      work,
    )
    changed = changed || !changes.is_empty()
    count += fragments
    let (next, _) = wrapper.edit_source(changes)
    let next_tree = Tree::new(next)
    for
      node in next_tree.all(
        next_tree.root("worksheet").id,
        "conditionalFormatting",
      ) {
      let markup = style_markup(next_tree, node)
      guard markup.length() <= work.limit - work.source else {
        @failure.reject(
          "limit-exceeded", "Transformed rule source exceeds budget",
        )
      }
      work.source += markup.length()
      output.write_string(markup)
    }
  }
  if changed {
    (
      [{ ..sheet_node_removal(tree, container), xml: output.to_string(), }],
      count,
    )
  } else {
    ([], 1)
  }
}
