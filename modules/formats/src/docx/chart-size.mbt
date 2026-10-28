///|
fn Session::prepare_chart_resize(
  self : Session,
  id : Int32,
  width : Double,
  height : Double,
) -> PreparedEdit? raise @failure.Failure {
  self.check_document_protection()
  let document = self.document()
  let tree = WordTree::new(document)
  let (paragraph, _) = self.editable_chart(tree, id, operation=ChartRetain)
  let frame = self.drawing_frame(tree, id)
  guard width >= 180 && width <= 14400 && height >= 150 && height <= 14400 else {
    @failure.reject("invalid-chart", "Invalid chart frame dimensions")
  }
  let width = (width * 12700).round() / 12700
  let height = (height * 12700).round() / 12700
  if width == frame.width && height == frame.height {
    return None
  }
  tree.check_chart_operation(id, ChartResize)
  guard !tree.shape_locked(id, "noChangeAspect") ||
    (width * frame.height - height * frame.width).abs() <=
    (frame.width + frame.height) / 12700 else {
    @failure.reject("protected-content", "Chart aspect ratio is locked")
  }
  let extent = tree.nodes[tree.anchor_child(
      tree.drawing_data(id).0.id,
      "extent",
    )]
  let changes : Array[@xml.SourceChange] = ["cx", "cy"].mapi((index, name) => {
    let attribute = extent.attributes
      .iter()
      .find_first(attribute => {
        attribute.name == name && attribute.uri.is_empty()
      })
      .unwrap()
    {
      node: extent.id,
      offset: attribute.start - extent.start,
      length: attribute.end - attribute.start,
      xml: ((if index == 0 { width } else { height }) * 12700)
      .round()
      .to_int64()
      .to_string(),
    }
  })
  let (candidate, xml) = document.edit_source(changes)
  Some({
    document: candidate,
    typing_text: None,
    join_group: false,
    edit: {
      xml: [xml],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [paragraph],
      bytes: edit_bytes(xml),
    },
  })
}
