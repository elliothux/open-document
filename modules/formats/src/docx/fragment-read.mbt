///|
fn check_fragment_content(
  tree : WordTree,
  nodes : Array[Int],
  pictures : Map[Int, Bool],
  fields~ : Bool = false,
) -> Unit raise @failure.Failure {
  let mut units = 0
  for id in nodes {
    let node = tree.nodes[id]
    if pictures.contains(id) {
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
      "r" => ["rPr", "t", "tab", "br", "cr", "drawing"]
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
        children.contains(tree.nodes[child].name)
      }) &&
      !["pStyle", "rStyle"].contains(node.name) else {
      @failure.reject(
        "protected-content", "Rich table fragment contains unsupported references or structure",
      )
    }
    if node.name == "hyperlink" {
      tree.check_hyperlink(id)
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
