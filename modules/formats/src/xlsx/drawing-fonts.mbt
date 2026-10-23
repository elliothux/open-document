///|
fn Session::drawing_font_keys(
  self : Session,
  parts : Map[String, @xml.Document],
) -> Array[String] raise @failure.Failure {
  let drawings : Map[String, @xml.Document] = Map([])
  for link in self.relationships() {
    if !link.external && link.kind == relationship_uri + "drawing" {
      drawings[link.target] = parts
        .get(link.target)
        .unwrap_or_else(() => self.part_xml(link.target))
    }
  }
  for path, document in parts {
    let root = document.nodes()[0]
    if root.uri == picture_uri && root.name == "wsDr" {
      drawings[path] = document
    }
  }
  let keys : Map[String, Bool] = Map([])
  for document in drawings.values() {
    if document
      .nodes()
      .any(node => node.uri == slicer_drawing_uri && node.name == "slicer") {
      keys[self.normal_font] = true
      keys[self.normal_font + "|bold"] = true
    }
    if document
      .nodes()
      .any(node => {
        node.uri == picture_drawing_uri &&
        node.name == "graphicData" &&
        node.attribute("uri") == Some(chart_uri)
      }) {
      keys["Arial"] = true
    }
    let tree = Tree::new(document)
    for node in document.nodes() {
      if node.uri != picture_drawing_uri ||
        !["rPr", "defRPr", "endParaRPr"].contains(node.name) {
        continue
      }
      let paragraph = for parent = node.parent
                          parent >= 0
                          parent = tree.nodes[parent].parent {
        let ancestor = tree.nodes[parent]
        if ancestor.uri == picture_drawing_uri && ancestor.name == "p" {
          break Some(ancestor)
        }
      } nobreak {
        None
      }
      let base = paragraph
        .bind(paragraph => {
          tree.picture_child(paragraph.id, "pPr", uri=picture_drawing_uri)
        })
        .bind(properties => {
          tree.picture_child(properties.id, "defRPr", uri=picture_drawing_uri)
        })
      let base_font = base
        .bind(properties => {
          tree.picture_child(properties.id, "latin", uri=picture_drawing_uri)
        })
        .bind(latin => latin.attribute("typeface"))
        .unwrap_or(self.normal_font)
      let family = tree
        .picture_child(node.id, "latin", uri=picture_drawing_uri)
        .bind(latin => latin.attribute("typeface"))
        .unwrap_or(base_font)
      let family = if ["+mn-lt", "+mj-lt"].contains(family) {
        self.normal_font
      } else {
        family
      }
      let bold = flag(
        node,
        "b",
        fallback=base.map(properties => flag(properties, "b")).unwrap_or(false),
      )
      let italic = flag(
        node,
        "i",
        fallback=base.map(properties => flag(properties, "i")).unwrap_or(false),
      )
      let key = family +
        (if bold { "|bold" } else { "" }) +
        (if italic { "|italic" } else { "" })
      guard key.length() <= 280 && keys.length() < 4096 else {
        @failure.reject(
          "limit-exceeded", "Worksheet drawing fonts exceed budget",
        )
      }
      keys[key] = true
    }
  }
  keys.keys().to_array()
}
