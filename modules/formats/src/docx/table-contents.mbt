///|
fn Session::prepare_table_contents(
  self : Session,
  tree : WordTree,
  cells : TableCellRange,
  text : String,
  check_graphemes~ : Bool,
  notes~ : Bool = false,
) -> PreparedEdit raise @failure.Failure {
  // ONLYOFFICE replaces the first selected cell on input and clears all selected cells on deletion.
  let texts = docx_texts(tree)
  if !text.is_empty() {
    let selection = tree.cell_contents_selection(cells.owners[0], texts)
    if self.prepare_plain_range(selection, text, check_graphemes~, notes~)
      is Some(prepared) {
      return prepared
    }
    let (document, step) = self.document().edit_source([])
    let focus = { ..selection.focus, affinity: "after", }
    return {
      document,
      typing_text: None,
      join_group: false,
      edit: {
        xml: [step],
        parts: Map([]),
        created: Map([]),
        created_media: Map([]),
        before: self.selection,
        after: Some({ anchor: focus, focus, }),
        paragraphs: [focus.paragraph],
        bytes: 0,
      },
    }
  }
  let targets = cells.owners
  let steps : Array[@xml.Edit] = []
  let affected : Array[Int32] = []
  let mut candidate = self.document()
  let mut result : PreparedEdit? = None
  let mut bytes = 0
  // shortcut: Clearing reparses each cell; batch patches if long selections block input.
  for index in 0..<targets.length() {
    let selection = tree.cell_contents_selection(
      targets[targets.length() - index - 1],
      texts,
    )
    let prepared = self.prepare_structural_range_in(
      candidate,
      selection,
      text,
      check_graphemes~,
      notes~,
    )
    guard prepared.edit.bytes <= history_byte_limit - bytes else {
      @failure.reject("limit-exceeded", "Table content history exceeds budget")
    }
    bytes += prepared.edit.bytes
    steps.append(prepared.edit.xml)
    affected.append(prepared.edit.paragraphs)
    candidate = prepared.document
    result = Some(prepared)
  }
  let result = result.unwrap()
  {
    ..result,
    document: candidate,
    join_group: false,
    edit: {
      ..result.edit,
      xml: steps,
      before: self.selection,
      paragraphs: affected,
      bytes,
    },
  }
}

///|
fn WordTree::cell_contents_selection(
  self : WordTree,
  cell : Int32,
  texts : Array[TextNode],
) -> Selection {
  let paragraphs = self.table_children(cell, "p")
  let first = paragraphs[0]
  let last = paragraphs.last().unwrap()
  let length = texts
    .iter()
    .fold(init=0, (sum, item) => {
      if item.paragraph == last {
        sum + inline_text(self.nodes[item.id]).length()
      } else {
        sum
      }
    })
  {
    anchor: {
      paragraph: first,
      offset: 0,
      affinity: "after",
      bidiLevel: None,
      frameStart: None,
    },
    focus: {
      paragraph: last,
      offset: length,
      affinity: "before",
      bidiLevel: None,
      frameStart: None,
    },
  }
}
