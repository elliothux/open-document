///|
/// Inserts a solid, editable WordArt text box as one source transaction.
pub fn Session::insert_word_art(
  self : Session,
  revision : Int,
  preset : String,
  text : String,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
  images? : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let color = match preset {
    "blue" => "4472C4"
    "gold" => "FFC000"
    "red" => "C00000"
    "purple" => "7030A0"
    "green-italic" => "70AD47"
    _ => @failure.reject("invalid-operation", "Unknown solid WordArt preset")
  }
  guard !text.trim().is_empty() else {
    @failure.reject("invalid-operation", "WordArt text must not be empty")
  }
  let prepared = self.prepare_shape_insertion(
    "rect",
    2700000.0 / 12700,
    720000.0 / 12700,
    "",
    "",
    0,
    text~,
  )
  let tree = WordTree::new(prepared.document)
  let focus = prepared.edit.after.unwrap().focus
  let id = tree.text_box_drawing(focus.paragraph).unwrap()
  let shape = tree.children[tree.drawing_data(id).1.id][0]
  let content = tree.nodes[tree.nodes[focus.paragraph].parent]
  let paragraphs = tree.children[content.id]
  let style = CharacterFormat::new(
    size=Set(36),
    bold=Set(true),
    italic=Set(preset == "green-italic"),
    color=Set(color),
  ).properties()
  let paragraph_style = ParagraphFormat::new(
    align=Set("center"),
    before=Set(0),
    after=Set(0),
    line=Set(@layout.Auto(240)),
  ).properties()
  let changes : Array[@xml.SourceChange] = []
  for paragraph in paragraphs {
    let mark = formatted_properties(
      tree,
      prepared.document,
      paragraph,
      "rPr",
      style,
    )
    let properties = formatted_properties(
      tree,
      prepared.document,
      paragraph,
      "pPr",
      paragraph_style,
      nested=Map([("rPr", mark)]),
    )
    let node = tree.nodes[paragraph]
    changes.push({
      node: paragraph,
      offset: node.opening_end - node.start,
      length: 0,
      xml: properties,
    })
    for run in tree.children[paragraph] {
      let node = tree.nodes[run]
      let properties = formatted_properties(
        tree,
        prepared.document,
        run,
        "rPr",
        style,
      )
      changes.push({
        node: run,
        offset: node.opening_end - node.start,
        length: 0,
        xml: properties,
      })
    }
  }
  let frame = tree.drawing_data(id).0
  let doc = tree.nodes[tree.anchor_child(frame.id, "docPr")]
  let name = doc.attributes
    .iter()
    .find_first(attr => attr.name == "name")
    .unwrap()
  changes.push({
    node: doc.id,
    offset: name.start - doc.start,
    length: name.end - name.start,
    xml: "WordArt " + doc.attribute("id").unwrap(),
  })
  let body = tree.nodes[tree
    .drawing_child(shape, "bodyPr", uri=word_shape_uri)
    .unwrap()]
  changes.push({
    node: body.id,
    offset: body.opening_end - body.start - 1,
    length: 0,
    xml: " anchor=\"ctr\" wrap=\"none\"",
  })
  let (candidate, xml) = prepared.document.edit_source(changes)
  let view = { ..self, document: Some(candidate), }
  let positioned = view
    .prepare_drawing_placement(
      id,
      Some({
        horizontal: @layout.Offset("column", 0),
        vertical: @layout.Offset("paragraph", 0),
        behind: false,
        order: 0,
        wrapping: "none",
        wrapSide: "bothSides",
        distance: { top: 0, right: 0, bottom: 0, left: 0, },
      }),
    )
    .unwrap()
  self.check_picture_layout(positioned.document, probe, profile, images)
  let steps = [..prepared.edit.xml, xml, ..positioned.edit.xml]
  let mut bytes = 0
  for step in steps {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - bytes else {
      @failure.reject(
        "limit-exceeded", "WordArt insertion exceeds history budget",
      )
    }
    bytes += size
  }
  self.commit_edit(
    {
      ..prepared.edit,
      xml: steps,
      bytes,
      after: Some({
        anchor: { ..focus, paragraph: paragraphs[0], offset: 0, },
        focus,
      }),
    },
    positioned.document,
  )
  self.edit_result(prepared.edit.paragraphs)
}
