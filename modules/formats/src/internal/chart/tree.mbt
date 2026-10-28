///|
let chart_uri = "http://schemas.openxmlformats.org/drawingml/2006/chart"

///|
let drawing_uri = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
let relationship_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

///|
priv struct Tree {
  part : String
  document : @xml.Document
  children : Map[Int32, Array[@xml.Node]]
}

///|
fn Tree::new(part : String, document : @xml.Document) -> Tree {
  let children : Map[Int32, Array[@xml.Node]] = Map([])
  for node in document.nodes() {
    if children.get(node.parent) is Some(items) {
      items.push(node)
    } else {
      children[node.parent] = [node]
    }
  }
  { part, document, children, }
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
    @failure.reject("unsupported-chart", "Duplicate " + name, part=self.part)
  }
  nodes.get(0)
}

///|
fn Tree::root(
  self : Tree,
  name : String,
  uri~ : String = chart_uri,
) -> @xml.Node raise @failure.Failure {
  let root = self.document.nodes()[0]
  guard root.name == name && root.uri == uri else {
    @failure.reject(
      "unsupported-chart",
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
      @failure.reject(
        "unsupported-chart",
        "Invalid numeric attribute: " + value,
      )
  }
  guard !parsed.is_nan() &&
    !parsed.is_inf() &&
    parsed == parsed.floor() &&
    parsed >= low &&
    parsed <= high else {
    @failure.reject("unsupported-chart", "Numeric attribute outside bounds")
  }
  parsed
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
fn relationship_part(owner : String) -> String {
  let segments = owner.split("/").map(segment => segment.to_owned()).to_array()
  let leaf = segments.pop().unwrap()
  segments.push("_rels")
  segments.push(leaf + ".rels")
  segments.join("/")
}
