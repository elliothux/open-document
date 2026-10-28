///|
let presentation_uri = "http://schemas.openxmlformats.org/presentationml/2006/main"

///|
let drawing_uri = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
let relationship_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

///|
priv struct Tree {
  part : String
  document : @xml.Document
  nodes : Map[Int32, @xml.Node]
  children : Map[Int32, Array[@xml.Node]]
}

///|
fn Tree::new(part : String, document : @xml.Document) -> Tree {
  let nodes = Map([])
  let children : Map[Int32, Array[@xml.Node]] = Map([])
  for node in document.nodes() {
    nodes[node.id] = node
    if children.get(node.parent) is Some(items) {
      items.push(node)
    } else {
      children[node.parent] = [node]
    }
  }
  { part, document, nodes, children, }
}

///|
fn Tree::all(
  self : Tree,
  parent : Int32,
  name : String,
  uri~ : String = drawing_uri,
) -> Array[@xml.Node] {
  self.children
  .get(parent)
  .unwrap_or([])
  .filter(node => node.name == name && node.uri == uri)
}

///|
fn Tree::one(
  self : Tree,
  parent : Int32,
  name : String,
  uri~ : String = drawing_uri,
) -> @xml.Node? raise @failure.Failure {
  let nodes = self.all(parent, name, uri~)
  guard nodes.length() <= 1 else {
    @failure.reject("malformed-pptx", "Duplicate " + name, part=self.part)
  }
  nodes.get(0)
}

///|
fn Tree::required(
  self : Tree,
  parent : Int32,
  name : String,
  uri~ : String = drawing_uri,
) -> @xml.Node raise @failure.Failure {
  self
  .one(parent, name, uri~)
  .unwrap_or_error(
    @failure.Failure(
      code="malformed-pptx",
      part=self.part,
      offset=-1,
      message="Missing " + name,
    ),
  )
}

///|
fn Tree::root(
  self : Tree,
  name : String,
  uri~ : String = presentation_uri,
) -> @xml.Node raise @failure.Failure {
  let root = self.document.nodes()[0]
  guard root.name == name && root.uri == uri else {
    @failure.reject(
      "unsupported-pptx",
      "Expected Transitional " + name,
      part=self.part,
    )
  }
  root
}

///|
fn number(
  value : String,
  low : Double,
  high : Double,
) -> Double raise @failure.Failure {
  let parsed = @string.parse_double(value) catch {
    _ =>
      @failure.reject("malformed-pptx", "Invalid numeric attribute: " + value)
  }
  guard !parsed.is_nan() &&
    !parsed.is_inf() &&
    parsed == parsed.floor() &&
    parsed >= low &&
    parsed <= high else {
    @failure.reject("malformed-pptx", "Numeric attribute outside bounds")
  }
  parsed
}

///|
fn flag(
  node : @xml.Node,
  key : String,
  default~ : Bool = false,
) -> Bool raise @failure.Failure {
  match node.attribute(key) {
    None => default
    Some("1" | "true") => true
    Some("0" | "false") => false
    _ => @failure.reject("malformed-pptx", "Invalid boolean attribute")
  }
}

///|
fn relation(
  opc : @opc.Package,
  owner : String,
  kind : String,
  parts~ : Map[String, @xml.Document] = Map([]),
) -> String? raise @failure.Failure {
  if parts.get(relationship_part(owner)) is Some(document) {
    let root = document.nodes()[0]
    let links = document
      .nodes()
      .filter(node => {
        node.parent == root.id &&
        node.attribute("Type") == Some(relationship_uri + "/" + kind)
      })
    guard links.length() <= 1 else {
      @failure.reject(
        "malformed-pptx",
        "Invalid " + kind + " relationship",
        part=owner,
      )
    }
    return links
      .get(0)
      .map(link => {
        guard [None, Some("Internal")].contains(link.attribute("TargetMode")) &&
          link.attribute("Target") is Some(target) else {
          @failure.reject(
            "malformed-pptx",
            "Invalid " + kind + " relationship",
            part=owner,
          )
        }
        @opc.resolve_target(owner, target)
      })
  }
  let links = opc
    .relationships()
    .iter()
    .filter(rel => {
      rel.owner == owner && rel.kind == relationship_uri + "/" + kind
    })
    .collect()
  guard links.length() <= 1 && links.all(link => !link.external) else {
    @failure.reject(
      "malformed-pptx",
      "Invalid " + kind + " relationship",
      part=owner,
    )
  }
  links.get(0).map(link => link.target)
}

///|
fn load_tree(
  opc : @opc.Package,
  cache : Map[String, Tree],
  part : String,
  parts~ : Map[String, @xml.Document] = Map([]),
) -> Tree raise @failure.Failure {
  if parts.get(part) is Some(document) {
    return Tree::new(part, document)
  }
  if cache.get(part) is Some(tree) {
    return tree
  }
  guard cache.length() < 2048 else {
    @failure.reject("limit-exceeded", "PPTX dependency count exceeds budget")
  }
  let tree = Tree::new(part, opc.xml(part))
  let ids : Map[String, Bool] = Map([])
  for node in tree.document.nodes() {
    if node.uri == presentation_uri && node.name == "cNvPr" {
      let id = source_identity(node.attribute("id").unwrap_or(""))
      guard !ids.contains(id) else {
        @failure.reject("malformed-pptx", "Duplicate object identity", part~)
      }
      ids[id] = true
    }
  }
  cache[part] = tree
  tree
}

///|
fn source_identity(value : String) -> String raise @failure.Failure {
  guard !value.is_empty() && value.iter().all(ch => ch >= '0' && ch <= '9') else {
    @failure.reject("malformed-pptx", "Invalid numeric identity")
  }
  number(value, 1, 4294967295).to_int64().to_string()
}

///|
priv struct Ref {
  tree : Tree
  node : @xml.Node
}

///|
fn Ref::child(
  self : Ref,
  name : String,
  uri~ : String = drawing_uri,
) -> Ref? raise @failure.Failure {
  self.tree
  .one(self.node.id, name, uri~)
  .map(node => { tree: self.tree, node, })
}

///|
fn children(
  chain : Array[Ref],
  name : String,
  uri~ : String = drawing_uri,
) -> Array[Ref] raise @failure.Failure {
  let result : Array[Ref] = []
  for item in chain {
    if item.child(name, uri~) is Some(child) {
      result.push(child)
    }
  }
  result
}

///|
fn attribute(chain : Array[Ref], key : String) -> String? {
  chain.iter().filter_map(item => item.node.attribute(key)).next()
}

///|
fn insertion(node : @xml.Node, xml : String) -> @xml.SourceChange {
  if node.empty {
    {
      node: node.id,
      offset: node.opening_end - node.start - 2,
      length: 2,
      xml: ">\{xml}</\{node.qualified}>",
    }
  } else {
    { node: node.id, offset: node.closing_start - node.start, length: 0, xml, }
  }
}
