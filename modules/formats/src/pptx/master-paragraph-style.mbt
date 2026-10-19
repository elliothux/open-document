///|
fn check_master_paragraph(properties : Ref?) -> Unit raise @failure.Failure {
  guard properties is Some(p) else { return }
  let markup = source_xml(p)
  guard !markup.contains("<!--") &&
    !markup.contains("<?") &&
    p.node.text.trim().is_empty() &&
    p.node.attributes.all(a => {
      a.uri.is_empty() &&
      [
        "marL", "marR", "indent", "algn", "rtl", "lvl", "defTabSz", "fontAlgn", "eaLnBrk",
        "latinLnBrk", "hangingPunct",
      ].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "Extended master paragraph metadata is protected",
    )
  }
  check_list_properties(p)
  for node in p.tree.children.get(p.node.id).unwrap_or([]) {
    guard node.uri == drawing_uri &&
      [
        "lnSpc", "spcBef", "spcAft", "buClrTx", "buClr", "buSzTx", "buSzPct", "buSzPts",
        "buFontTx", "buFont", "buNone", "buChar", "buAutoNum", "tabLst", "defRPr",
      ].contains(node.name) else {
      @failure.reject(
        "protected-content", "Extended master paragraph content is protected",
      )
    }
    if node.name.has_prefix("bu") {
      check_bullet_property({ tree: p.tree, node, })
    }
    if ["lnSpc", "spcBef", "spcAft"].contains(node.name) {
      guard node.attributes.is_empty() &&
        node.text.trim().is_empty() &&
        p.tree.children.get(node.id).unwrap_or([]) is [child] &&
        child.uri == drawing_uri &&
        ["spcPts", "spcPct"].contains(child.name) &&
        child.attributes.length() == 1 &&
        child.attribute("val") is Some(_) &&
        child.text.is_empty() &&
        p.tree.children.get(child.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "protected-content", "Extended master spacing is protected",
        )
      }
    }
  }
  ignore(read_paragraph_tabs([p]))
}

///|
fn master_paragraph(
  tree : Tree,
  main : Tree,
  theme : Theme,
  kind : String,
  level : Int,
) -> TextParagraph raise @failure.Failure {
  let (_, _, own) = master_text_style(tree, kind, level)
  let styles = master_style_sources(tree, main, kind, level)
  let style = text_style(theme, children(styles, "defRPr"), "A", "+mn-lt")
  let runs : Array[TextRun] = [
    { source: None, date_field: None, text: "", parts: [(style, "")], },
  ]
  let source = own.unwrap_or({ tree, node: tree.document.nodes()[0], })
  let (resolved, reason) = read_paragraph_style(
    source,
    own,
    styles,
    level,
    runs,
    theme,
    [],
  )
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  resolved
}

///|
fn Session::master_paragraph_query(
  self : Session,
  tree : Tree,
  theme : Theme,
  kind : String,
  level : Int,
) -> Json {
  let fields = [
    "left", "right", "first", "before", "after", "line", "list", "level", "rtl",
    "listFont", "listSize", "listColor", "tabs", "defaultTab",
  ]
  let result : Map[String, Json] = Map([])
  for field in fields {
    result[field] = Json::null()
  }
  result["alignment"] = Json::null()
  result["reason"] = Json("")
  try {
    let (_, _, own) = master_text_style(tree, kind, level)
    check_master_paragraph(own)
    let paragraph = master_paragraph(tree, self.main, theme, kind, level)
    let values = paragraph_values(paragraph)
    for index, field in fields {
      result[field] = values[index]
    }
    result["alignment"] = Json(paragraph.align)
  } catch {
    @failure.Failure(message~, ..) => result["reason"] = Json(message)
  }
  Json(result)
}

///|
fn Session::set_master_paragraph_style(
  self : Session,
  part : String,
  kind : String,
  level : Int,
  format : ParagraphFormat?,
  alignment : String?,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard alignment
    .map(v => ["left", "center", "right", "justify"].contains(v))
    .unwrap_or(true) &&
    format.map(f => f.level is None).unwrap_or(true) else {
    @failure.reject(
      "invalid-operation", "Invalid master paragraph alignment or nested level",
    )
  }
  let format = format.map(f => f.normalized())
  let original = self.source_slide(part)
  let tree = original.tree
  guard tree.document.nodes()[0].name == "sldMaster" else {
    @failure.reject("invalid-slide", "Select a master source")
  }
  let (_, _, own) = master_text_style(tree, kind, level)
  check_master_paragraph(own)
  let theme_part = relation(self.opc, part, "theme", parts=self.parts).unwrap()
  let theme = read_theme(
    load_tree(self.opc, self.cache, theme_part, parts=self.parts),
    [tree],
  )
  let paragraph = master_paragraph(tree, self.main, theme, kind, level)
  let markup = paragraph_markup(
    paragraph,
    own,
    format,
    name="lvl\{level+1}pPr",
    style=true,
    alignment~,
  )
  if markup.is_empty() || own.map(source_xml) == Some(markup) {
    return self.query()
  }
  self.commit_master_style(
    original,
    master_level_change(tree, kind, level, markup),
    probe,
    profile,
  )
}
