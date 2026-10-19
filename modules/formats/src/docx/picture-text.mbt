///|
fn Session::check_native_pictures(
  self : Session,
  tree : WordTree,
  paragraph : Int,
) -> Unit raise @failure.Failure {
  for id in tree.descendants(paragraph) {
    if tree.nodes[id].uri == word_uri && tree.nodes[id].name == "drawing" {
      ignore(self.editable_picture(tree, id, replace=true))
    }
  }
}

///|
fn WordTree::has_picture_range(
  self : WordTree,
  texts : Array[TextNode],
  start : Int,
  end : Int,
) -> Bool {
  for item in texts; cursor = 0 {
    let length = inline_text(self.nodes[item.id]).length()
    if self.nodes[item.id].name == "drawing" &&
      start < cursor + length &&
      end > cursor {
      return true
    }
    continue cursor + length
  }
  false
}

///|
fn Session::check_picture_range(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
) -> Unit raise @failure.Failure {
  let texts = docx_texts(tree)
  for paragraph in range.paragraphs {
    let start = if paragraph == range.start.paragraph {
      range.start.offset
    } else {
      0
    }
    let end = if paragraph == range.end.paragraph {
      range.end.offset
    } else {
      0x7fffffff
    }
    for item in texts.filter(item => item.paragraph == paragraph); cursor = 0 {
      let length = inline_text(tree.nodes[item.id]).length()
      if tree.nodes[item.id].name == "drawing" &&
        start < cursor + length &&
        end > cursor {
        ignore(self.editable_picture(tree, item.id, remove=true))
      }
      continue cursor + length
    }
  }
}

///|
fn Session::picture_text_changes(
  self : Session,
  tree : WordTree,
  id : Int,
  text : String,
  image_offset : Int?,
  limit : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let node = tree.nodes[id]
  // Splitting a paragraph moves runs; anchor changes to its unchanged container.
  let paragraph = tree.nodes[tree.nodes[node.parent].parent]
  let parent = tree.nodes[paragraph.parent]
  let changes : Array[@xml.SourceChange] = []
  if image_offset is Some(offset) {
    ignore(self.editable_picture(tree, id, replace=true))
    guard offset >= 0 && offset < text.length() && text[offset] == '\ufffc' else {
      abort("Invalid retained image position")
    }
    for
      (position, value) in [
        (node.start, text[:offset].to_owned()),
        (node.end, text[offset + 1:].to_owned()),
      ] {
      if !value.is_empty() {
        changes.push({
          node: parent.id,
          offset: position - parent.start,
          length: 0,
          xml: inline_markup(value, limit),
        })
      }
    }
  } else {
    ignore(self.editable_picture(tree, id, remove=true))
    changes.push({
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: if text.is_empty() {
        ""
      } else {
        inline_markup(text, limit)
      },
    })
  }
  changes
}

///|
fn WordTree::split_picture_input(
  self : WordTree,
  document : @xml.Document,
  paragraph : Int,
  insertion : Int,
  offset : Int,
  parts : Array[String],
  tail : String,
  limit : Int,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let node = self.nodes[insertion]
  let run = self.nodes[node.parent]
  let p = self.nodes[paragraph]
  let parent = self.nodes[p.parent]
  let properties = self
    .child(run.id, "rPr")
    .map(id => {
      let value = self.nodes[id]
      document.source()[value.start:value.end].to_owned()
    })
    .unwrap_or("")
  let frame = "</\{run.qualified}></\{p.qualified}>" +
    structure_opening(p) +
    self.continuation_properties(document, paragraph) +
    structure_opening(run) +
    properties
  let output = StringBuilder()
  let mut units = 0
  for i, part in parts {
    if i > 0 {
      units += frame.length()
      output.write_string(frame)
    }
    guard units <= limit else {
      @failure.reject(
        "limit-exceeded", "Picture paragraph split exceeds source budget",
      )
    }
    let markup = inline_markup(part, limit - units)
    units += markup.length()
    guard units <= limit else {
      @failure.reject(
        "limit-exceeded", "Picture paragraph split exceeds source budget",
      )
    }
    output.write_string(markup)
  }
  let retained = offset == 1 || tail == "\ufffc"
  let position = if offset == 1 { node.end } else { node.start }
  [
    {
      node: parent.id,
      offset: position - parent.start,
      length: if retained {
        0
      } else {
        node.end - node.start
      },
      xml: output.to_string(),
    },
  ]
}
