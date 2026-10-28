///|
fn fragment_numbering_document(
  source : String,
  limit : Int32,
) -> @xml.Document raise @failure.Failure {
  @xml.Document::parse(@utf8.encode(source), "table-numbering", 128, limit)
}

///|
fn NumberingContext::check_fragment(
  self : NumberingContext,
) -> Unit raise @failure.Failure {
  guard self.tree.nodes[0].attributes.is_empty() &&
    self.tree.nodes[0].text.trim().is_empty() &&
    self.tree.children[0].all(id => {
      self.tree.nodes[id].uri == word_uri &&
      ["abstractNum", "num"].contains(self.tree.nodes[id].name)
    }) else {
    @failure.reject("protected-content", "Unsupported copied numbering root")
  }
  let used : Map[Int32, Bool] = Map([])
  for instance in self.instances.keys() {
    guard instance > 0 else {
      @failure.reject(
        "invalid-numbering", "Copied numbering instances must be positive",
      )
    }
    let definition = self.definition(instance)
    used[definition.abstract_id] = true
    for level in definition.levels.values() {
      if self.tree.child(level.node, "pPr") is Some(p) {
        guard self.tree.children[p].all(id => {
          !["pStyle", "numPr"].contains(self.tree.nodes[id].name)
        }) else {
          @failure.reject(
            "protected-content", "Copied numbering has external paragraph references",
          )
        }
      }
    }
  }
  guard used.length() == self.abstracts.length() else {
    @failure.reject(
      "invalid-numbering", "Copied numbering contains unused definitions",
    )
  }
  for id in self.tree.order {
    let node = self.tree.nodes[id]
    guard node.uri == word_uri &&
      !["pStyle", "rStyle", "numPr"].contains(node.name) &&
      !node.attributes.any(a => {
        a.name.has_suffix("Theme") ||
        a.name.has_prefix("theme") ||
        a.name == "cstheme"
      }) else {
      @failure.reject(
        "protected-content", "Copied numbering contains unresolved resources",
      )
    }
    if ["nsid", "multiLevelType", "tmpl", "name"].contains(node.name) {
      self.tree.numbering_shape(id, ["val"], [])
    }
  }
}

///|
fn Session::fragment_numbering(
  self : Session,
  tree : WordTree,
  grid : TableGrid,
  top : Int32,
  bottom : Int32,
  left : Int32,
  right : Int32,
  styles : Styles,
  limit : Int32,
) -> (String, Map[Int32, (Int32, Int32)]) raise @failure.Failure {
  let selected = []
  for row in top..<bottom {
    for column, cell in grid.cells[row] {
      let start = grid.starts[row][column]
      if start >= left && start < right {
        selected.append(tree.table_children(cell, "p"))
      }
    }
  }
  self.fragment_paragraph_numbering(tree, selected, styles, limit)
}

///|
fn Session::fragment_paragraph_numbering(
  self : Session,
  tree : WordTree,
  selected : Array[Int32],
  styles : Styles,
  limit : Int32,
) -> (String, Map[Int32, (Int32, Int32)]) raise @failure.Failure {
  let instances : Map[Int32, Bool] = Map([])
  let paragraphs : Map[Int32, (Int32, Int32)] = Map([])
  for p in selected {
    if styles.numbering_reference(tree, p) is Some((instance, level)) {
      instances[instance] = true
      paragraphs[p] = (instance, level)
    }
  }
  if instances.is_empty() {
    return ("", Map([]))
  }
  let context = self.numbering_context()
  let abstracts : Map[Int32, Bool] = Map([])
  let changes : Array[@xml.SourceChange] = []
  for instance in instances.keys() {
    abstracts[context.definition(instance).abstract_id] = true
  }
  let variants : Map[(Int32, Bool), Int32] = Map([])
  let first : Map[Int32, Int32] = Map([])
  let copied : Map[Int32, (Int32, Int32)] = Map([])
  let mut sequence = 1
  for p in tree.order {
    guard paragraphs.get(p) is Some((instance, level)) else { continue }
    let underline = styles.character_style(tree, p, None, []).underline
    let key = (instance, underline)
    let id = variants
      .get(key)
      .unwrap_or_else(() => {
        guard variants.length() < 4096 else {
          @failure.reject(
            "limit-exceeded", "Copied numbering variants exceed budget",
          )
        }
        let id = if !first.contains(instance) {
          first[instance] = instance
          instance
        } else {
          while sequence < 65536 && context.instances.contains(sequence) {
            sequence += 1
          }
          guard sequence < 65536 else {
            @failure.reject(
              "limit-exceeded", "Copied numbering identities exhausted",
            )
          }
          let id = sequence
          sequence += 1
          id
        }
        variants[key] = id
        id
      })
    copied[p] = (id, level)
  }
  for id in context.tree.order {
    let node = context.tree.nodes[id]
    if node.name != "lvl" {
      continue
    }
    let mut owner = node
    while owner.parent > 0 {
      owner = context.tree.nodes[owner.parent]
    }
    let included = if owner.name == "abstractNum" {
      abstracts.contains(
        numbering_integer(
          owner.attribute("abstractNumId", uri=word_uri).unwrap(),
          2147483646,
        ),
      )
    } else if owner.name == "num" {
      instances.contains(
        numbering_integer(
          owner.attribute("numId", uri=word_uri).unwrap(),
          2147483646,
        ),
      )
    } else {
      false
    }
    if !included {
      continue
    }
    let parent = node
    let id = context.tree.child(node.id, "rPr")
    let patch : Map[String, Map[String, String?]?] = Map([])
    if id.bind(id => context.tree.child(id, "rFonts")) is Some(font) {
      let values : Map[String, String?] = Map([])
      for
        (slot, theme) in [
          ("ascii", "asciiTheme"),
          ("hAnsi", "hAnsiTheme"),
          ("eastAsia", "eastAsiaTheme"),
          ("cs", "cstheme"),
        ] {
        if context.tree.nodes[font].attribute(theme, uri=word_uri)
          is Some(value) {
          values[slot] = Some(
            font_family(
              Map([(slot, (value, true))]),
              slot,
              styles.defaults.family,
              styles.themes,
            ),
          )
          values[theme] = None
        }
      }
      if !values.is_empty() {
        patch["rFonts"] = Some(values)
      }
    }
    if id.bind(id => context.tree.child(id, "color")) is Some(color) &&
      context.tree.nodes[color].attribute("themeColor", uri=word_uri) is Some(_) {
      let resolved = theme_text_color(
        context.tree,
        id.unwrap(),
        styles.defaults.color,
        styles.themes,
      )
      patch["color"] = Some(
        Map([
          ("val", Some(resolved)),
          ("themeColor", None),
          ("themeTint", None),
          ("themeShade", None),
        ]),
      )
    }
    if !patch.is_empty() {
      let markup = formatted_properties(
        context.tree,
        context.document,
        parent.id,
        "rPr",
        patch,
      )
      if properties_change(
          context.tree,
          context.document,
          parent.id,
          "rPr",
          markup,
        )
        is Some(change) {
        changes.push(change)
      }
    }
  }
  let numbers = if changes.is_empty() {
    context.document
  } else {
    context.document.edit_source(changes).0
  }
  let source = WordTree::new(numbers)
  let output = StringBuilder()
  output.write_string("<od:numbering xmlns:od=\"\{word_uri}\">")
  let mut units = 64
  for id in context.tree.children[0] {
    let node = context.tree.nodes[id]
    let included = node.name == "abstractNum" &&
      abstracts.contains(
        numbering_integer(
          node.attribute("abstractNumId", uri=word_uri).unwrap(),
          2147483646,
        ),
      )
    if included {
      let markup = source.standalone_markup(numbers, id)
      guard markup.length() <= limit - units else {
        @failure.reject(
          "limit-exceeded", "Copied numbering exceeds source budget",
        )
      }
      units += markup.length()
      output.write_string(markup)
    }
  }
  for (original, underline), id in variants {
    let markup = context.fragment_instance(
      numbers,
      source,
      original,
      id,
      underline,
      first[original] == id,
      limit,
    )
    guard markup.length() <= limit - units else {
      @failure.reject(
        "limit-exceeded", "Copied numbering exceeds source budget",
      )
    }
    units += markup.length()
    output.write_string(markup)
  }
  output.write_string("</od:numbering>")
  let document = fragment_numbering_document(output.to_string(), limit)
  NumberingContext::new(document, "table-numbering").check_fragment()
  (
    "<odClip:numbering xmlns:odClip=\"\{table_fragment_uri}\">" +
    output.to_string() +
    "</odClip:numbering>",
    copied,
  )
}

///|
fn Session::import_fragment_numbering(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  let wrappers = tree.order.filter(id => {
    tree.nodes[id].uri == table_fragment_uri &&
    tree.nodes[id].name == "numbering"
  })
  if wrappers.is_empty() {
    guard tree.order.all(id => {
      tree.nodes[id].uri != word_uri ||
      tree.nodes[id].name != "numId" ||
      tree.nodes[id].attribute("val", uri=word_uri) == Some("0")
    }) else {
      @failure.reject(
        "protected-content", "Rich list references require copied numbering",
      )
    }
    return document
  }
  guard wrappers.length() == 1 else {
    @failure.reject("invalid-numbering", "Duplicate copied numbering")
  }
  let wrapper = tree.nodes[wrappers[0]]
  guard tree.nodes[wrapper.parent].uri == word_uri &&
    ["tbl", "body"].contains(tree.nodes[wrapper.parent].name) &&
    wrapper.attributes.is_empty() &&
    wrapper.text.trim().is_empty() &&
    tree.children[wrapper.id].length() == 1 else {
    @failure.reject("protected-content", "Invalid copied numbering owner")
  }
  let root = tree.children[wrapper.id][0]
  let limit = self.opc.budget.entry_bytes.min(history_byte_limit / 2)
  let incoming = fragment_numbering_document(
    tree.standalone_markup(document, root),
    limit,
  )
  let numbers = NumberingContext::new(incoming, "table-numbering")
  numbers.check_fragment()
  let references : Map[Int32, Int32] = Map([])
  let abstracts : Map[Int32, Int32] = Map([])
  let used_num : Map[Int32, Bool] = Map([])
  let used_abstract : Map[Int32, Bool] = Map([])
  for part in self.style_part_names() {
    for node in self.part_xml(part).nodes() {
      if node.uri != word_uri {
        continue
      }
      for
        (name, used) in [("numId", used_num), ("abstractNumId", used_abstract)] {
        let value = if node.name == name {
          node.attribute("val", uri=word_uri)
        } else {
          node.attribute(name, uri=word_uri)
        }
        if value is Some(value) {
          let id = @string.parse_int(value) catch { _ => continue }
          if id >= 0 {
            used[id] = true
          }
        }
      }
    }
  }
  for
    (source, used, mapping, minimum) in [
      (numbers.instances, used_num, references, 1),
      (numbers.abstracts, used_abstract, abstracts, 0),
    ] {
    let mut sequence = minimum
    for id in source.keys() {
      while sequence < 65536 && used.contains(sequence) {
        sequence += 1
      }
      guard sequence < 65536 else {
        @failure.reject(
          "limit-exceeded", "Copied numbering identities exhausted",
        )
      }
      mapping[id] = sequence
      used[sequence] = true
      sequence += 1
    }
  }
  let body_changes : Array[@xml.SourceChange] = []
  let used : Map[Int32, Bool] = Map([])
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri || node.name != "numPr" {
      continue
    }
    tree.numbering_shape(id, [], ["numId", "ilvl"])
    let instance = numbering_integer(
      tree.numbering_value(id, "numId").unwrap_or("-1"),
      2147483646,
    )
    if instance == 0 {
      continue
    }
    let level = numbering_integer(
      tree.numbering_value(id, "ilvl").unwrap_or("0"),
      8,
    )
    ignore(numbers.level(instance, level))
    used[instance] = true
    body_changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: list_properties(references[instance], level),
    })
  }
  guard used.length() == numbers.instances.length() && !used.is_empty() else {
    @failure.reject(
      "invalid-numbering", "Copied numbering requires matching paragraph references",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for id in numbers.tree.order {
    let node = numbers.tree.nodes[id]
    for attribute in node.attributes {
      let mapping = if attribute.name == "numId" {
        Some(references)
      } else if attribute.name == "abstractNumId" ||
        (node.name == "abstractNumId" && attribute.name == "val") {
        Some(abstracts)
      } else {
        None
      }
      if mapping is Some(mapping) {
        let old = numbering_integer(attribute.value, 2147483646)
        changes.push({
          node: id,
          offset: attribute.start - node.start,
          length: attribute.end - attribute.start,
          xml: mapping[old].to_string(),
        })
      }
    }
  }
  let remapped = incoming.edit_source(changes).0
  let source = WordTree::new(remapped)
  let markup = source.children[0]
    .map(id => source.standalone_markup(remapped, id))
    .join("")
  let links = self
    .relationships()
    .filter(rel => {
      rel.owner == self.main &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"
    })
  let part = if links.is_empty() {
    self.new_word_part("numbering", parts, edits, created)
  } else {
    self.numbering_context().part
  }
  let original = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let (next, edit) = append_part_xml(original, markup)
  let context = NumberingContext::new(next, part)
  for id in references.values() {
    ignore(context.definition(id))
  }
  guard next.source().length() <= limit else {
    @failure.reject("limit-exceeded", "Numbering part exceeds source budget")
  }
  parts[part] = next
  if created.contains(part) {
    created[part] = next
  } else {
    edits.get_or_init(part, () => []).push(edit)
  }
  body_changes.push({
    node: wrapper.parent,
    offset: wrapper.start - tree.nodes[wrapper.parent].start,
    length: wrapper.end - wrapper.start,
    xml: "",
  })
  document.edit_source(body_changes).0
}
