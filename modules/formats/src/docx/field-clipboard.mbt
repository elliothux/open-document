///|
fn Session::field_values(
  self : Session,
  tree : WordTree,
  fields : Array[Int],
  layout : @layout.Layout?,
) -> Map[Int, String] raise @failure.Failure {
  let values : Map[Int, String] = Map([])
  if fields.is_empty() {
    return values
  }
  guard fields.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Clipboard fields exceed limits")
  }
  guard layout is Some(layout) && layout.revision == self.revision else {
    @failure.reject(
      "stale-layout", "Field clipboard text requires the current layout",
    )
  }
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Field clipboard text requires a complete layout",
    )
  }
  let sources : Map[(Int, Int), Int] = Map([])
  for id in fields {
    let run = tree.field_result_run(id).unwrap()
    sources[(tree.nodes[id].parent, tree.child(run, "t").unwrap())] = id
  }
  for page in layout.pages {
    for line in page.lines {
      if line.container < 0 {
        continue
      }
      for run in line.runs {
        for source in run.sources {
          if sources.get((line.paragraph, source.node)) is Some(id) {
            guard values
              .get(id)
              .map(previous => previous == run.text)
              .unwrap_or(true) else {
              @failure.reject(
                "unsupported-layout", "Field clipboard result is ambiguous",
              )
            }
            values[id] = run.text
          }
        }
      }
    }
  }
  guard values.length() == sources.length() else {
    @failure.reject(
      "unsupported-layout", "Field clipboard position is unavailable",
    )
  }
  values
}

///|
fn Session::selection_field_values(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
  layout : @layout.Layout?,
) -> Map[Int, String] raise @failure.Failure {
  let selected : Array[Int] = []
  let math : Map[Int, String] = Map([])
  let paragraphs = Map::from_array(range.paragraphs.map(p => (p, true)))
  let offsets : Map[Int, Int] = Map([])
  for item in docx_texts(tree) {
    if !paragraphs.contains(item.paragraph) {
      continue
    }
    let offset = offsets.get(item.paragraph).unwrap_or(0)
    let length = inline_text(tree.nodes[item.id]).length()
    let start = if item.paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if item.paragraph == range.end.paragraph {
      range.end.offset
    } else {
      2147483647
    }
    if tree.nodes[item.id].name == "fldSimple" &&
      start < offset + length &&
      end > offset {
      selected.push(item.id)
    }
    if tree.nodes[item.id].uri == math_uri &&
      start < offset + length &&
      end > offset {
      let (_, content) = self.math_target(tree, item.id)
      math[item.id] = content.math_text().unwrap()
    }
    offsets[item.paragraph] = offset + length
  }
  let values = self.field_values(tree, selected, layout)
  for id, text in math {
    values[id] = text
  }
  values
}

///|
fn Session::field_cache_changes(
  self : Session,
  tree : WordTree,
  fields : Array[Int],
  layout : @layout.Layout,
) -> Map[Int, String] raise @failure.Failure {
  let values = self.field_values(tree, fields, Some(layout))
  let changes : Map[Int, String] = Map([])
  for id in fields {
    let primary = tree.child(tree.field_result_run(id).unwrap(), "t").unwrap()
    for text in tree.descendants(id) {
      if tree.nodes[text].uri == word_uri && tree.nodes[text].name == "t" {
        let value = if text == primary { values[id] } else { "" }
        if tree.nodes[text].text != value {
          changes[text] = value
        }
      }
    }
  }
  changes
}

///|
fn fragment_field_markup(
  tree : WordTree,
  document : @xml.Document,
  paragraph : Int,
  field : Int,
  styles : Styles,
  value : String,
  limit : Int,
) -> String raise @failure.Failure {
  let code = running_field_code(
    tree.nodes[field].attribute("instr", uri=word_uri).unwrap_or(""),
  )
  let run = tree.field_result_run(field).unwrap()
  let style = styles
    .character_style(tree, paragraph, Some(run), [])
    .caret_font(value, 0, false, styles.themes)
  let format = style.fragment_format()
  format.validate()
  let properties = formatted_properties(
    tree,
    document,
    run,
    "rPr",
    format.properties(),
  )
  let instruction = property_attribute(running_field_instruction(code))
  let markup = "<od:fldSimple od:instr=\"\{instruction}\" od:dirty=\"true\"><od:r>\{properties}\{inline_markup(value,limit)}</od:r></od:fldSimple>"
  guard markup.length() <= limit else {
    @failure.reject("limit-exceeded", "Rich field exceeds clipboard budget")
  }
  markup
}
