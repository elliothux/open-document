///|
fn[T : Eq + ToJson] format_summary(values : Array[T], reason : String) -> Json {
  if values.is_empty() {
    return { "kind": "unavailable", "reason": reason }
  }
  let value = values[0]
  if values.iter().any(item => item != value) {
    { "kind": "mixed" }
  } else {
    { "kind": "value", "value": ToJson::to_json(value) }
  }
}

///|
fn Styles::inherited_character(
  self : Styles,
  tree : WordTree,
  paragraph : Int,
  run : Int?,
) -> RunStyle raise @failure.Failure {
  let layers = self.character_layers(tree, paragraph, run, [])
  if run is Some(run) && tree.child(run, "rPr") is Some(_) {
    ignore(layers.pop())
  }
  let mut style = self.defaults
  for (tree, id, inherited) in layers {
    style = run_properties(tree, id, style, self.themes, inherited~)
  }
  style
}

///|
fn Session::formatting_styles(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
) -> Array[RunStyle] raise @failure.Failure {
  let styles = self.styles([])
  let all_texts = docx_texts(tree)
  let result : Array[RunStyle] = []
  let collapsed = range.start.paragraph == range.end.paragraph &&
    range.start.offset == range.end.offset
  let pending = if self.selection ==
    Some({ anchor: range.start, focus: range.end, }) {
    self.typing_format
  } else {
    None
  }
  for paragraph in range.paragraphs {
    let texts = all_texts.filter(item => item.paragraph == paragraph)
    let mut cursor = 0
    let mut selected = false
    let first = if paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let last = if paragraph == range.end.paragraph {
      range.end.offset
    } else {
      0x7fffffff
    }
    for index, item in texts {
      let end = cursor + inline_text(tree.nodes[item.id]).length()
      let hit = if collapsed {
        first < end ||
        (first == end && range.start.affinity == "before") ||
        index == texts.length() - 1
      } else {
        first < end && last > cursor
      }
      if hit {
        let style = styles.character_style(tree, paragraph, Some(item.run), [])
        let style = if collapsed && pending is Some(patch) {
          style.formatted(
            styles.inherited_character(tree, paragraph, Some(item.run)),
            patch,
          )
        } else {
          style
        }
        result.push(style)
        selected = true
        if collapsed {
          break
        }
      }
      cursor = end
    }
    if !selected && texts.is_empty() {
      let inherited = styles.character_style(tree, paragraph, None, [])
      let style = if tree
        .child(paragraph, "pPr")
        .bind(id => tree.child(id, "rPr"))
        is Some(id) {
        run_properties(tree, id, inherited, styles.themes)
      } else {
        inherited
      }
      result.push(
        if collapsed && pending is Some(patch) {
          style.formatted(inherited, patch)
        } else {
          style
        },
      )
    }
  }
  result
}

///|
fn Session::formatting_range(
  self : Session,
  document : @xml.Document,
  selection : Selection,
) -> ParagraphRange raise @failure.Failure {
  let tree = WordTree::new(document)
  let range = self.paragraph_range_in(
    document,
    tree,
    selection,
    structural=true,
    check_layout=false,
  )
  let styles = self.styles([])
  for paragraph in range.paragraphs {
    let p = self.paragraph(tree, styles, paragraph, [])
    guard p.readOnlyReason.is_empty() else {
      @failure.reject("protected-content", p.readOnlyReason)
    }
  }
  range
}

///|
/// Queries all effective values in the range; mixed values never use its first character.
pub fn Session::query_formatting(
  self : Session,
  revision : Int,
  selection : Selection,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let mut reason = ""
  let range = try self.formatting_range(self.document(), selection) catch {
    @failure.Failure(
      code="invalid-position"
      | "stale-revision"
      | "closed-session"
      | "busy",
      ..
    ) as error => raise error
    @failure.Failure(message~, ..) => {
      reason = message
      None
    }
  } noraise {
    value => Some(value)
  }
  let characters = match range {
    Some(range) => self.formatting_styles(tree, range)
    None => []
  }
  let paragraphs = match range {
    Some(range) => {
      let styles = self.styles([])
      range.paragraphs.map(id => self.paragraph(tree, styles, id, []))
    }
    None => []
  }
  {
    "revision": revision,
    "reason": reason,
    "character": {
      "family": format_summary(characters.map(style => style.family), reason),
      "size": format_summary(characters.map(style => style.size), reason),
      "color": format_summary(characters.map(style => style.color), reason),
      "bold": format_summary(characters.map(style => style.bold), reason),
      "italic": format_summary(characters.map(style => style.italic), reason),
      "underline": format_summary(
        characters.map(style => style.underline),
        reason,
      ),
      "strike": format_summary(characters.map(style => style.strike), reason),
      "highlight": format_summary(
        characters.map(style => style.highlight),
        reason,
      ),
      "vertAlign": format_summary(
        characters.map(style => style.vertAlign),
        reason,
      ),
    },
    "paragraph": {
      "align": format_summary(paragraphs.map(p => p.align), reason),
      "before": format_summary(paragraphs.map(p => p.before), reason),
      "after": format_summary(paragraphs.map(p => p.after), reason),
      "left": format_summary(paragraphs.map(p => p.left), reason),
      "right": format_summary(paragraphs.map(p => p.right), reason),
      "first": format_summary(paragraphs.map(p => p.first), reason),
      "line": format_summary(paragraphs.map(p => p.line.to_json()), reason),
      "pageBreakBefore": format_summary(
        paragraphs.map(p => p.pageBreakBefore),
        reason,
      ),
    },
  }
}
