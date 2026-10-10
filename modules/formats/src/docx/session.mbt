///|
let word_uri = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

///|
struct TextNode {
  id : Int
  paragraph : Int
  run : Int
}

///|
pub struct Session {
  opc : @opc.Package
  main : String
  mut document : @xml.Document?
  texts : Array[TextNode]
  replacements : Map[Int, String]
  mut revision : Int
  mut closed : Bool
  diagnostics : Array[String]
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  let opc = @opc.Package::open(bytes, budget)
  let mut main : String? = None
  for rel in opc.relationships() {
    if rel.owner.is_empty() &&
      rel.kind ==
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" {
      guard !rel.external && main is None else {
        @failure.reject(
          "malformed-docx", "Invalid or duplicate main relationship",
        )
      }
      main = Some(rel.target)
    }
    guard !rel.kind.has_prefix(
      "http://purl.oclc.org/ooxml/officeDocument/relationships/",
    ) else {
      @failure.reject("unsupported-docx", "Strict OOXML is unsupported")
    }
    guard !rel.kind.has_prefix(
      "http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/",
    ) else {
      @failure.reject("unsupported-docx", "Signed packages are unsupported")
    }
  }
  guard main is Some(main) else {
    @failure.reject("malformed-docx", "Missing officeDocument relationship")
  }
  guard opc.content_type(main) ==
    Some(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml",
    ) else {
    @failure.reject(
      "unsupported-docx",
      "Only Transitional DOCX documents are supported",
      part=main,
    )
  }
  let document = opc.xml(main)
  let nodes = document.nodes()
  guard nodes[0].uri == word_uri && nodes[0].name == "document" else {
    @failure.reject(
      "unsupported-docx",
      "Unsupported Word document namespace",
      part=main,
    )
  }
  let texts : Array[TextNode] = []
  let diagnostics : Array[String] = []
  let mut body = -1
  for id, node in nodes {
    if node.parent == 0 && node.uri == word_uri && node.name == "body" {
      guard body < 0 else {
        @failure.reject("malformed-docx", "Duplicate document body", part=main)
      }
      body = id
    }
  }
  guard body >= 0 else {
    @failure.reject("malformed-docx", "Missing document body", part=main)
  }
  for id, node in nodes {
    if node.parent == body &&
      !(node.uri == word_uri && (node.name == "p" || node.name == "sectPr")) {
      diagnostics.push("preserved-structure:" + node.qualified)
    }
    if node.uri != word_uri || node.name != "t" {
      continue
    }
    let run = node.parent
    if run < 0 || nodes[run].uri != word_uri || nodes[run].name != "r" {
      continue
    }
    let paragraph = nodes[run].parent
    if paragraph < 0 ||
      nodes[paragraph].uri != word_uri ||
      nodes[paragraph].name != "p" {
      continue
    }
    let in_body = for ancestor = paragraph
                      ancestor >= 0
                      ancestor = nodes[ancestor].parent {
      if ancestor == body {
        break true
      }
    } nobreak {
      false
    }
    if in_body {
      texts.push({ id, paragraph, run, })
    }
  }
  {
    opc,
    main,
    document: Some(document),
    texts,
    replacements: Map([]),
    revision: 0,
    closed: false,
    diagnostics,
  }
}

///|
fn Session::document(self : Session) -> @xml.Document raise @failure.Failure {
  guard !self.closed && self.document is Some(document) else {
    @failure.reject("closed-session", "DOCX session is closed")
  }
  document
}

///|
pub fn Session::query(self : Session) -> Json raise @failure.Failure {
  let nodes = self.document().nodes()
  let texts : Array[Json] = []
  for node in self.texts {
    texts.push({
      "id": node.id,
      "paragraph": node.paragraph,
      "run": node.run,
      "text": self.replacements.get(node.id).unwrap_or(nodes[node.id].text),
    })
  }
  let rels : Array[Json] = []
  for rel in self.opc.relationships() {
    rels.push({
      "owner": rel.owner,
      "id": rel.id,
      "type": rel.kind,
      "target": rel.target,
      "external": rel.external,
    })
  }
  {
    "revision": self.revision,
    "mainPart": self.main,
    "texts": texts,
    "relationships": rels,
    "diagnostics": self.diagnostics,
    "decodedBytes": self.opc.decoded_bytes(),
  }
}

///|
pub fn Session::replace(
  self : Session,
  id : Int,
  revision : Int,
  text : String,
) -> Int raise @failure.Failure {
  let document = self.document()
  guard revision == self.revision else {
    @failure.reject("stale-revision", "Revision does not match current session")
  }
  guard self.revision < 0x7fffffff else {
    @failure.reject("limit-exceeded", "Revision exhausted")
  }
  guard self.texts.iter().any(node => node.id == id) else {
    @failure.reject("invalid-operation", "Unknown or unsupported text node")
  }
  let candidate = self.replacements.copy()
  candidate[id] = text
  let bytes = document.replace(candidate)
  self.opc.validate_replacements(Map::from_array([(self.main, bytes)]))
  self.replacements[id] = text
  self.revision += 1
  self.revision
}

///|
pub fn Session::save(self : Session) -> Bytes raise @failure.Failure {
  let document = self.document()
  let replacements : Map[String, Bytes] = Map([])
  if !self.replacements.is_empty() {
    replacements[self.main] = document.replace(self.replacements)
  }
  self.opc.save(replacements)
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.closed = true
  self.opc.close()
  self.document = None
  self.texts.clear()
  self.replacements.clear()
  self.diagnostics.clear()
}
