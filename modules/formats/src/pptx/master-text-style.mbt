///|
fn master_text_style(
  tree : Tree,
  kind : String,
  level : Int32,
) -> (Ref?, Ref?, Ref?) raise @failure.Failure {
  guard ["title", "body", "other"].contains(kind) && level >= 0 && level <= 8 else {
    @failure.reject("invalid-operation", "Invalid master text style or level")
  }
  let styles = tree
    .one(tree.root("sldMaster").id, "txStyles", uri=presentation_uri)
    .map(node => { tree, node, })
  let category = styles.bind(p => p.child(kind + "Style", uri=presentation_uri))
  let paragraph = category.bind(p => p.child("lvl\{level + 1}pPr"))
  (styles, category, paragraph)
}

///|
fn master_text_properties(paragraph : Ref?) -> Ref? raise @failure.Failure {
  let properties = paragraph.bind(p => p.child("defRPr"))
  if properties is Some(source) {
    let markup = source_xml(source)
    guard source.node.text.trim().is_empty() &&
      !markup.contains("<!--") &&
      !markup.contains("<?") &&
      source.node.attributes.all(a => {
        a.uri.is_empty() &&
        [
          "lang", "altLang", "sz", "b", "i", "u", "strike", "kern", "cap", "spc",
          "normalizeH", "baseline", "noProof", "dirty", "err", "smtClean", "smtId",
          "bmk", "kumimoji",
        ].contains(a.name)
      }) &&
      source.tree.children
      .get(source.node.id)
      .unwrap_or([])
      .all(node => {
        node.uri == drawing_uri &&
        ["noFill", "solidFill", "latin", "ea", "cs", "highlight"].contains(
          node.name,
        )
      }) else {
      @failure.reject(
        "protected-content", "Extended master text properties are protected",
      )
    }
    ignore(paint_fill(source))
    for kind in ["latin", "ea", "cs"] {
      if source.child(kind) is Some(font) {
        guard font.node.text.trim().is_empty() &&
          font.tree.children.get(font.node.id).unwrap_or([]).is_empty() &&
          font.node.attributes.all(a => {
            a.uri.is_empty() &&
            ["typeface", "panose", "pitchFamily", "charset"].contains(a.name)
          }) else {
          @failure.reject(
            "protected-content", "Extended master font is protected",
          )
        }
      }
    }
    if source.child("highlight") is Some(highlight) {
      check_highlight(highlight)
    }
  }
  properties
}

///|
fn Session::master_text_styles(self : Session, current : Slide) -> Json {
  try {
    guard current.tree.document.nodes()[0].name == "sldMaster" else {
      return { "items": [], "reason": "Select a master source" }
    }
    let tree = current.tree
    let theme_part = relation(self.opc, tree.part, "theme", parts=self.parts).unwrap()
    let theme = read_theme(
      load_tree(self.opc, self.cache, theme_part, parts=self.parts),
      [tree],
    )
    let items : Array[Json] = []
    for kind in ["title", "body", "other"] {
      for level in 0..<9 {
        let (format, reason) = try {
          let (_, _, paragraph) = master_text_style(tree, kind, level)
          ignore(master_text_properties(paragraph))
          let sources = master_style_sources(tree, self.main, kind, level)
          let style = text_style(
            theme,
            children(sources, "defRPr"),
            "A",
            "+mn-lt",
          )
          let fonts = style.font.split("|").to_array()
          let format : Json = {
            "font": fonts[0].to_owned(),
            "size": style.size,
            "spacing": style.spacing,
            "bold": fonts.contains("bold"),
            "italic": fonts.contains("italic"),
            "color": style.color.to_lower(),
            "underline": style.underline,
            "strike": style.strike,
            "highlight": style.highlight.to_lower(),
            "script": style.script,
          }
          (format, "")
        } catch {
          @failure.Failure(message~, ..) => (Json::null(), message)
        }
        items.push({
          "kind": kind,
          "level": level,
          "format": format,
          "reason": reason,
          "paragraph": self.master_paragraph_query(tree, theme, kind, level),
        })
      }
    }
    { "items": items, "reason": self.modification_reason() }
  } catch {
    @failure.Failure(message~, ..) => { "items": [], "reason": message }
  }
}

///|
fn Session::set_master_text_style(
  self : Session,
  part : String,
  kind : String,
  level : Int32,
  format : TextFormat?,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let original = self.source_slide(part)
  let format = format.map(f => f.normalized())
  let tree = original.tree
  guard tree.document.nodes()[0].name == "sldMaster" else {
    @failure.reject("invalid-slide", "Select a master source")
  }
  let (_, _, paragraph) = master_text_style(tree, kind, level)
  let properties = master_text_properties(paragraph)
  if format is None && properties is None {
    return self.query()
  }
  let change = if format is None && properties is Some(properties) {
    remove_slide_node(tree, properties.node)
  } else {
    let markup = formatted_properties(properties, "defRPr", format)
    if properties is Some(properties) && source_xml(properties) == markup {
      return self.query()
    }
    if paragraph is Some(paragraph) {
      text_property_change(paragraph, "defRPr", format)
    } else {
      master_level_change(
        tree,
        kind,
        level,
        "<a:lvl\{level+1}pPr xmlns:a=\"\{drawing_uri}\">\{markup}</a:lvl\{level+1}pPr>",
      )
    }
  }
  self.commit_master_style(original, change, probe, profile)
}

///|
fn Session::commit_master_style(
  self : Session,
  original : Slide,
  change : @xml.SourceChange,
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let part = original.tree.part
  let prepared = self.prepare(original, [change])
  check_changed_source_fonts(original, prepared.0, probe, profile)
  let affected = prepared.0.objects
    .filter(object => {
      object.source.tree.part == part &&
      object.body.fit != "none" &&
      object.fit_key() != original.object(object.id).fit_key()
    })
    .map(object => object.id)
  let (candidate, edit) = if affected.is_empty() {
    prepared
  } else {
    guard probe is Some(probe) else {
      @failure.reject(
        "missing-font", "Master text reflow requires a font probe and profile",
      )
    }
    self.prepare_fitted(original, [change], affected, probe, profile)
  }
  self.commit_page(candidate, [(part, edit)], self.selection, probe?, profile~)
  self.query()
}
