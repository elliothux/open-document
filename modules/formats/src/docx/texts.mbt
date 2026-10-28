///|
fn docx_texts(tree : WordTree) -> Array[TextNode] {
  let body = tree.child(0, "body").unwrap()
  let texts : Array[TextNode] = []
  let fields : Map[Int32, Bool] = Map([])
  for id in tree.order {
    let node = tree.nodes[id]
    if tree.index_markers.contains(id) {
      continue
    }
    if node.uri == math_uri &&
      ["oMath", "oMathPara"].contains(node.name) &&
      node.parent >= 0 &&
      tree.nodes[node.parent].uri == word_uri &&
      tree.nodes[node.parent].name == "p" {
      let in_body = for ancestor = node.parent
                        ancestor >= 0
                        ancestor = tree.nodes[ancestor].parent {
        if ancestor == body {
          break true
        }
      } nobreak {
        false
      }
      if in_body {
        texts.push({ id, paragraph: node.parent, run: id, })
      }
      continue
    }
    if node.uri == word_uri &&
      node.name == "fldSimple" &&
      node.parent >= 0 &&
      tree.nodes[node.parent].name == "p" &&
      tree.nodes[node.parent].uri == word_uri {
      let in_body = for ancestor = node.parent
                        ancestor >= 0
                        ancestor = tree.nodes[ancestor].parent {
        if ancestor == body {
          break true
        }
      } nobreak {
        false
      }
      let supported = fields.get_or_init(node.parent, () => {
        try {
          ignore(tree.running_fields(node.parent))
          true
        } catch {
          @failure.Failure(..) => false
        }
      })
      if in_body && supported {
        texts.push({
          id,
          paragraph: node.parent,
          run: tree.field_result_run(id).unwrap_or(id),
        })
      }
      continue
    }
    if node.uri != word_uri ||
      ![
        "t", "delText", "br", "cr", "tab", "drawing", "footnoteReference", "endnoteReference",
      ].contains(node.name) {
      continue
    }
    let run = node.parent
    if run < 0 || tree.nodes[run].uri != word_uri || tree.nodes[run].name != "r" {
      continue
    }
    if tree.nodes[run].parent >= 0 &&
      tree.nodes[tree.nodes[run].parent].uri == word_uri &&
      tree.nodes[tree.nodes[run].parent].name == "fldSimple" {
      continue
    }
    let parent = tree.nodes[run].parent
    let paragraph = if parent >= 0 &&
      tree.nodes[parent].uri == word_uri &&
      ["ins", "del"].contains(tree.nodes[parent].name) {
      try {
        ignore(tree.check_text_revision(parent))
        tree.nodes[parent].parent
      } catch {
        @failure.Failure(..) => -1
      }
    } else {
      tree.run_paragraph(run)
    }
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
      match node.attribute("type", uri=word_uri) {
        Some("column") => "\u000b"
        Some("page") => "\u000c"
        _ => "\u2028"
      }
    "cr" => "\u2028"
    "tab" => "\t"
    "drawing" => "\ufffc"
    "fldSimple" => "\ufffc"
    "footnoteReference" | "endnoteReference" => "\ufffc"
    "oMath" | "oMathPara" => "\ufffc"
    _ => node.text
  }
}
