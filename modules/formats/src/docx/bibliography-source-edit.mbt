///|
fn source_element(
  uri : String,
  name : String,
  value : String,
) -> String raise @failure.Failure {
  "<b:\{name} xmlns:b=\"\{uri}\">\{@xml.escape_text(value)}</b:\{name}>"
}

///|
fn source_author_markup(
  uri : String,
  author : String,
  corporate : Bool,
) -> String raise @failure.Failure {
  if corporate {
    return "<b:Author xmlns:b=\"\{uri}\">" +
      source_element(uri, "Corporate", author) +
      "</b:Author>"
  }
  let comma = author.find(",")
  let last = comma
    .map(index => author[:index].trim().to_owned())
    .unwrap_or(author)
  let first = comma
    .map(index => author[index + 1:].trim().to_owned())
    .unwrap_or("")
  "<b:Author xmlns:b=\"\{uri}\"><b:NameList><b:Person>" +
  source_element(uri, "Last", last) +
  source_element(uri, "First", first) +
  "</b:Person></b:NameList></b:Author>"
}

///|
fn source_publisher_key(kind : String) -> String {
  if kind == "JournalArticle" {
    "JournalName"
  } else if kind == "InternetSite" {
    "InternetSiteTitle"
  } else {
    "Publisher"
  }
}

///|
fn source_markup(
  uri : String,
  value : BibliographySource,
) -> String raise @failure.Failure {
  let author = if value.author.is_empty() {
    ""
  } else {
    "<b:Author xmlns:b=\"\{uri}\">" +
    source_author_markup(uri, value.author, false) +
    "</b:Author>"
  }
  "<b:Source xmlns:b=\"\{uri}\">" +
  source_element(uri, "Tag", value.tag) +
  source_element(uri, "SourceType", value.kind) +
  author +
  source_element(uri, "Title", value.title) +
  source_element(uri, "Year", value.year) +
  source_element(uri, source_publisher_key(value.kind), value.publisher) +
  source_element(uri, "URL", value.url) +
  "</b:Source>"
}

///|
fn source_changes(
  tree : WordTree,
  old : SourceRecord,
  value : BibliographySource,
) -> (Map[Int, String], Array[@xml.SourceChange]) raise @failure.Failure {
  let text : Map[Int, String] = Map([])
  let changes : Array[@xml.SourceChange] = []
  let uri = tree.nodes[old.node].uri
  let missing = StringBuilder()
  for
    (key, before, after) in [
      ("SourceType", old.value.kind, value.kind),
      ("Title", old.value.title, value.title),
      ("Year", old.value.year, value.year),
      (
        source_publisher_key(value.kind),
        if value.kind == old.value.kind {
          old.value.publisher
        } else {
          source_leaf(tree, old.node, source_publisher_key(value.kind), 512)
        },
        value.publisher,
      ),
      ("URL", old.value.url, value.url),
    ] {
    if before == after {
      continue
    }
    if source_children(tree, old.node, key).get(0) is Some(id) {
      text[id] = after
    } else {
      missing.write_string(source_element(uri, key, after))
    }
  }
  if old.value.author != value.author {
    guard old.author_reason.is_empty() else {
      @failure.reject("protected-content", old.author_reason)
    }
    let outer = source_children(tree, old.node, "Author").get(0)
    let inner = outer.bind(id => source_children(tree, id, "Author").get(0))
    let corporate = inner
      .map(id => !source_children(tree, id, "Corporate").is_empty())
      .unwrap_or(false)
    let markup = source_author_markup(uri, value.author, corporate)
    if inner is Some(id) {
      let node = tree.nodes[id]
      changes.push({
        node: node.parent,
        offset: node.start - tree.nodes[node.parent].start,
        length: node.end - node.start,
        xml: markup,
      })
    } else if outer is Some(id) {
      let node = tree.nodes[id]
      if node.empty {
        changes.push({
          node: id,
          offset: node.opening_end - node.start - 2,
          length: 2,
          xml: ">" + markup + "</" + node.qualified + ">",
        })
      } else {
        changes.push({
          node: id,
          offset: node.closing_start - node.start,
          length: 0,
          xml: markup,
        })
      }
    } else {
      missing.write_string(
        "<b:Author xmlns:b=\"\{uri}\">" + markup + "</b:Author>",
      )
    }
  }
  let missing = missing.to_string()
  if !missing.is_empty() {
    let node = tree.nodes[old.node]
    changes.push({
      node: old.node,
      offset: node.closing_start - node.start,
      length: 0,
      xml: missing,
    })
  }
  (text, changes)
}

///|
/// Edits native source data in one package/history transaction, preserving other entries and metadata.
pub fn Session::edit_bibliography_source(
  self : Session,
  revision : Int,
  change : BibliographyEdit,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_document_protection()
  let source = self.bibliography_part()
  let records = source
    .map(pair => read_bibliography_sources(WordTree::new(pair.1)))
    .unwrap_or([])
  let tag = match change {
    CreateSource(value) | UpdateSource(value) => {
      check_bibliography_source(value)
      value.tag
    }
    DeleteSource(tag) => {
      check_source_tag(tag)
      tag
    }
  }
  let old = records.iter().find_first(record => record.value.tag == tag)
  match change {
    CreateSource(_) => {
      guard old is None && records.length() < 512 else {
        @failure.reject(
          "invalid-operation", "Source tag already exists or source limit reached",
        )
      }
    }
    UpdateSource(value) => {
      guard old is Some(record) && record.reason.is_empty() else {
        @failure.reject("protected-content", "Select one supported source")
      }
      if record.value == value {
        return self.edit_state()
      }
    }
    DeleteSource(_) => {
      guard old is Some(record) && record.reason.is_empty() else {
        @failure.reject("protected-content", "Select one supported source")
      }
      let references = self.source_references()
      guard !references.contains(tag) && !references.contains("") else {
        @failure.reject(
          "protected-content", "This source is cited in the document",
        )
      }
    }
  }
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let (part, original) = source.unwrap_or_else(() => {
    self.create_source_part(parts, edits, created)
  })
  let tree = WordTree::new(original)
  let (candidate, step) = match change {
    CreateSource(value) =>
      append_part_xml(
        original,
        source_markup(tree.nodes[tree.order[0]].uri, value),
      )
    UpdateSource(value) => {
      let (text, changes) = source_changes(tree, old.unwrap(), value)
      original.edit_text(text, source=changes)
    }
    DeleteSource(_) => {
      let node = tree.nodes[old.unwrap().node]
      original.edit_source([
        {
          node: node.parent,
          offset: node.start - tree.nodes[node.parent].start,
          length: node.end - node.start,
          xml: "",
        },
      ])
    }
  }
  ignore(read_bibliography_sources(WordTree::new(candidate)))
  parts[part] = candidate
  if created.contains(part) {
    created[part] = candidate
  } else {
    edits.get_or_init(part, () => []).push(step)
  }
  let bytes = xml_part_edit_bytes(edits, created)
  let typing = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [],
      bytes,
    },
    self.document(),
    parts~,
  )
  self.typing_format = typing
  self.edit_result([])
}
