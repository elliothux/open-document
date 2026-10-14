///|
let spreadsheet_uri = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

///|
let relationship_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

///|
priv struct Tree {
  document : @xml.Document
  nodes : Map[Int, @xml.Node]
  children : Map[Int, Array[@xml.Node]]
}

///|
fn Tree::new(document : @xml.Document) -> Tree {
  let nodes : Map[Int, @xml.Node] = Map([])
  let children : Map[Int, Array[@xml.Node]] = Map([])
  for node in document.nodes() {
    nodes[node.id] = node
    if children.get(node.parent) is Some(items) {
      items.push(node)
    } else {
      children[node.parent] = [node]
    }
  }
  { document, nodes, children, }
}

///|
fn Tree::all(self : Tree, parent : Int, name : String) -> Array[@xml.Node] {
  self.children
  .get(parent)
  .unwrap_or([])
  .filter(node => node.uri == spreadsheet_uri && node.name == name)
}

///|
fn Tree::one(
  self : Tree,
  parent : Int,
  name : String,
) -> @xml.Node? raise @failure.Failure {
  let nodes = self.all(parent, name)
  guard nodes.length() <= 1 else {
    @failure.reject("malformed-xlsx", "Duplicate " + name + " element")
  }
  nodes.get(0)
}

///|
fn Tree::root(self : Tree, name : String) -> @xml.Node raise @failure.Failure {
  let root = self.document.nodes()[0]
  guard root.name == name && root.uri == spreadsheet_uri else {
    @failure.reject("unsupported-xlsx", "Expected Transitional " + name)
  }
  root
}

///|
fn Tree::text(self : Tree, id : Int) -> (String, Bool) raise @failure.Failure {
  let runs = self.all(id, "r")
  let rich = !runs.is_empty() || !self.all(id, "rPh").is_empty()
  let text = if !runs.is_empty() {
    runs
    .map(run => self.one(run.id, "t").map(node => node.text).unwrap_or(""))
    .join("")
  } else {
    self.one(id, "t").map(node => node.text).unwrap_or("")
  }
  guard text.length() <= 32767 else {
    @failure.reject("limit-exceeded", "Cell string exceeds budget")
  }
  (decode_text(text), rich)
}

///|
// SpreadsheetML escapes encode UTF-16 units; decode once so _x005F_ stays literal.
fn decode_text(text : String) -> String raise @failure.Failure {
  let output = StringBuilder()
  let mut index = 0
  while index < text.length() {
    if index + 7 <= text.length() &&
      text[index:index + 2] == "_x" &&
      text[index + 6] == 95 {
      let unit = @string.parse_int(text[index + 2:index + 6], base=16) catch {
        _ => -1
      }
      if unit >= 0 {
        if unit >= 0xd800 && unit <= 0xdbff {
          guard index + 14 <= text.length() &&
            text[index + 7:index + 9] == "_x" &&
            text[index + 13] == 95 else {
            @failure.reject("malformed-xlsx", "Unpaired escaped surrogate")
          }
          let low = @string.parse_int(text[index + 9:index + 13], base=16) catch {
            _ => -1
          }
          guard low >= 0xdc00 && low <= 0xdfff else {
            @failure.reject("malformed-xlsx", "Unpaired escaped surrogate")
          }
          output.write_char(
            (0x10000 + (unit - 0xd800) * 1024 + low - 0xdc00).to_char().unwrap(),
          )
          index += 14
        } else {
          guard unit < 0xdc00 || unit > 0xdfff else {
            @failure.reject("malformed-xlsx", "Unpaired escaped surrogate")
          }
          output.write_char(unit.to_char().unwrap())
          index += 7
        }
        continue
      }
    }
    let character = text.get_char(index).unwrap()
    output.write_char(character)
    index += if character.to_int() > 0xffff { 2 } else { 1 }
  }
  output.to_string()
}

///|
fn encode_text(text : String) -> String raise @failure.Failure {
  // Protect escape-like literals before XML escaping.
  let output = StringBuilder()
  let mut index = 0
  while index < text.length() {
    if index + 7 <= text.length() &&
      text[index:index + 2] == "_x" &&
      text[index + 6] == 95 &&
      (@string.parse_int(text[index + 2:index + 6], base=16) catch { _ => -1 }) >=
      0 {
      output.write_string("_x005F_")
      index += 1
    } else {
      let character = text.get_char(index).unwrap()
      output.write_char(character)
      index += if character.to_int() > 0xffff { 2 } else { 1 }
    }
  }
  @xml.escape_text(output.to_string())
}
