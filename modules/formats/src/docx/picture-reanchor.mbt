///|
fn Session::prepare_picture_anchor(
  self : Session,
  id : Int,
  anchor : @layout.DrawingAnchor?,
  target? : Position,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> PreparedEdit? raise @failure.Failure {
  guard target is Some(target) else {
    return self.prepare_picture_placement(id, anchor, probe?, profile~, images?)
  }
  let original = self.document()
  let tree = WordTree::new(original)
  let (image, paragraph, _, _) = self.editable_picture(tree, id, position=true)
  guard image.anchor is Some(_) && anchor is Some(_) else {
    @failure.reject(
      "invalid-operation", "Reanchoring requires a floating picture",
    )
  }
  for paragraph in [paragraph, target.paragraph] {
    guard tree.nodes.get(paragraph) is Some(node) &&
      tree.nodes.get(node.parent) is Some(parent) &&
      parent.uri == word_uri &&
      parent.name == "body" else {
      @failure.reject(
        "protected-content", "Picture anchors require body paragraphs",
      )
    }
  }
  ignore(
    self.paragraph_range(
      tree,
      { anchor: target, focus: target, },
      structural=true,
    ),
  )
  let offset = for
    item in self.texts.filter(item => item.paragraph == paragraph)
    cursor = 0 {
    if item.id == id {
      break cursor
    }
    continue cursor + inline_text(tree.nodes[item.id]).length()
  } nobreak {
    @failure.reject("invalid-image", "Picture has no logical anchor")
  }
  if paragraph == target.paragraph &&
    (target.offset == offset || target.offset == offset + 1) {
    return self.prepare_picture_placement(id, anchor, probe?, profile~, images?)
  }
  tree.check_structure_paragraph(paragraph)
  let frame = tree.nodes[tree.children[id][0]]
  guard paragraph == target.paragraph ||
    !["1", "true"].contains(frame.attribute("locked").unwrap_or("0")) else {
    @failure.reject("protected-content", "Picture paragraph anchor is locked")
  }
  // Validate the final placement, since the intermediate paragraph can have different wrapping.
  let placement = self.prepare_picture_placement(id, anchor)
  let document = placement.map(value => value.document).unwrap_or(original)
  let tree = WordTree::new(document)
  let drawing = tree.nodes[id]
  let run = tree.nodes[drawing.parent]
  let source = document.source()
  let properties = tree
    .child(run.id, "rPr")
    .map(id => source[tree.nodes[id].start:tree.nodes[id].end].to_owned())
    .unwrap_or("")
  let moved = source[run.start:run.opening_end - 1].to_owned() +
    tree.namespace_additions(run.id, target.paragraph) +
    ">" +
    properties +
    source[drawing.start:drawing.end].to_owned() +
    "</" +
    run.qualified +
    ">"
  let (removed, removal) = document.edit_source([
    {
      node: run.id,
      offset: drawing.start - run.start,
      length: drawing.end - drawing.start,
      xml: "",
    },
  ])
  let target = {
    ..target,
    offset: target.offset -
    (if paragraph == target.paragraph && target.offset > offset {
      1
    } else {
      0
    }),
    bidiLevel: None,
    frameStart: None,
  }
  let tree = WordTree::new(removed)
  let insertion = tree.picture_anchor_insertion(
    removed,
    target,
    moved,
    self.opc.budget.entry_bytes.min(history_byte_limit / 2),
  )
  let (candidate, addition) = removed.edit_source([insertion])
  let placed = for
    item in docx_texts(WordTree::new(candidate)).filter(item => {
      item.paragraph == target.paragraph
    })
    cursor = 0 {
    if cursor == target.offset && candidate.node(item.id).name == "drawing" {
      break item.id
    }
    continue cursor + inline_text(candidate.node(item.id)).length()
  } nobreak {
    @failure.reject("invalid-image", "Moved picture has no logical anchor")
  }
  ignore(self.image_frame(WordTree::new(candidate), placed))
  self.check_picture_layout(candidate, probe, profile, images)
  let xml = placement.map(value => value.edit.xml.copy()).unwrap_or([])
  xml.append([removal, addition])
  let start = { ..target, affinity: "after", }
  let end = { ..target, offset: target.offset + 1, affinity: "before", }
  Some({
    document: candidate,
    typing_text: None,
    join_group: false,
    edit: {
      xml,
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: Some({ anchor: start, focus: end, }),
      paragraphs: if paragraph == target.paragraph {
        [paragraph]
      } else {
        [paragraph, target.paragraph]
      },
      bytes: xml.fold(init=0, (total, step) => total + edit_bytes(step)),
    },
  })
}

///|
fn WordTree::picture_anchor_insertion(
  self : WordTree,
  document : @xml.Document,
  position : Position,
  moved : String,
  limit : Int,
) -> @xml.SourceChange raise @failure.Failure {
  let texts = docx_texts(self).filter(item => {
    item.paragraph == position.paragraph
  })
  let target = for item in texts; cursor = 0 {
    let length = inline_text(self.nodes[item.id]).length()
    if position.offset < cursor + length ||
      (position.offset == cursor + length && position.affinity == "before") {
      break Some((item.id, position.offset - cursor))
    }
    continue cursor + length
  } nobreak {
    texts
    .last()
    .map(item => (item.id, inline_text(self.nodes[item.id]).length()))
  }
  let paragraph = self.nodes[position.paragraph]
  guard target is Some((id, offset)) else {
    return if paragraph.empty {
      {
        node: paragraph.id,
        offset: paragraph.opening_end - paragraph.start - 2,
        length: 2,
        xml: ">" + moved + "</" + paragraph.qualified + ">",
      }
    } else {
      {
        node: paragraph.id,
        offset: paragraph.closing_start - paragraph.start,
        length: 0,
        xml: moved,
      }
    }
  }
  let node = self.nodes[id]
  let run = self.nodes[node.parent]
  guard run.uri == word_uri && run.name == "r" && run.parent == paragraph.id else {
    @failure.reject(
      "protected-content", "Picture anchor inside a field or hyperlink is protected",
    )
  }
  let source = document.source()
  let text = inline_text(node)
  let (left, right) = if offset == 0 || offset == text.length() {
    let cut = if offset == 0 { node.start } else { node.end }
    (
      source[run.opening_end:cut].to_owned(),
      source[cut:run.closing_start].to_owned(),
    )
  } else {
    guard node.name == "t" &&
      node.uri == word_uri &&
      node.attributes.all(attr => {
        attr.uri == "http://www.w3.org/XML/1998/namespace" &&
        attr.name == "space"
      }) &&
      !source[node.start:node.end].contains("<!--") &&
      !source[node.start:node.end].contains("<?") else {
      @failure.reject(
        "protected-content", "Unknown inline source prevents anchor insertion",
      )
    }
    (
      source[run.opening_end:node.start].to_owned() +
      inline_markup(text[:offset].to_owned(), limit),
      inline_markup(text[offset:].to_owned(), limit) +
      source[node.end:run.closing_start].to_owned(),
    )
  }
  let opening = source[run.start:run.opening_end].to_owned()
  let closing = "</" + run.qualified + ">"
  let properties = self
    .child(run.id, "rPr")
    .map(id => source[self.nodes[id].start:self.nodes[id].end].to_owned())
    .unwrap_or("")
  let xml = opening +
    left +
    closing +
    moved +
    opening +
    properties +
    right +
    closing
  guard xml.length() <= limit else {
    @failure.reject("limit-exceeded", "Picture anchor source exceeds budget")
  }
  {
    node: paragraph.id,
    offset: run.start - paragraph.start,
    length: run.end - run.start,
    xml,
  }
}
