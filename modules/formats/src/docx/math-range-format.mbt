///|
fn ParagraphRange::math_roots(
  self : ParagraphRange,
  tree : WordTree,
) -> Array[Int] {
  let roots : Array[Int] = []
  let texts = docx_texts(tree)
  for paragraph in self.paragraphs {
    let start = if paragraph == self.start.paragraph {
      self.start.offset
    } else {
      0
    }
    let end = if paragraph == self.end.paragraph {
      self.end.offset
    } else {
      2147483647
    }
    for item in texts.filter(item => item.paragraph == paragraph); offset = 0 {
      let node = tree.nodes[item.id]
      let length = inline_text(node).length()
      if node.uri == math_uri && start < offset + length && end > offset {
        roots.push(node.id)
      }
      continue offset + length
    }
  }
  roots
}

///|
fn CharacterFormat::math_font_patch(self : CharacterFormat) -> Bool {
  self ==
  CharacterFormat::new(family=self.family, size=self.size, color=self.color) &&
  self.family != Clear &&
  self.size != Clear &&
  self.color != Clear
}

///|
fn Session::selected_math_style(
  self : Session,
  tree : WordTree,
  id : Int,
) -> @layout.TextStyle raise @failure.Failure {
  let paragraph = tree.nodes[id].parent
  let value = self.styles([]).character_style(tree, paragraph, None, [])
  math_content_style(
    self.read_inline_math(
      tree,
      id,
      @layout.TextStyle::new(
        value.key(),
        value.size,
        value.text_color(tree.page_background().unwrap_or("ffffff")),
      ),
    ).content,
  )
}

///|
fn Session::math_font_changes(
  self : Session,
  tree : WordTree,
  document : @xml.Document,
  id : Int,
  patch : CharacterFormat,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if patch == CharacterFormat::new() {
    return []
  }
  guard patch.math_font_patch() else {
    @failure.reject(
      "protected-content", "Formula selections accept font family, size and RGB color",
    )
  }
  ignore(self.math_target(tree, id))
  let current = self.selected_math_style(tree, id)
  let next = math_fraction_style(
    CharacterFormat::new(
      family=Set(if patch.family is Set(value) { value } else { current.font }),
      size=Set(if patch.size is Set(value) { value } else { current.size }),
      color=Set(if patch.color is Set(value) { value } else { current.color }),
    ),
  )
  let markup = @omml.math_properties_markup(next)
  let changes : Array[@xml.SourceChange] = []
  for node in tree.descendants(id) {
    if tree.nodes[node].uri == math_uri &&
      ["r", "ctrlPr"].contains(tree.nodes[node].name) {
      if (current.font, current.size, current.color) ==
        (next.font, next.size, next.color) &&
        tree.child(node, "rPr") is Some(_) {
        continue
      }
      let math_properties = tree.children[node]
        .iter()
        .find_first(id => {
          tree.nodes[id].uri == math_uri && tree.nodes[id].name == "rPr"
        })
      let change = if tree.child(node, "rPr") is None &&
        math_properties is Some(properties) {
        Some(@xml.SourceChange::{
          node,
          offset: tree.nodes[properties].end - tree.nodes[node].start,
          length: 0,
          xml: markup,
        })
      } else {
        properties_change(tree, document, node, "rPr", markup)
      }
      if change is Some(change) {
        changes.push(change)
      }
    }
  }
  changes
}
