///|
fn Session::watermark_headers(
  self : Session,
  tree : WordTree,
) -> Array[Map[String, String]] raise @failure.Failure {
  let effective : Map[String, String] = Map([])
  tree
  .page_sections()
  .map(section => {
    let seen : Set[String] = Set([])
    for id in section.map(id => tree.children[id]).unwrap_or([]) {
      let node = tree.nodes[id]
      if node.uri != word_uri || node.name != "headerReference" {
        continue
      }
      let variant = node.attribute("type", uri=word_uri).unwrap_or("")
      guard ["default", "first", "even"].contains(variant) &&
        !seen.contains(variant) else {
        @failure.reject(
          "protected-content", "Invalid or duplicate watermark header variant",
        )
      }
      seen.add(variant)
      effective[variant] = self.running_part(tree, id, "header")
    }
    effective.copy()
  })
}

///|
fn Session::watermark_sources(
  self : Session,
  headers : Array[Map[String, String]],
) -> Map[String, WatermarkSource?] raise @failure.Failure {
  let sources : Map[String, WatermarkSource?] = Map([])
  for variants in headers {
    for part in variants.values() {
      if sources.contains(part) {
        continue
      }
      sources[part] = WordTree::new(self.part_xml(part))
        .header_watermark()
        .map(mark => { ..mark, value: self.watermark_value(part, mark.value), })
    }
  }
  sources
}
