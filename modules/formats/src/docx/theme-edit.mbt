///|
fn blank_word_theme() -> String {
  let out = StringBuilder()
  out.write_string(
    "<a:theme xmlns:a=\"\{theme_uri}\" name=\"Open Document\"><a:themeElements><a:clrScheme name=\"Default\">",
  )
  for
    (slot, color) in [
      ("dk1", "000000"),
      ("lt1", "ffffff"),
      ("dk2", "1f497d"),
      ("lt2", "eeece1"),
      ("accent1", "4f81bd"),
      ("accent2", "c0504d"),
      ("accent3", "9bbb59"),
      ("accent4", "8064a2"),
      ("accent5", "4bacc6"),
      ("accent6", "f79646"),
      ("hlink", "0000ff"),
      ("folHlink", "800080"),
    ] {
    out.write_string("<a:\{slot}><a:srgbClr val=\"\{color}\"/></a:\{slot}>")
  }
  out.write_string("</a:clrScheme><a:fontScheme name=\"Default\">")
  for kind in ["majorFont", "minorFont"] {
    out.write_string(
      "<a:\{kind}><a:latin typeface=\"Times New Roman\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:\{kind}>",
    )
  }
  out.write_string(
    "</a:fontScheme><a:fmtScheme name=\"Default\"><a:fillStyleLst>",
  )
  let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
  for _ in 0..<3 {
    out.write_string(fill)
  }
  out.write_string("</a:fillStyleLst><a:lnStyleLst>")
  for width in [6350, 12700, 19050] {
    out.write_string(
      "<a:ln w=\"\{width}\">\{fill}<a:prstDash val=\"solid\"/></a:ln>",
    )
  }
  out.write_string("</a:lnStyleLst><a:effectStyleLst>")
  for _ in 0..<3 {
    out.write_string("<a:effectStyle><a:effectLst/></a:effectStyle>")
  }
  out.write_string("</a:effectStyleLst><a:bgFillStyleLst>")
  for _ in 0..<3 {
    out.write_string(fill)
  }
  out.write_string(
    "</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>",
  )
  out.to_string()
}

///|
fn Session::theme_edit_reason(self : Session) -> String raise @failure.Failure {
  if self.settings_part() is Some(part) {
    let tree = WordTree::new(self.part_xml(part))
    for id in tree.children[0] {
      let node = tree.nodes[id]
      if node.uri != word_uri {
        continue
      }
      let enabled = node
        .attribute(
          if node.name == "documentProtection" {
            "enforcement"
          } else {
            "val"
          },
          uri=word_uri,
        )
        .unwrap_or(if node.name == "documentProtection" { "0" } else { "1" })
      if ["documentProtection", "styleLockTheme"].contains(node.name) &&
        !["0", "false", "off"].contains(enabled) {
        return "Document theme is protected"
      }
    }
  }
  ""
}

///|
pub fn Session::theme_colors(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let reason = self.theme_edit_reason()
  let tree = WordTree::new(
    match self.theme_part() {
      Some(part) => self.part_xml(part)
      None =>
        @xml.Document::parse(
          @utf8.encode(blank_word_theme()),
          "",
          self.opc.budget.xml_depth,
          self.opc.budget.entry_bytes,
        )
    },
  )
  {
    "revision": revision,
    "colors": Json(
      theme_slots.map(slot => {
        {
          "slot": Json(slot),
          "color": Json(theme_rgb(tree, theme_color_node(tree, slot))),
          "reason": Json(reason),
        } catch {
          @failure.Failure(message~, ..) =>
            {
              "slot": Json(slot),
              "color": Json::null(),
              "reason": Json(message),
            }
        }
      }),
    ),
  }
}

///|
pub fn Session::set_theme_color(
  self : Session,
  revision : Int,
  slot : String,
  value : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard theme_slots.contains(slot) &&
    value.length() == 6 &&
    value.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject("invalid-operation", "Invalid theme color slot or RGB")
  }
  let reason = self.theme_edit_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let original = self.theme_part()
  let parts = self.parts.copy()
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let part = match original {
    Some(part) => part
    None => self.new_word_part("theme", parts, edits, created)
  }
  let document = parts.get(part).unwrap_or_else(() => self.part_xml(part))
  let tree = WordTree::new(document)
  let target = theme_color_node(tree, slot)
  let value = value.to_lower()
  if theme_rgb(tree, target) == value && original is Some(_) {
    return self.edit_state()
  }
  let node = tree.nodes[target]
  let (candidate, edit) = document.edit_source([
    {
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml: "<a:srgbClr xmlns:a=\"\{theme_uri}\" val=\"\{value}\"/>",
    },
  ])
  parts[part] = candidate
  if created.contains(part) {
    created[part] = candidate
  } else {
    edits[part] = [edit]
  }
  let view = { ..self, parts, }
  ignore(view.flow())
  let affected = WordTree::new(self.document()).order.filter(id => {
    let node = self.document().node(id)
    node.uri == word_uri && node.name == "p"
  })
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [],
      parts: edits,
      created,
      created_media: Map([]),
      before: self.selection,
      after: self.selection.map(s => s.without_visual_hints()),
      paragraphs: affected,
      bytes: xml_part_edit_bytes(edits, created),
    },
    self.document(),
    parts~,
  )
  self.typing_format = pending
  self.edit_result(affected)
}
