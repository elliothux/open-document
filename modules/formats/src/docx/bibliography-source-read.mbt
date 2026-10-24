///|
let bibliography_uri = "http://schemas.openxmlformats.org/officeDocument/2006/bibliography"

///|
let bibliography_legacy_uri = "http://schemas.microsoft.com/office/word/2004/10/bibliography"

///|
let custom_xml_relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml"

///|
pub(all) struct BibliographySource {
  tag : String
  kind : String
  author : String
  title : String
  year : String
  publisher : String
  url : String
} derive(Eq, ToJson)

///|
pub extend BibliographySource with Eq::{equal, not_equal}

///|
pub extend BibliographySource with ToJson::{to_json}

///|
pub(all) enum BibliographyEdit {
  CreateSource(BibliographySource)
  UpdateSource(BibliographySource)
  DeleteSource(String)
}

///|
priv struct SourceRecord {
  node : Int
  value : BibliographySource
  reason : String
  author_reason : String
}

///|
fn source_text(value : String, limit : Int) -> Bool {
  value.length() <= limit &&
  @xml.valid_text(value) &&
  value
  .iter()
  .all(c => {
    c >= ' ' &&
    !(c >= '\u007f' && c <= '\u009f') &&
    c != '\u2028' &&
    c != '\u2029'
  })
}

///|
fn check_source_tag(tag : String) -> Unit raise @failure.Failure {
  guard !tag.is_empty() &&
    tag.trim() == tag &&
    source_text(tag, 64) &&
    !tag.contains("\"") &&
    !tag.contains("\\") else {
    @failure.reject(
      "invalid-operation", "Source tags require 1-64 plain characters without quotes or backslashes",
    )
  }
}

///|
fn check_bibliography_source(
  value : BibliographySource,
) -> Unit raise @failure.Failure {
  check_source_tag(value.tag)
  guard ["Book", "JournalArticle", "InternetSite", "Report", "Misc"].contains(
      value.kind,
    ) &&
    !value.title.trim().is_empty() &&
    source_text(value.title, 1024) &&
    source_text(value.author, 1024) &&
    source_text(value.year, 32) &&
    source_text(value.publisher, 512) &&
    source_text(value.url, 2048) else {
    @failure.reject("invalid-operation", "Invalid bibliography source fields")
  }
}

///|
fn source_children(tree : WordTree, parent : Int, name : String) -> Array[Int] {
  tree.children[parent].filter(id => {
    tree.nodes[id].uri == tree.nodes[tree.order[0]].uri &&
    tree.nodes[id].name == name
  })
}

///|
fn source_leaf(
  tree : WordTree,
  parent : Int,
  name : String,
  limit : Int,
) -> String raise @failure.Failure {
  let nodes = source_children(tree, parent, name)
  guard nodes.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate source property: " + name)
  }
  guard nodes.get(0) is Some(id) else { return "" }
  let node = tree.nodes[id]
  let raw = tree.source[node.start:node.end]
  guard tree.children[id].is_empty() &&
    !raw.contains("<!--") &&
    !raw.contains("<?") else {
    @failure.reject("protected-content", "Extended source property: " + name)
  }
  guard source_text(node.text, limit) else {
    @failure.reject(
      "limit-exceeded",
      "Source property exceeds text budget: " + name,
    )
  }
  node.text
}

///|
fn source_author(tree : WordTree, parent : Int) -> (String, String) {
  let output = StringBuilder()
  let reason = try {
    let roots = source_children(tree, parent, "Author")
    guard roots.length() <= 1 else {
      @failure.reject("protected-content", "Ambiguous source author lists")
    }
    if roots.get(0) is Some(root) {
      let authors = source_children(tree, root, "Author")
      guard authors.length() <= 1 else {
        @failure.reject("protected-content", "Ambiguous source authors")
      }
      if authors.get(0) is Some(author) {
        let corporate = source_children(tree, author, "Corporate")
        let lists = source_children(tree, author, "NameList")
        guard corporate.length() + lists.length() <= 1 else {
          @failure.reject("protected-content", "Mixed source author kinds")
        }
        if !corporate.is_empty() {
          output.write_string(source_leaf(tree, author, "Corporate", 1024))
        }
        if lists.get(0) is Some(list) {
          let people = source_children(tree, list, "Person")
          guard people.length() <= 64 else {
            @failure.reject("limit-exceeded", "Too many source authors")
          }
          let mut extended = tree.children[list].length() != people.length() ||
            people.length() > 1
          for index, person in people {
            let last = source_leaf(tree, person, "Last", 512)
            let first = source_leaf(tree, person, "First", 512)
            let middle = source_leaf(tree, person, "Middle", 512)
            if index > 0 {
              output.write_string("; ")
            }
            output.write_string(last)
            let given = [first, middle]
              .filter(text => !text.is_empty())
              .join(" ")
            if !given.is_empty() {
              output.write_string(
                (if last.is_empty() { "" } else { ", " }) + given,
              )
            }
            extended = extended ||
              !middle.is_empty() ||
              tree.children[person].any(id => {
                !["Last", "First"].contains(tree.nodes[id].name) ||
                tree.nodes[id].uri != tree.nodes[author].uri
              })
          }
          guard !extended else {
            @failure.reject(
              "protected-content", "Multiple or extended author names are retained as source data",
            )
          }
        }
        guard tree.children[author].all(id => {
          ["Corporate", "NameList"].contains(tree.nodes[id].name) &&
          tree.nodes[id].uri == tree.nodes[author].uri
        }) else {
          @failure.reject(
            "protected-content", "Extended source author data is retained",
          )
        }
        let node = tree.nodes[author]
        let raw = tree.source[node.start:node.end]
        guard !raw.contains("<!--") &&
          !raw.contains("<?") &&
          tree
          .descendants(author)
          .all(id => {
            let child = tree.nodes[id]
            child.attributes.is_empty() &&
            (
              !["Author", "NameList", "Person"].contains(child.name) ||
              child.text.trim().is_empty()
            )
          }) else {
          @failure.reject(
            "protected-content", "Annotated source author data is retained",
          )
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
  (output.to_string(), reason)
}

///|
fn read_bibliography_sources(
  tree : WordTree,
) -> Array[SourceRecord] raise @failure.Failure {
  let root = tree.nodes[tree.order[0]]
  guard root.name == "Sources" &&
    [bibliography_uri, bibliography_legacy_uri].contains(root.uri) &&
    root.text.trim().is_empty() &&
    tree.children[root.id].all(id => {
      tree.nodes[id].uri == root.uri && tree.nodes[id].name == "Source"
    }) else {
    @failure.reject(
      "protected-content", "Unsupported bibliography sources root",
    )
  }
  guard tree.order.length() <= 32768 && tree.children[root.id].length() <= 512 else {
    @failure.reject("limit-exceeded", "Bibliography sources exceed budget")
  }
  let tags : Set[String] = Set([])
  let records : Array[SourceRecord] = []
  for id in tree.children[root.id] {
    let tag = source_leaf(tree, id, "Tag", 64)
    check_source_tag(tag)
    guard !tags.contains(tag) else {
      @failure.reject("protected-content", "Duplicate bibliography source tags")
    }
    tags.add(tag)
    let (author, author_reason) = source_author(tree, id)
    guard source_text(author, 1024) else {
      @failure.reject("limit-exceeded", "Source author display exceeds budget")
    }
    let mut value : BibliographySource = {
      tag,
      kind: "Misc",
      author,
      title: "",
      year: "",
      publisher: "",
      url: "",
    }
    let reason = try {
      let kind = source_leaf(tree, id, "SourceType", 64)
      let kind = if kind.is_empty() { "Misc" } else { kind }
      value = {
        ..value,
        kind,
        title: source_leaf(tree, id, "Title", 1024),
        year: source_leaf(tree, id, "Year", 32),
        publisher: source_leaf(
          tree,
          id,
          if kind == "JournalArticle" {
            "JournalName"
          } else if kind == "InternetSite" {
            "InternetSiteTitle"
          } else {
            "Publisher"
          },
          512,
        ),
        url: source_leaf(tree, id, "URL", 2048),
      }
      guard ["Book", "JournalArticle", "InternetSite", "Report", "Misc"].contains(
        kind,
      ) else {
        @failure.reject(
          "protected-content", "This source type requires editing support",
        )
      }
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    records.push({ node: id, value, reason, author_reason, })
  }
  records
}

///|
fn Session::bibliography_part(
  self : Session,
) -> (String, @xml.Document)? raise @failure.Failure {
  let links = self
    .relationships()
    .filter(link => {
      link.owner == self.main && link.kind == custom_xml_relationship
    })
  guard links.length() <= 64 else {
    @failure.reject("limit-exceeded", "Too many custom XML parts")
  }
  let mut result = None
  for link in links {
    guard !link.external else { continue }
    let document = self.part_xml(link.target)
    let root = document.nodes()[0]
    if root.name != "Sources" ||
      ![bibliography_uri, bibliography_legacy_uri].contains(root.uri) {
      continue
    }
    guard result is None &&
      self
      .relationships()
      .filter(other => !other.external && other.target == link.target)
      .length() ==
      1 else {
      @failure.reject(
        "protected-content", "Shared or multiple bibliography source lists require ownership support",
      )
    }
    result = Some((link.target, document))
  }
  result
}

///|
/// Lists the document's native bibliography source records without changing its package.
pub fn Session::bibliography_sources(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let records = self
    .bibliography_part()
    .map(pair => read_bibliography_sources(WordTree::new(pair.1)))
    .unwrap_or([])
  let references : Set[String] = if records.is_empty() {
    Set([])
  } else {
    self.source_references()
  }
  let entries = records.map(record => {
    let value = record.value
    let result : Json = {
      "tag": value.tag,
      "kind": value.kind,
      "author": value.author,
      "title": value.title,
      "year": value.year,
      "publisher": value.publisher,
      "url": value.url,
      "reason": record.reason,
      "authorReason": record.author_reason,
      "deleteReason": if references.contains(value.tag) ||
        references.contains("") {
        "This source is cited in the document"
      } else {
        ""
      },
    }
    result
  })
  {
    "revision": revision,
    "sources": entries,
    "bibliographies": self.bibliography_fields(),
  }
}
