///|
fn docx_texts(tree : WordTree) -> Array[TextNode] {
  let body = tree.child(0, "body").unwrap()
  let texts : Array[TextNode] = []
  for id in tree.order {
    let node = tree.nodes[id]
    if node.uri != word_uri ||
      !["t", "br", "cr", "tab", "drawing"].contains(node.name) {
      continue
    }
    let run = node.parent
    if run < 0 || tree.nodes[run].uri != word_uri || tree.nodes[run].name != "r" {
      continue
    }
    let paragraph = tree.nodes[run].parent
    if paragraph < 0 ||
      tree.nodes[paragraph].uri != word_uri ||
      tree.nodes[paragraph].name != "p" {
      continue
    }
    let in_body = for ancestor = paragraph
                      ancestor >= 0
                      ancestor = tree.nodes[ancestor].parent {
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
  texts
}

///|
fn inline_text(node : @xml.Node) -> String {
  match node.name {
    "br" =>
      if node.attribute("type", uri=word_uri) == Some("page") {
        "\u000c"
      } else {
        "\u2028"
      }
    "cr" => "\u2028"
    "tab" => "\t"
    "drawing" => "\ufffc"
    _ => node.text
  }
}
