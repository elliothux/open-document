///|
priv struct NumberLevel {
  node : Int
  start : Int
  restart : Int
  format : String
  pattern : String
  align : String
  suffix : String
}

///|
priv struct NumberDefinition {
  abstract_id : Int
  base_levels : Map[Int, NumberLevel]
  levels : Map[Int, NumberLevel]
  overrides : Map[Int, Int]
}

///|
priv struct NumberCounter {
  values : Array[Int]
  seen : Map[Int, Bool]
  mut previous : Int
}

///|
fn numbering_integer(
  value : String,
  maximum : Int,
) -> Int raise @failure.Failure {
  let number = @string.parse_int(value[:]) catch {
    _ => @failure.reject("invalid-numbering", "Invalid numbering integer")
  }
  guard number >= 0 && number <= maximum else {
    @failure.reject("invalid-numbering", "Numbering integer is out of range")
  }
  number
}

///|
fn WordTree::numbering_shape(
  self : WordTree,
  id : Int,
  attributes : Array[String],
  children : Array[String],
  repeated~ : String = "",
) -> Unit raise @failure.Failure {
  let node = self.nodes[id]
  guard node.uri == word_uri &&
    node.text.trim().is_empty() &&
    node.attributes
    .iter()
    .all(a => a.uri == word_uri && attributes.contains(a.name)) else {
    @failure.reject("unsupported-numbering", "Unsupported numbering properties")
  }
  let names : Map[String, Bool] = Map([])
  for child in self.children[id] {
    let node = self.nodes[child]
    guard node.uri == word_uri &&
      children.contains(node.name) &&
      (node.name == repeated || !names.contains(node.name)) else {
      @failure.reject(
        "unsupported-numbering", "Unknown or duplicate numbering child",
      )
    }
    names[node.name] = true
  }
}

///|
fn WordTree::numbering_value(
  self : WordTree,
  parent : Int,
  name : String,
) -> String? raise @failure.Failure {
  guard self.child(parent, name) is Some(id) else { return None }
  self.numbering_shape(id, ["val"], [])
  guard self.nodes[id].attribute("val", uri=word_uri) is Some(value) else {
    @failure.reject("invalid-numbering", "Missing numbering value")
  }
  Some(value)
}

///|
fn Styles::numbering_reference(
  self : Styles,
  tree : WordTree,
  paragraph : Int,
  style~ : FormatChange[String] = Keep,
) -> (Int, Int)? raise @failure.Failure {
  fn merge(
    tree : WordTree,
    parent : Int,
    previous : (Int?, Int),
  ) -> (Int?, Int) raise @failure.Failure {
    guard tree.child(parent, "numPr") is Some(id) else { return previous }
    tree.numbering_shape(id, [], ["numId", "ilvl"])
    (
      match tree.numbering_value(id, "numId") {
        Some(value) => Some(numbering_integer(value, 2147483646))
        None => previous.0
      },
      tree
      .numbering_value(id, "ilvl")
      .map(value => numbering_integer(value, 8))
      .unwrap_or(previous.1),
    )
  }
  let props = tree.child(paragraph, "pPr")
  let key = match style {
    Set(key) => Some(key)
    Clear => self.default_paragraph
    Keep =>
      match props.bind(p => tree.value(p, "pStyle")) {
        Some(key) => Some(key)
        None => self.default_paragraph
      }
  }
  let mut reference : (Int?, Int) = (None, 0)
  if key is Some(key) && self.tree is Some(style_tree) {
    for style in self.chain(key, []) {
      if style_tree.child(style, "pPr") is Some(p) {
        reference = merge(style_tree, p, reference)
      }
    }
  }
  if props is Some(p) {
    reference = merge(tree, p, reference)
  }
  match reference.0 {
    Some(id) if id > 0 => Some((id, reference.1))
    _ => None
  }
}

///|
fn WordTree::number_definition(
  self : WordTree,
  id : Int,
  instances : Map[Int, Int],
  abstracts : Map[Int, Int],
) -> NumberDefinition raise @failure.Failure {
  guard instances.get(id) is Some(instance) else {
    @failure.reject(
      "invalid-numbering", "Missing or duplicate numbering instance",
    )
  }
  self.numbering_shape(
    instance,
    ["numId"],
    ["abstractNumId", "lvlOverride"],
    repeated="lvlOverride",
  )
  guard self.numbering_value(instance, "abstractNumId") is Some(key) else {
    @failure.reject("invalid-numbering", "Missing abstract numbering reference")
  }
  let abstract_id = numbering_integer(key, 2147483646)
  guard abstracts.get(abstract_id) is Some(definition) else {
    @failure.reject(
      "invalid-numbering", "Missing or duplicate abstract numbering",
    )
  }
  self.numbering_shape(
    definition,
    ["abstractNumId"],
    ["nsid", "multiLevelType", "tmpl", "name", "lvl"],
    repeated="lvl",
  )
  let levels : Map[Int, NumberLevel] = Map([])
  for node in self.children[definition] {
    if self.nodes[node].name == "lvl" {
      let (index, level) = self.number_level(node)
      guard !levels.contains(index) else {
        @failure.reject("invalid-numbering", "Duplicate numbering level")
      }
      levels[index] = level
    }
  }
  let base_levels = levels.copy()
  let overrides : Map[Int, Int] = Map([])
  let seen : Map[Int, Bool] = Map([])
  for item in self.children[instance] {
    if self.nodes[item].name != "lvlOverride" {
      continue
    }
    self.numbering_shape(item, ["ilvl"], ["startOverride", "lvl"])
    let index = numbering_integer(
      self.nodes[item].attribute("ilvl", uri=word_uri).unwrap_or("-1"),
      8,
    )
    guard !seen.contains(index) else {
      @failure.reject("invalid-numbering", "Duplicate numbering level override")
    }
    seen[index] = true
    if self.numbering_value(item, "startOverride") is Some(start) {
      overrides[index] = numbering_integer(start, 2147483646)
    }
    if self.child(item, "lvl") is Some(node) {
      let (actual, level) = self.number_level(node)
      guard actual == index else {
        @failure.reject(
          "invalid-numbering", "Mismatched numbering level override",
        )
      }
      levels[index] = level
    }
  }
  { abstract_id, base_levels, levels, overrides, }
}

///|
fn NumberCounter::advance(
  self : NumberCounter,
  definition : NumberDefinition,
  id : Int,
  level : Int,
) -> Unit raise @failure.Failure {
  // ONLYOFFICE DocumentNumberingInfoEngine: parent resets and first-instance overrides.
  if self.previous < 0 {
    for i in 0..<9 {
      self.values[i] = definition.base_levels
        .get(i)
        .map(l => l.start)
        .unwrap_or(0) -
        1
    }
  } else if level < self.previous {
    for i in (level + 1)..<9 {
      let restart = definition.base_levels
        .get(i)
        .map(l => l.restart)
        .unwrap_or(-1)
      if restart != 0 && (restart < 0 || level < restart) {
        self.values[i] = definition.base_levels
          .get(i)
          .map(l => l.start)
          .unwrap_or(0) -
          1
      }
    }
  }
  if level > self.previous {
    for i in (self.previous + 1)..<level {
      self.values[i] += 1
    }
  }
  guard self.values[level] < 2147483646 else {
    @failure.reject("limit-exceeded", "Numbering counter overflow")
  }
  self.values[level] += 1
  if !self.seen.contains(id) {
    self.seen[id] = true
    if definition.overrides.get(level) is Some(start) {
      self.values[level] = start
    }
  }
  for i in 0..<level {
    if self.values[i] == 0 {
      self.values[i] = 1
    }
  }
  self.previous = level
}

///|
fn Session::apply_numbering(
  self : Session,
  tree : WordTree,
  styles : Styles,
  paragraphs : Map[Int, @layout.Paragraph],
  backgrounds : Map[Int, String],
) -> Unit raise @failure.Failure {
  let references : Map[Int, (Int, Int)] = Map([])
  for id in tree.order {
    if paragraphs.contains(id) {
      if styles.numbering_reference(tree, id) is Some(reference) {
        references[id] = reference
      }
    }
  }
  if references.is_empty() {
    return
  }
  let context = self.numbering_context()
  let numbers = context.tree
  let counters : Map[Int, NumberCounter] = Map([])
  for id in tree.order {
    guard references.get(id) is Some((instance, index)) else { continue }
    let definition = context.definition(instance)
    guard definition.levels.get(index) is Some(level) else {
      @failure.reject("invalid-numbering", "Missing numbering level")
    }
    let counter = match counters.get(definition.abstract_id) {
      Some(value) => value
      None => {
        let value : NumberCounter = {
          values: Array::make(9, 0),
          seen: Map([]),
          previous: -1,
        }
        counters[definition.abstract_id] = value
        value
      }
    }
    counter.advance(definition, instance, index)
    let text = numbering_label(definition.levels, counter.values, index)
    let paragraph = context.properties(tree, paragraphs[id], instance, index)
    let mut character = styles.character_style(tree, id, None, [])
    if tree.child(id, "pPr") is Some(p) {
      let underline = character.underline
      character = styles.run_character_style(tree, p, character, [])
      // Paragraph-mark underline does not apply to numbering; level underline still can.
      character = { ..character, underline, }
    }
    if numbers.child(level.node, "rPr") is Some(p) {
      character = run_properties(numbers, p, character, styles.themes)
    }
    character = character.font_runs(text, styles.themes)[0].0
    paragraphs[id] = {
      ..paragraph,
      marker: Some({
        text,
        numbering: Some({
          instance,
          numeric: !["bullet", "none"].contains(level.format),
          values: counter.values[:index + 1].to_owned(),
          labels: Array::makei(index + 1, current => {
            definition.levels
            .get(current)
            .bind(_ => {
              // Unused parent templates must not block the current list text.
              Some(
                numbering_label(
                  definition.levels,
                  counter.values,
                  current,
                  reference=current == index,
                ),
              ) catch {
                @failure.Failure(code="unsupported-numbering", ..) as error => {
                  if current == index {
                    raise error
                  }
                  None
                }
                error => raise error
              }
            })
          }),
        }),
        align: level.align,
        suffix: level.suffix,
        style: {
          font: character.key(),
          size: character.size,
          color: character.text_color(backgrounds[id]),
          underline: character.underline,
          strike: character.strike,
          highlight: highlight_color(character.highlight),
          script: character.vertAlign,
          spacing: character.spacing,
        },
      }),
    }
  }
}
