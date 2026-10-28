///|
pub(all) struct ListLevelFormat {
  format : String
  pattern : String
  start : Int32
  restart : Int32?
  align : String
  suffix : String
  left : FormatChange[Double]
  first : FormatChange[Double]
  character : CharacterFormat
}

///|
pub fn ListLevelFormat::new(
  format : String,
  pattern : String,
  start~ : Int32 = 1,
  restart~ : Int32? = None,
  align~ : String = "left",
  suffix~ : String = "tab",
  left~ : FormatChange[Double] = Keep,
  first~ : FormatChange[Double] = Keep,
  character~ : CharacterFormat = CharacterFormat::new(),
) -> ListLevelFormat {
  { format, pattern, start, restart, align, suffix, left, first, character, }
}

///|
/// Updates the effective level's owning definition without requiring a body selection.
pub fn Session::update_list_level(
  self : Session,
  revision : Int32,
  instance : Int32,
  index : Int32,
  format : ListLevelFormat,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard instance > 0 &&
    index >= 0 &&
    index <= 8 &&
    [
      "decimal", "decimalZero", "decimalFullWidth", "decimalEnclosedCircle", "lowerLetter",
      "upperLetter", "lowerRoman", "upperRoman", "bullet",
    ].contains(format.format) &&
    !format.pattern.is_empty() &&
    format.pattern.length() <= 256 &&
    @xml.valid_text(format.pattern) &&
    !format.pattern
    .iter()
    .any(ch => ch < ' ' || ch == '\u007f' || ch == '\u2028' || ch == '\u2029') &&
    format.start >= 0 &&
    format.start <= 2147483646 &&
    format.restart.map(v => v >= 0 && v <= index).unwrap_or(true) &&
    ["left", "center", "right"].contains(format.align) &&
    ["tab", "space", "nothing"].contains(format.suffix) &&
    format.character.style is Keep else {
    @failure.reject("invalid-operation", "Invalid list level definition")
  }
  format.character.validate()
  let paragraph = ParagraphFormat::new(left=format.left, first=format.first).properties()
  let context = self.numbering_context()
  let original = context.definition(instance)
  let level = context.level(instance, index)
  let mut candidate = context.document
  let edits : Array[@xml.Edit] = []
  let mut bytes = 0
  for
    (name, value) in [
      ("start", Some(format.start.to_string())),
      ("numFmt", Some(format.format)),
      ("lvlRestart", format.restart.map(v => v.to_string())),
      ("lvlText", Some(format.pattern)),
      ("lvlJc", Some(format.align)),
      ("suff", Some(format.suffix)),
      ("pPr", None),
      ("rPr", None),
    ] {
    let tree = WordTree::new(candidate)
    let markup = if name == "pPr" {
      formatted_properties(tree, candidate, level.node, name, paragraph)
    } else if name == "rPr" {
      formatted_properties(
        tree,
        candidate,
        level.node,
        name,
        format.character.properties(),
      )
    } else {
      property_markup(
        tree,
        candidate,
        tree.child(level.node, name),
        name,
        value.map(v => Map::from_array([("val", Some(v))])),
      )
    }
    if properties_change(tree, candidate, level.node, name, markup)
      is Some(change) {
      let (updated, edit) = candidate.edit_source([change])
      let count = edit_bytes(edit)
      guard count <= history_byte_limit - bytes else {
        @failure.reject(
          "limit-exceeded", "List definition history budget exceeded",
        )
      }
      bytes += count
      edits.push(edit)
      candidate = updated
    }
  }
  if edits.is_empty() {
    return self.edit_state()
  }
  let parts = self.parts.copy()
  parts[context.part] = candidate
  let view = { ..self, parts, }
  let numbers = view.numbering_context()
  let definition = numbers.definition(instance)
  for level, _ in definition.levels {
    ignore(numbering_label(definition.levels, Array::make(9, 1), level))
  }
  let document = self.document()
  let tree = WordTree::new(document)
  let styles = self.styles([])
  let affected = numbers.validate_level_labels(
    tree,
    styles,
    Map::from_array([(original.abstract_id, true)]),
  )
  for p in view.formatting_paragraphs(document, affected) {
    validate_paragraph_style_values(p)
  }
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: Map::from_array([(context.part, edits)]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs: affected,
      bytes,
    },
    document,
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}

///|
fn NumberingContext::validate_level_labels(
  self : NumberingContext,
  tree : WordTree,
  styles : Styles,
  abstracts : Map[Int32, Bool],
) -> Array[Int32] raise @failure.Failure {
  let affected : Array[Int32] = []
  let counters : Map[Int32, NumberCounter] = Map([])
  for p in tree.order {
    if tree.nodes[p].uri != word_uri || tree.nodes[p].name != "p" {
      continue
    }
    guard styles.numbering_reference(tree, p) is Some((id, index)) else {
      continue
    }
    guard self.instances.get(id) is Some(node) &&
      self.tree.numbering_value(node, "abstractNumId") is Some(value) else {
      @failure.reject(
        "invalid-numbering", "Missing abstract numbering reference",
      )
    }
    let abstract_id = numbering_integer(value, 2147483646)
    if !abstracts.contains(abstract_id) {
      continue
    }
    let definition = self.definition(id)
    let counter = match counters.get(abstract_id) {
      Some(value) => value
      None => {
        let value : NumberCounter = {
          values: Array::make(9, 0),
          seen: Map([]),
          previous: -1,
        }
        counters[abstract_id] = value
        value
      }
    }
    counter.advance(definition, id, index)
    ignore(numbering_label(definition.levels, counter.values, index))
    affected.push(p)
  }
  affected
}
