///|
fn local_table_tokens(tokens : Array[Token]) -> Bool {
  for index, token in tokens {
    if token is Brackets(_) && !(index > 0 && tokens[index - 1] is Word(_)) {
      return true
    }
  }
  false
}

///|
fn resized_table_formula(
  text : String,
  table : StructuredTable,
  removed : Array[String],
  in_table~ : Bool,
  exiting~ : Bool,
) -> String raise @failure.Failure {
  let spans : Array[(Int, Int)] = []
  let tokens = formula_tokens(text, spans~)
  let changes : Array[(Int, Int, String)] = []
  for index, token in tokens {
    guard token is Brackets(selector) else { continue }
    let explicit = index > 0 &&
      tokens[index - 1] is Word(name) &&
      name.to_upper() == table.name.to_upper()
    let qualified = index > 0 && tokens[index - 1] is Word(_)
    if !explicit && (!in_table || qualified) {
      continue
    }
    let broken = table_selector(selector).columns.any(item => {
      removed.contains(item.0.to_upper())
    })
    if broken {
      changes.push(
        (
          spans[if explicit { index - 1 } else { index }].0,
          spans[index].1,
          "#REF!",
        ),
      )
    } else if !qualified && exiting {
      changes.push((spans[index].0, spans[index].0, table.name))
    }
  }
  let output = StringBuilder()
  let mut cursor = 0
  for (first, last, replacement) in changes {
    output.write_view(text[cursor:first])
    output.write_string(replacement)
    cursor = last
  }
  output.write_view(text[cursor:])
  let result = output.to_string()
  guard result.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Resized table formula exceeds budget")
  }
  result
}

///|
fn resized_table_references(
  document : @xml.Document,
  table : StructuredTable,
  range : Range,
  removed : Array[String],
  owner : String,
  work : FormulaWork,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(document)
  let result : Array[@xml.SourceChange] = []
  for node in document.nodes() {
    if node.uri != spreadsheet_uri ||
      ![
        "f", "formula", "formula1", "formula2", "definedName", "calculatedColumnFormula",
        "totalsRowFormula",
      ].contains(node.name) ||
      node.text.is_empty() {
      continue
    }
    work.spend(amount=node.text.length() + 1)
    let mut in_table = owner == table.part
    let mut exiting = false
    if owner == table.sheet {
      if tree.nodes.get(node.parent) is Some(parent) && parent.name == "c" {
        let address = Address::parse(parent.attribute("r").unwrap_or(""))
        in_table = table.range.contains(address)
        exiting = in_table && !range.contains(address)
      } else if local_table_tokens(formula_tokens(node.text)) {
        @failure.reject(
          "protected-content", "Local table references in worksheet rules require table-aware range editing",
        )
      }
    }
    let text = resized_table_formula(
      node.text,
      table,
      removed,
      in_table~,
      exiting~,
    )
    if text != node.text {
      result.append(axis_text_change(tree, node, text))
    }
  }
  result
}

///|
fn resized_table_conditions(
  document : @xml.Document,
  table : StructuredTable,
  range : Range,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let result : Array[@xml.SourceChange] = []
  guard range.covers(table.range) else { return result }
  let tree = Tree::new(document)
  for node in tree.all(tree.root("worksheet").id, "conditionalFormatting") {
    let bounds = clear_rule_ranges(node.attribute("sqref").unwrap_or(""))
    let updated = bounds.map(bound => {
      let whole = bound.left == table.range.left &&
        bound.right == table.range.right
      let column = bound.left == bound.right &&
        bound.left >= table.range.left &&
        bound.right <= table.range.right
      let full = bound.top == table.range.top &&
        bound.bottom == table.range.bottom
      let body = bound.top == table.range.top + table.headers &&
        bound.bottom == table.range.bottom - table.totals
      if (whole || column) && (full || body) {
        { ..bound, bottom: bound.bottom + range.bottom - table.range.bottom, }
      } else {
        bound
      }
    })
    if updated != bounds {
      result.append(
        metadata_changes(node, [("sqref", updated.map(Range::name).join(" "))]),
      )
    }
  }
  result
}
