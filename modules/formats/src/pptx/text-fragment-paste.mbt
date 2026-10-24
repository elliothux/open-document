///|
fn read_text_fragment(
  source : String,
  budget : @archive.Budget,
) -> (Tree, Array[@xml.Node], Int) raise @failure.Failure {
  guard source.length() <= 1048576 else {
    @failure.reject(
      "limit-exceeded", "Presentation text clipboard exceeds 1Mi units",
    )
  }
  let document = @xml.Document::parse(
    @utf8.encode(source),
    "clipboard",
    budget.xml_depth,
    budget.entry_bytes.min(4194304),
  )
  let tree = Tree::new("clipboard", document)
  let root = document.nodes()[0]
  let paragraphs = tree.children.get(root.id).unwrap_or([])
  guard root.uri == text_fragment_uri &&
    root.name == "fragment" &&
    root.attributes.is_empty() &&
    root.text.trim().is_empty() &&
    !source.contains("<!--") &&
    !source.contains("<?") &&
    !paragraphs.is_empty() &&
    paragraphs.length() <= 256 &&
    paragraphs.all(p => p.uri == drawing_uri && p.name == "p") else {
    @failure.reject("protected-content", "Invalid presentation text fragment")
  }
  let attributes : Map[String, Array[String]] = {
    "p": [],
    "pPr": ["lvl", "algn", "marL", "marR", "indent", "rtl", "defTabSz"],
    "r": [],
    "rPr": [
      "sz", "spc", "b", "i", "u", "strike", "baseline", "lang", "altLang", "dirty",
      "smtClean", "smtId", "noProof",
    ],
    "endParaRPr": [
      "sz", "spc", "b", "i", "u", "strike", "baseline", "lang", "altLang", "dirty",
      "smtClean", "smtId", "noProof",
    ],
    "t": ["space"],
    "br": [],
    "solidFill": [],
    "srgbClr": ["val"],
    "alpha": ["val"],
    "highlight": [],
    "latin": ["typeface", "pitchFamily", "charset"],
    "ea": ["typeface", "pitchFamily", "charset"],
    "cs": ["typeface", "pitchFamily", "charset"],
    "spcBef": [],
    "spcAft": [],
    "lnSpc": [],
    "spcPts": ["val"],
    "spcPct": ["val"],
    "buNone": [],
    "buChar": ["char"],
    "buAutoNum": ["type", "startAt"],
    "buFont": ["typeface"],
    "buClr": [],
    "buSzPts": ["val"],
    "buSzPct": ["val"],
    "tabLst": [],
    "tab": ["pos", "algn"],
    "link": [
      "kind", "target", "tooltip", "tgtFrame", "history", "highlightClick", "endSnd",
    ],
    "hoverLink": [
      "kind", "target", "tooltip", "tgtFrame", "history", "highlightClick", "endSnd",
    ],
  }
  let children : Map[String, Array[String]] = {
    "fragment": ["p"],
    "p": ["pPr", "r", "br", "endParaRPr"],
    "pPr": [
      "spcBef", "spcAft", "lnSpc", "buNone", "buChar", "buAutoNum", "buFont", "buClr",
      "buSzPts", "buSzPct", "tabLst",
    ],
    "r": ["rPr", "t"],
    "rPr": ["solidFill", "highlight", "latin", "ea", "cs", "link", "hoverLink"],
    "endParaRPr": [
      "solidFill", "highlight", "latin", "ea", "cs", "link", "hoverLink",
    ],
    "solidFill": ["srgbClr"],
    "highlight": ["srgbClr"],
    "buClr": ["srgbClr"],
    "srgbClr": ["alpha"],
    "spcBef": ["spcPts", "spcPct"],
    "spcAft": ["spcPts", "spcPct"],
    "lnSpc": ["spcPts", "spcPct"],
    "tabLst": ["tab"],
  }
  let mut length = paragraphs.length() - 1
  for node in document.nodes()[1:] {
    guard (
        (node.uri == drawing_uri && !["link", "hoverLink"].contains(node.name)) ||
        (
          node.uri == text_fragment_uri &&
          ["link", "hoverLink"].contains(node.name)
        )
      ) &&
      attributes.get(node.name) is Some(allowed) &&
      node.attributes.all(a => {
        allowed.contains(a.name) &&
        (
          a.uri.is_empty() ||
          (
            node.name == "t" &&
            a.name == "space" &&
            a.uri == "http://www.w3.org/XML/1998/namespace"
          )
        )
      }) &&
      children
      .get(tree.nodes[node.parent].name)
      .unwrap_or([])
      .contains(node.name) &&
      (node.name == "t" || node.text.trim().is_empty()) else {
      @failure.reject(
        "protected-content", "Unsupported native presentation clipboard content",
      )
    }
    if node.name == "t" {
      length += node.text.length()
    }
    if node.name == "br" {
      length += 1
    }
    let nested = tree.children.get(node.id).unwrap_or([])
    guard nested.all(child => {
        ["p", "r", "br", "tab"].contains(child.name) ||
        nested.filter(n => n.name == child.name).length() == 1
      }) &&
      (node.name != "r" || nested.filter(n => n.name == "t").length() == 1) &&
      (
        node.name != "alpha" ||
        (
          node.attribute("val") == Some("0") &&
          tree.nodes[tree.nodes[node.parent].parent].name == "highlight"
        )
      ) else {
      @failure.reject(
        "protected-content", "Malformed presentation text fragment",
      )
    }
  }
  guard length <= 32767 else {
    @failure.reject("limit-exceeded", "Pasted text exceeds text frame budget")
  }
  (tree, paragraphs, length)
}

///|
/// Pastes a validated native text fragment into one shape or table-cell range as one history entry.
pub fn Session::paste_text_fragment(
  self : Session,
  revision : Int,
  fragment : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let object = self.editable(true)
  let (tree, paragraphs, length) = read_text_fragment(fragment, self.budget)
  let selection = self.selection
  let original = self.source_slide(selection.slide)
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let tree = self.bind_text_fragment_links(
    tree,
    original.tree.part,
    parts,
    created,
    edits,
  )
  let a = selection.anchor.min(selection.focus)
  let b = selection.anchor.max(selection.focus)
  let boundaries = @layout.grapheme_boundaries(object.text())
  guard boundaries.contains(a) &&
    boundaries.contains(b) &&
    object.text().length() - (b - a) + length <= 32767 else {
    @failure.reject(
      "invalid-position", "Pasted range exceeds text frame or grapheme boundaries",
    )
  }
  let (first, start) = paragraph_location(object, a)
  let (last, end) = paragraph_location(object, b)
  let initial = object.paragraphs[first]
  let ending = object.paragraphs[last]
  guard initial.source.node.parent == ending.source.node.parent else {
    @failure.reject(
      "protected-content", "Rich paste requires one text container",
    )
  }
  let before = paragraph_piece(initial, 0, start)
  let tail = paragraph_piece(ending, end, paragraph_length(ending))
  let output = StringBuilder()
  let expected_tabs : Array[Array[ParagraphTab]?] = []
  for index, p in paragraphs {
    let target_properties = if index == 0 && start > 0 {
      Some(initial)
    } else if index == paragraphs.length() - 1 && end < paragraph_length(ending) {
      Some(ending)
    } else {
      None
    }
    output.write_string("<a:p xmlns:a='\{drawing_uri}'>")
    if target_properties is Some(paragraph) {
      expected_tabs.push(None)
      output.write_string(
        paragraph.source.child("pPr").map(source_xml).unwrap_or(""),
      )
    } else {
      expected_tabs.push(
        Some(
          read_paragraph_tabs(
            tree.one(p.id, "pPr").map(node => [{ tree, node, }]).unwrap_or([]),
          ),
        ),
      )
      output.write_string(
        tree
        .one(p.id, "pPr")
        .map(node => tree.standalone_markup(tree.document, node.id))
        .unwrap_or("<a:pPr><a:buNone/></a:pPr>"),
      )
    }
    if index == 0 {
      output.write_string(before)
    }
    for node in tree.children.get(p.id).unwrap_or([]) {
      if !["pPr", "endParaRPr"].contains(node.name) {
        output.write_string(tree.standalone_markup(tree.document, node.id))
      }
    }
    if index == paragraphs.length() - 1 {
      output.write_string(tail)
    }
    if tree.one(p.id, "endParaRPr") is Some(node) {
      output.write_string(tree.standalone_markup(tree.document, node.id))
    }
    output.write_string("</a:p>")
  }
  let parent = initial.source.tree.nodes[initial.source.node.parent]
  let changes : Array[@xml.SourceChange] = [
    {
      node: parent.id,
      offset: initial.source.node.start - parent.start,
      length: ending.source.node.end - initial.source.node.start,
      xml: output.to_string(),
    },
  ]
  let (slide, edit) = self.prepare_fitted(
    original,
    changes,
    [object.id],
    probe,
    profile,
  )
  let target = slide.object(object.id)
  for index, expected in expected_tabs {
    guard expected is None ||
      expected == Some(target.paragraphs[first + index].tabs) else {
      @failure.reject(
        "protected-content", "Target inherited tabs prevent preserving source paragraph formatting",
      )
    }
  }
  guard target.text_reason.is_empty() else {
    @failure.reject("protected-content", target.text_reason)
  }
  if target.table is Some(_) {
    ignore(target.paint_table(probe, profile))
  } else {
    ignore(fit_text(target, target.geometry.unwrap(), probe, profile))
  }
  let text = slide.object(object.id).text()
  let focus = @layout.grapheme_boundaries(text)
    .iter()
    .find_first(offset => offset >= a + length)
    .unwrap_or(text.length())
  edits.push((slide.tree.part, edit))
  self.commit_page(
    slide,
    edits,
    { ..selection, anchor: focus, focus, },
    parts~,
    created_parts=created,
    probe~,
    profile~,
  )
  self.query()
}
