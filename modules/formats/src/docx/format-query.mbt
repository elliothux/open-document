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
  style~ : FormatChange[String] = Keep,
) -> RunStyle raise @failure.Failure {
  let layers = self.character_layers(tree, paragraph, run, [], style~)
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
) -> (Array[RunStyle], Array[String]) raise @failure.Failure {
  let styles = self.styles([])
  let all_texts = docx_texts(tree)
  let result : Array[RunStyle] = []
  let identifiers : Array[String] = []
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
        let patch = if collapsed { pending } else { None }
        let (value, key) = styles.queried_character(
          tree,
          paragraph,
          Some(item.run),
          patch,
        )
        let text = inline_text(tree.nodes[item.id])
        if collapsed {
          result.push(
            value.caret_font(
              text,
              (first - cursor).clamp(min=0, max=text.length()),
              range.start.affinity == "before",
              styles.themes,
            ),
          )
          identifiers.push(key)
        } else {
          let selected_text = text[(first - cursor).max(0):(last - cursor).min(
            text.length(),
          )].to_owned()
          for (style, _) in value.font_runs(selected_text, styles.themes) {
            result.push(style)
            identifiers.push(key)
          }
        }
        selected = true
        if collapsed {
          break
        }
      }
      cursor = end
    }
    if !selected && texts.is_empty() {
      let patch = if collapsed { pending } else { None }
      let run = match tree.paragraph_runs(paragraph).get(0) {
        Some(run) => Some(run)
        None => tree.child(paragraph, "pPr")
      }
      let (value, key) = styles.queried_character(tree, paragraph, run, patch)
      result.push(value.caret_font("", 0, false, styles.themes))
      identifiers.push(key)
    }
  }
  (result, identifiers)
}

///|
fn Styles::queried_character(
  self : Styles,
  tree : WordTree,
  paragraph : Int,
  run : Int?,
  pending : CharacterFormat?,
) -> (RunStyle, String) raise @failure.Failure {
  let patch = pending.unwrap_or(CharacterFormat::new())
  let value = self.character_style(tree, paragraph, run, [], style=patch.style)
  let key = format_value(
    run
    .bind(id => tree.child(id, "rPr"))
    .bind(id => tree.value(id, "rStyle"))
    .unwrap_or(""),
    "",
    patch.style,
  )
  (
    if pending is Some(_) {
      value.formatted(
        self.inherited_character(tree, paragraph, run, style=patch.style),
        patch,
      )
    } else {
      value
    },
    key,
  )
}

///|
fn Session::formatting_range(
  self : Session,
  document : @xml.Document,
  selection : Selection,
  whole_cells~ : Bool = false,
) -> ParagraphRange raise @failure.Failure {
  let tree = WordTree::new(document)
  let cells = if whole_cells {
    self.table_format_range(tree, selection)
  } else {
    None
  }
  let range = cells.unwrap_or_else(() => {
    self.paragraph_range_in(
      document,
      tree,
      selection,
      structural=true,
      check_layout=false,
    )
  })
  for p in self.formatting_paragraphs(document, range.paragraphs) {
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
  layout? : @layout.Layout,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let tree = WordTree::new(self.document())
  let mut reason = ""
  let range = try
    self.formatting_range(self.document(), selection, whole_cells=true)
  catch {
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
  let (characters, character_styles) = match range {
    Some(range) => self.formatting_styles(tree, range)
    None => ([], [])
  }
  let paragraphs = match range {
    Some(range) => self.formatting_paragraphs(self.document(), range.paragraphs)
    None => []
  }
  let multiple_cells = range is Some(selected) &&
    tree.nodes[selected.start.paragraph].parent !=
    tree.nodes[selected.end.paragraph].parent
  let text_range = if multiple_cells { None } else { range }
  {
    "revision": revision,
    "reason": reason,
    "cellSelection": self.table_cell_selection(tree, selection) catch {
      @failure.Failure(message~, ..) =>
        { "value": Json::null(), "reason": message }
    },
    "hyperlink": self.hyperlink_summary(
      tree,
      text_range,
      if multiple_cells {
        "Select one table cell to edit a hyperlink"
      } else {
        reason
      },
    ),
    "table": self.table_dimensions(tree, text_range, layout),
    "list": format_summary(
      match range {
        None => []
        Some(range) => {
          let styles = self.styles([])
          range.paragraphs.map(id => {
            match styles.numbering_reference(tree, id) {
              None => Json::null()
              Some((id, level)) => { "id": id, "level": level }
            }
          })
        }
      },
      reason,
    ),
    "character": {
      "style": format_summary(character_styles, reason),
      "family": format_summary(characters.map(style => style.family), reason),
      "size": format_summary(characters.map(style => style.size), reason),
      "spacing": format_summary(characters.map(style => style.spacing), reason),
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
      "style": format_summary(
        match range {
          Some(range) => {
            let default_style = self.styles([]).default_paragraph.unwrap_or("")
            range.paragraphs.map(id => {
              tree
              .child(id, "pPr")
              .bind(p => tree.value(p, "pStyle"))
              .unwrap_or(default_style)
            })
          }
          None => []
        },
        reason,
      ),
      "align": format_summary(paragraphs.map(p => p.align), reason),
      "rtl": format_summary(paragraphs.map(p => p.rtl), reason),
      "before": format_summary(paragraphs.map(p => p.before), reason),
      "after": format_summary(paragraphs.map(p => p.after), reason),
      "left": format_summary(paragraphs.map(p => p.left), reason),
      "right": format_summary(paragraphs.map(p => p.right), reason),
      "first": format_summary(paragraphs.map(p => p.first), reason),
      "line": format_summary(paragraphs.map(p => p.line.to_json()), reason),
      "tabs": format_summary(paragraphs.map(p => Json(p.tabs)), reason),
      "pageBreakBefore": format_summary(
        paragraphs.map(p => p.pageBreakBefore),
        reason,
      ),
      "keepLines": format_summary(paragraphs.map(p => p.keepLines), reason),
      "keepNext": format_summary(paragraphs.map(p => p.keepNext), reason),
      "widowControl": format_summary(
        paragraphs.map(p => p.widowControl),
        reason,
      ),
    },
  }
}
