///|
fn Session::comment_word_selection(
  self : Session,
  document : @xml.Document,
  selection : Selection,
) -> Selection raise @failure.Failure {
  ignore(self.formatting_range(document, selection))
  let caret = selection.focus
  guard selection.anchor.paragraph == caret.paragraph &&
    selection.anchor.offset == caret.offset else {
    @failure.reject(
      "invalid-position", "Word comments require a collapsed caret",
    )
  }
  let tree = WordTree::new(document)
  let text = self
    .editable_texts(caret.paragraph)
    .map(t => inline_text(tree.nodes[t.id]))
    .join("")
  match @layout.word_range_at(text, caret.offset) {
    None => selection
    Some((start, end)) =>
      {
        anchor: {
          ..caret,
          offset: start,
          affinity: "after",
          bidiLevel: None,
          frameStart: None,
        },
        focus: {
          ..caret,
          offset: end,
          affinity: "before",
          bidiLevel: None,
          frameStart: None,
        },
      }
  }
}

///|
fn Session::select_comment(
  self : Session,
  selection : Selection,
) -> Json raise @failure.Failure {
  self.selection = Some(selection)
  self.typing_text = None
  self.typing_format = None
  self.input_group = None
  self.vertical_x = None
  self.navigation_layout = -1
  self.edit_result([])
}

///|
/// Cycles through editable open root anchors in source document order without writing history.
pub fn Session::navigate_comment(
  self : Session,
  revision : Int32,
  direction : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["previous", "next"].contains(direction) else {
    @failure.reject("invalid-operation", "Invalid comment navigation direction")
  }
  let source = self.comment_source()
  let roots = Map::from_array(
    source
    .map(s => {
      s.entries.filter(e => e.parent is None && !e.done).map(e => (e.key, true))
    })
    .unwrap_or([]),
  )
  let tree = WordTree::new(self.document())
  let anchors = tree
    .comment_anchors()
    .filter(a => {
      roots.contains(a.key) && a.reason.is_empty() && a.selection is Some(_)
    })
  if anchors.is_empty() {
    return { "comment": Json::null(), "state": self.edit_result([]) }
  }
  let rank : Map[Int32, Int32] = Map([])
  for id in tree.order {
    if tree.nodes[id].uri == word_uri && tree.nodes[id].name == "p" {
      rank[id] = rank.length()
    }
  }
  let compare = fn(a : Position, b : Position) -> Int32 {
    let paragraph = rank[a.paragraph].compare(rank[b.paragraph])
    if paragraph == 0 {
      a.offset.compare(b.offset)
    } else {
      paragraph
    }
  }
  let origin = self.selection.map(s => {
    self.check_position(s.anchor)
    self.check_position(s.focus)
    if compare(s.anchor, s.focus) <= 0 {
      s.anchor
    } else {
      s.focus
    }
  })
  let target = if direction == "next" {
    match origin {
      None => anchors[0]
      Some(origin) =>
        anchors
        .iter()
        .find_first(a => compare(a.selection.unwrap().anchor, origin) > 0)
        .unwrap_or(anchors[0])
    }
  } else {
    let last = anchors[anchors.length() - 1]
    match origin {
      None => last
      Some(origin) =>
        for i in 0..<anchors.length() {
          let anchor = anchors[anchors.length() - 1 - i]
          let range = anchor.selection.unwrap()
          if compare(range.focus, origin) <= 0 &&
            compare(range.anchor, origin) < 0 {
            break anchor
          }
        } nobreak {
          last
        }
    }
  }
  {
    "comment": target.key,
    "state": self.select_comment(target.selection.unwrap()),
  }
}
