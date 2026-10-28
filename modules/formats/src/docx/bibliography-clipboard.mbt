///|
fn citation_source_payload(
  tree : WordTree,
  document : @xml.Document,
  record : SourceRecord,
) -> String raise @failure.Failure {
  let uri = tree.nodes[record.node].uri
  "<odBib:Sources xmlns:odBib=\"\{uri}\">" +
  tree.standalone_markup(document, record.node) +
  "</odBib:Sources>"
}

///|
fn citation_source_signature(
  document : @xml.Document,
  record : SourceRecord,
) -> String raise @failure.Failure {
  let tree = WordTree::new(document)
  let tag = source_children(tree, record.node, "Tag")[0]
  let (normalized, _) = document.edit_text(
    Map::from_array([(tag, "odCitation")]),
  )
  WordTree::new(normalized).standalone_markup(normalized, record.node)
}

///|
fn Session::fragment_citation_sources(
  self : Session,
  xml : String,
  limit : Int32,
) -> String raise @failure.Failure {
  let document = @xml.Document::parse(
    @utf8.encode(
      "<od:document xmlns:od=\"\{word_uri}\">" + xml + "</od:document>",
    ),
    "citation-clipboard",
    self.opc.budget.xml_depth,
    self.opc.budget.entry_bytes,
  )
  let tree = WordTree::new(document)
  let fields = tree.order.filter(id => {
    tree.nodes[id].uri == word_uri &&
    tree.nodes[id].name == "fldSimple" &&
    tree.nodes[id]
    .attribute("instr", uri=word_uri)
    .unwrap_or("")
    .trim()
    .to_upper()
    .has_prefix("CITATION")
  })
  if fields.is_empty() {
    return xml
  }
  guard fields.length() <= 4096 &&
    self.bibliography_part() is Some((_, sources)) else {
    @failure.reject(
      "protected-content", "Rich citations require their document sources",
    )
  }
  let source_tree = WordTree::new(sources)
  let records = read_bibliography_sources(source_tree)
  let encoded : Map[String, String] = Map([])
  let changes : Array[@xml.SourceChange] = []
  let mut units = xml.length()
  for id in fields {
    let node = tree.nodes[id]
    let tag = citation_code(node.attribute("instr", uri=word_uri).unwrap())[9:].to_owned()
    let payload = match encoded.get(tag) {
      Some(value) => value
      None => {
        guard records.iter().find_first(record => record.value.tag == tag)
          is Some(record) &&
          record.reason.is_empty() else {
          @failure.reject(
            "protected-content", "Rich citations require a supported source record",
          )
        }
        guard source_tree
          .descendants(record.node)
          .all(id => {
            source_tree.nodes[id].uri == source_tree.nodes[record.node].uri &&
            source_tree.nodes[id].attributes.all(a => {
              a.uri.is_empty() ||
              a.uri == source_tree.nodes[record.node].uri ||
              (
                a.uri == "http://www.w3.org/XML/1998/namespace" &&
                a.name == "space"
              )
            })
          }) else {
          @failure.reject(
            "protected-content", "Foreign source extensions require resource transfer support",
          )
        }
        let value = @base64.encode(
          @utf8.encode(citation_source_payload(source_tree, sources, record)),
        )
        encoded[tag] = value
        value
      }
    }
    let attributes = " xmlns:odClip=\"\{table_fragment_uri}\" odClip:citationSource=\"\{payload}\""
    units += attributes.length()
    guard units <= limit else {
      @failure.reject(
        "limit-exceeded", "Citation sources exceed clipboard budget",
      )
    }
    changes.push({
      node: id,
      offset: node.opening_end - node.start - 1,
      length: 0,
      xml: attributes,
    })
  }
  let (candidate, _) = document.edit_source(changes)
  let root = candidate.nodes()[0]
  candidate.source()[root.opening_end:root.closing_start].to_owned()
}

///|
fn Session::import_fragment_citations(
  self : Session,
  document : @xml.Document,
  parts : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
  created : Map[String, @xml.Document],
) -> @xml.Document raise @failure.Failure {
  let tree = WordTree::new(document)
  let fields : Array[Int32] = []
  for id in tree.order {
    let node = tree.nodes[id]
    let metadata = node.attribute("citationSource", uri=table_fragment_uri)
    if metadata is Some(_) {
      guard node.uri == word_uri && node.name == "fldSimple" else {
        @failure.reject(
          "protected-content", "Invalid copied citation source owner",
        )
      }
    }
    if node.uri == word_uri &&
      node.name == "fldSimple" &&
      (
        metadata is Some(_) ||
        node
        .attribute("instr", uri=word_uri)
        .unwrap_or("")
        .trim()
        .to_upper()
        .has_prefix("CITATION")
      ) {
      fields.push(id)
    }
  }
  if fields.is_empty() {
    return document
  }
  guard fields.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Too many copied citations")
  }
  let existing = { ..self, parts, }.bibliography_part()
  let mut source_part = existing.map(pair => pair.0)
  let mut uri = existing.map(pair => pair.1.nodes()[0].uri).unwrap_or("")
  let signatures : Map[String, String] = Map([])
  let guids : Map[String, String] = Map([])
  let tags : Set[String] = Set([])
  if existing is Some((_, source)) {
    let source_tree = WordTree::new(source)
    for record in read_bibliography_sources(source_tree) {
      tags.add(record.value.tag)
      let payload = @xml.Document::parse(
        @utf8.encode(citation_source_payload(source_tree, source, record)),
        "existing-citation-source",
        self.opc.budget.xml_depth,
        self.opc.budget.entry_bytes,
      )
      let record = read_bibliography_sources(WordTree::new(payload))[0]
      let signature = citation_source_signature(payload, record)
      if !signatures.contains(signature) {
        signatures[signature] = record.value.tag
      }
      let guid = source_leaf(WordTree::new(payload), record.node, "Guid", 128).to_upper()
      if !guid.is_empty() {
        guids[guid] = if guids
          .get(guid)
          .map(old => old != signature)
          .unwrap_or(false) {
          ""
        } else {
          signature
        }
      }
    }
  }
  let changes : Array[@xml.SourceChange] = []
  let mut next = 1
  for id in fields {
    let node = tree.nodes[id]
    guard !node.empty &&
      node.text.trim().is_empty() &&
      tree.nodes[node.parent].uri == word_uri &&
      tree.nodes[node.parent].name == "p" &&
      node.attribute("citationSource", uri=table_fragment_uri) is Some(encoded) &&
      node.attributes.all(a => {
        (a.uri == word_uri && ["instr", "dirty", "fldLock"].contains(a.name)) ||
        (a.uri == table_fragment_uri && a.name == "citationSource")
      }) else {
      @failure.reject(
        "protected-content", "Copied citations require their complete source record",
      )
    }
    let code = citation_code(
      node.attribute("instr", uri=word_uri).unwrap_or(""),
    )
    let bytes = @base64.decode(encoded) catch {
      _ =>
        @failure.reject(
          "invalid-operation", "Invalid copied citation source encoding",
        )
    }
    let payload = @xml.Document::parse(
      bytes,
      "copied-citation-source",
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    let source_tree = WordTree::new(payload)
    let records = read_bibliography_sources(source_tree)
    guard payload.nodes()[0].attributes.is_empty() &&
      records is [record] &&
      record.reason.is_empty() &&
      record.value.tag == code[9:].to_owned() &&
      source_tree
      .descendants(record.node)
      .all(id => {
        source_tree.nodes[id].uri == source_tree.nodes[record.node].uri &&
        source_tree.nodes[id].attributes.all(a => {
          a.uri.is_empty() ||
          a.uri == source_tree.nodes[record.node].uri ||
          (a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space")
        })
      }) else {
      @failure.reject(
        "protected-content", "Invalid or extended copied citation source",
      )
    }
    let incoming_uri = payload.nodes()[0].uri
    // shortcut: mixed bibliography namespaces stay protected until namespace-aware source transfer is needed.
    guard uri.is_empty() || uri == incoming_uri else {
      @failure.reject(
        "protected-content", "Mixed bibliography namespaces require source conversion",
      )
    }
    if uri.is_empty() {
      uri = incoming_uri
    }
    let signature = citation_source_signature(payload, record)
    let tag = match signatures.get(signature) {
      Some(tag) => tag
      None => {
        let guid = source_leaf(source_tree, record.node, "Guid", 128).to_upper()
        guard guid.is_empty() ||
          !guids.contains(guid) ||
          guids[guid] == signature else {
          @failure.reject(
            "protected-content", "Conflicting source versions require an explicit source choice",
          )
        }
        guard tags.length() < 512 else {
          @failure.reject(
            "limit-exceeded", "Copied sources exceed the document source limit",
          )
        }
        let tag = if !tags.contains(record.value.tag) {
          record.value.tag
        } else {
          while next <= 65536 && tags.contains("odCitation" + next.to_string()) {
            next += 1
          }
          guard next <= 65536 else {
            @failure.reject(
              "limit-exceeded", "Citation source identities exhausted",
            )
          }
          let candidate = "odCitation" + next.to_string()
          next += 1
          candidate
        }
        tags.add(tag)
        signatures[signature] = tag
        if !guid.is_empty() {
          guids[guid] = signature
        }
        let source = if tag == record.value.tag {
          payload
        } else {
          payload.edit_text(
            Map::from_array([
              (source_children(source_tree, record.node, "Tag")[0], tag),
            ]),
          ).0
        }
        let markup = WordTree::new(source).standalone_markup(
          source,
          record.node,
        )
        let part = match source_part {
          Some(part) => part
          None => {
            let (part, _) = self.create_source_part(parts, edits, created, uri~)
            source_part = Some(part)
            part
          }
        }
        let original = parts.get(part).unwrap_or_else(() => self.part_xml(part))
        let (updated, step) = append_part_xml(original, markup)
        ignore(read_bibliography_sources(WordTree::new(updated)))
        parts[part] = updated
        if created.contains(part) {
          created[part] = updated
        } else {
          edits.get_or_init(part, () => []).push(step)
        }
        tag
      }
    }
    let bindings = tree.namespace_bindings(id)
    let prefix = bindings
      .keys()
      .find_first(prefix => !prefix.is_empty() && bindings[prefix] == word_uri)
      .unwrap()
    let namespaces = node.namespaces
      .filter(pair => pair.1 != table_fragment_uri)
      .map(pair => {
        " " +
        (if pair.0.is_empty() { "xmlns" } else { "xmlns:" + pair.0 }) +
        "=\"" +
        property_attribute(pair.1) +
        "\""
      })
      .join("")
    let attributes = node.attributes
      .filter(a => a.uri == word_uri && a.name != "instr")
      .map(a => {
        " " + prefix + ":" + a.name + "=\"" + property_attribute(a.value) + "\""
      })
      .join("")
    let opening = "<" +
      node.qualified +
      namespaces +
      attributes +
      " " +
      prefix +
      ":instr=\"" +
      property_attribute(running_field_instruction("CITATION:" + tag)) +
      "\">"
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.opening_end - node.start,
      xml: opening,
    })
  }
  document.edit_source(changes).0
}
