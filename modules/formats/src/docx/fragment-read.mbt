///|
fn check_fragment_content(
  tree : WordTree,
  nodes : Array[Int],
  objects : Map[Int, Bool],
  fields~ : Bool = false,
  notes~ : Bool = false,
) -> Unit raise @failure.Failure {
  let mut units = 0
  for id in nodes {
    let node = tree.nodes[id]
    if objects.contains(id) {
      continue
    }
    guard node.uri == word_uri else {
      @failure.reject(
        "protected-content", "Foreign rich table content is unsupported",
      )
    }
    if node.name == "t" {
      guard node.text.length() <= command_limit - units else {
        @failure.reject(
          "limit-exceeded", "Rich table text exceeds UTF-16 budget",
        )
      }
      units += node.text.length()
    } else {
      guard node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Rich table contains misplaced text",
        )
      }
    }
    guard (
        node.name != "br" ||
        node.attribute("type", uri=word_uri).unwrap_or("textWrapping") ==
        "textWrapping"
      ) &&
      !node.attributes.any(a => {
        a.name.has_suffix("Theme") ||
        a.name.has_prefix("theme") ||
        a.name == "cstheme"
      }) else {
      @failure.reject(
        "protected-content", "Rich table contains unresolved style resources or breaks",
      )
    }
    let children = match node.name {
      "body" => ["p", "tbl"]
      "tbl" => ["tblPr", "tblGrid", "tr"]
      "tblPr" =>
        ["tblLayout", "tblW", "jc", "tblBorders", "tblCellMar", "tblInd"]
      "tblGrid" => ["gridCol"]
      "tr" => ["trPr", "tc"]
      "trPr" => ["trHeight", "tblHeader", "cantSplit"]
      "tc" => ["tcPr", "p"]
      "tcPr" =>
        ["tcW", "gridSpan", "vMerge", "tcBorders", "shd", "tcMar", "vAlign"]
      "p" =>
        ["pPr", "r", "hyperlink", "bookmarkStart", "bookmarkEnd"] +
        (if fields { ["fldSimple"] } else { [] })
      "fldSimple" if fields => ["r"]
      "hyperlink" => ["r", "bookmarkStart", "bookmarkEnd"]
      "r" =>
        ["rPr", "t", "tab", "br", "cr", "drawing"] +
        (if notes {
          ["footnoteReference", "endnoteReference", "footnoteRef", "endnoteRef"]
        } else {
          []
        })
      "pPr" =>
        [
          "rPr", "spacing", "ind", "jc", "pageBreakBefore", "autoSpaceDE", "autoSpaceDN",
          "tabs", "bidi", "numPr", "outlineLvl", "keepLines", "keepNext", "widowControl",
          "contextualSpacing",
        ]
      "rPr" =>
        [
          "rFonts", "sz", "color", "b", "i", "lang", "bCs", "iCs", "szCs", "u", "strike",
          "highlight", "vertAlign", "cs", "rtl", "spacing",
        ]
      "tabs" => ["tab"]
      "numPr" => ["numId", "ilvl"]
      "tcBorders" | "tcMar" | "tblCellMar" => ["top", "left", "bottom", "right"]
      "tblBorders" => ["top", "left", "bottom", "right", "insideH", "insideV"]
      _ => []
    }
    guard tree.children[id].all(child => {
        children.contains(tree.nodes[child].name) || objects.contains(child)
      }) &&
      !["pStyle", "rStyle"].contains(node.name) else {
      @failure.reject(
        "protected-content", "Rich table fragment contains unsupported references or structure",
      )
    }
    if node.name == "hyperlink" {
      if node.attribute("target", uri=table_fragment_uri) is Some(_) {
        ignore(fragment_link_target(tree, node))
      } else {
        tree.check_hyperlink(id)
      }
    }
    if note_reference(node) || ["footnoteRef", "endnoteRef"].contains(node.name) {
      guard notes &&
        tree.nodes[node.parent].name == "r" &&
        tree.nodes[tree.nodes[node.parent].parent].name == "p" &&
        tree.children[id].is_empty() &&
        node.attributes.all(a => {
          note_reference(node) && a.uri == word_uri && a.name == "id"
        }) else {
        @failure.reject("protected-content", "Invalid rich note marker")
      }
      if note_reference(node) {
        ignore(note_key(node.attribute("id", uri=word_uri).unwrap_or("")))
      }
    }
    if node.name == "fldSimple" {
      guard fields &&
        tree.nodes[node.parent].uri == word_uri &&
        tree.nodes[node.parent].name == "p" else {
        @failure.reject(
          "protected-content", "Rich fields require a paragraph container",
        )
      }
      tree.simple_page_fields(node.parent)
    }
    if [
        "body", "tbl", "tblPr", "tblGrid", "tr", "trPr", "tc", "tcPr", "p", "pPr",
        "r", "rPr",
      ].contains(node.name) {
      guard node.attributes.is_empty() && node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Rich table identity metadata is unsupported",
        )
      }
    }
  }
}
