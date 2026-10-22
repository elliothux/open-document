///|
let math_uri = "http://schemas.openxmlformats.org/officeDocument/2006/math"

///|
let word_uri = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

///|
let drawing_uri = "http://schemas.openxmlformats.org/drawingml/2006/main"

///|
priv struct Tree {
  nodes : Map[Int, @xml.Node]
  children : Map[Int, Array[Int]]
}

///|
fn Tree::child(self : Tree, parent : Int, name : String) -> Int? {
  for id in self.children[parent] {
    if self.nodes[id].uri == word_uri && self.nodes[id].name == name {
      return Some(id)
    }
  }
  None
}

///|
fn Tree::value(self : Tree, parent : Int, name : String) -> String? {
  self
  .child(parent, name)
  .bind(id => self.nodes[id].attribute("val", uri=word_uri))
}

///|
fn Tree::number(
  self : Tree,
  parent : Int,
  name : String,
  attribute : String,
) -> Double? raise @failure.Failure {
  match
    self
    .child(parent, name)
    .bind(id => self.nodes[id].attribute(attribute, uri=word_uri)) {
    None => None
    Some(value) => {
      let number = @string.parse_int(value[:]).to_double() catch {
        _ =>
          @failure.reject(
            "invalid-style",
            "Invalid numeric Word property: " + name,
          )
      }
      Some(number)
    }
  }
}

///|
pub fn read(
  nodes : Map[Int, @xml.Node],
  children : Map[Int, Array[Int]],
  id : Int,
  base : @layout.TextStyle,
  nary_limit : (String) -> String raise @failure.Failure,
) -> @layout.MathFormula raise @failure.Failure {
  let reader : MathRead = { base, style: None, nodes: 0, units: 0, nary_limit, }
  let formula = @layout.MathFormula::new(
    reader.sequence({ nodes, children, }, id, 0),
    reader.style.unwrap_or(base),
  )
  let frame : @layout.DrawingFrame = {
    width: 0,
    height: 0,
    anchor: None,
    content: Math(formula),
  }
  frame.validate()
  formula
}
