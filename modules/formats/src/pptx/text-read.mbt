///|
fn text_style(
  theme : Theme,
  sources : Array[Ref],
  text : String,
  default_font : String,
) -> @layout.TextStyle raise @failure.Failure {
  let size = number(attribute(sources, "sz").unwrap_or("1800"), 100, 102400) /
    100
  let bold = attribute(sources, "b")
    .map(value => value == "1" || value == "true")
    .unwrap_or(false)
  let italic = attribute(sources, "i")
    .map(value => value == "1" || value == "true")
    .unwrap_or(false)
  let script = font_script(text)
  let font_kind = if ["Hans", "Hant", "Jpan", "Hang"].contains(script) {
    "ea"
  } else if script != "latin" {
    "cs"
  } else {
    "latin"
  }
  let families = children(sources, font_kind)
  let family = families
    .iter()
    .filter_map(item => item.node.attribute("typeface"))
    .find_first(value => !value.is_empty())
    .unwrap_or(
      attribute(children(sources, "latin"), "typeface").unwrap_or(default_font),
    )
  let paint = fill(theme, sources)
  let color = if paint.is_empty() &&
    sources.iter().find_first(item => item.node.name == "fontRef")
    is Some(reference) {
    color(theme, reference)
  } else {
    paint
  }
  for source in sources {
    for name in ["u", "strike", "baseline", "cap", "spc", "kumimoji"] {
      if source.node.attribute(name) is Some(value) &&
        !["none", "noStrike", "0", "false"].contains(value) {
        @failure.reject(
          "unsupported-text",
          "Unsupported text decoration: " + name,
        )
      }
    }
    for child in source.tree.children.get(source.node.id).unwrap_or([]) {
      if child.uri == drawing_uri &&
        ["effectLst", "effectDag", "highlight", "ln"].contains(child.name) {
        @failure.reject(
          "unsupported-text",
          "Unsupported text effect: " + child.name,
        )
      }
    }
  }
  {
    font: font_key(theme, family, text, bold, italic),
    underline: false,
    strike: false,
    highlight: "",
    script: "baseline",
    size,
    color: if color.is_empty() {
      "000000"
    } else {
      color
    },
  }
}

///|
fn spacing(
  sources : Array[Ref],
  name : String,
) -> ParagraphGap raise @failure.Failure {
  for source in children(sources, name) {
    if source.child("spcPts") is Some(points) {
      return Points(
        number(points.node.attribute("val").unwrap_or("0"), 0, 1000000) / 100,
      )
    }
    if source.child("spcPct") is Some(points) {
      return Percent(
        number(points.node.attribute("val").unwrap_or("0"), 0, 1000000) / 100000,
      )
    }
  }
  Points(0)
}

///|
fn read_text(
  theme : Theme,
  chain : Array[Ref],
  master : Tree,
  defaults : Ref?,
) -> (Array[TextParagraph], Body, String) raise @failure.Failure {
  let bodies = children(chain, "txBody", uri=presentation_uri)
  let properties = children(bodies, "bodyPr")
  let fit = for item in properties {
    if item.child("noAutofit") is Some(_) || item.child("spAutoFit") is Some(_) {
      break false
    }
    if item.child("normAutofit") is Some(_) {
      break true
    }
  } nobreak {
    false
  }
  let body : Body = {
    left: number(attribute(properties, "lIns").unwrap_or("91440"), 0, 182880000) /
    12700,
    right: number(
      attribute(properties, "rIns").unwrap_or("91440"),
      0,
      182880000,
    ) /
    12700,
    top: number(attribute(properties, "tIns").unwrap_or("45720"), 0, 182880000) /
    12700,
    bottom: number(
      attribute(properties, "bIns").unwrap_or("45720"),
      0,
      182880000,
    ) /
    12700,
    anchor: attribute(properties, "anchor").unwrap_or("t"),
    wrap: attribute(properties, "wrap").unwrap_or("square") != "none",
    fit,
  }
  let mut reason = ""
  if !["t", "ctr", "b"].contains(body.anchor) ||
    !["horz"].contains(attribute(properties, "vert").unwrap_or("horz")) ||
    attribute(properties, "numCol").unwrap_or("1") != "1" ||
    !children(properties, "spAutoFit").is_empty() ||
    !children(properties, "prstTxWarp").is_empty() {
    reason = "Unsupported text frame direction, columns or autofit"
  }
  let paragraphs : Array[TextParagraph] = []
  guard bodies.get(0) is Some(current) &&
    current.tree.part == chain[0].tree.part else {
    return (paragraphs, body, reason)
  }
  let lists = children(bodies, "lstStyle")
  let ph = placeholder(chain[0])
  let kind = if ph
    .map(value => ["title", "ctrTitle"].contains(value.0))
    .unwrap_or(false) {
    "titleStyle"
  } else if ph
    .map(value => ["body", "subTitle", "obj"].contains(value.0))
    .unwrap_or(false) {
    "bodyStyle"
  } else {
    "otherStyle"
  }
  let master_styles = master
    .one(master.document.nodes()[0].id, "txStyles", uri=presentation_uri)
    .bind(node => master.one(node.id, kind, uri=presentation_uri))
    .map(node => { tree: master, node, })
  let font_ref = children(
    children(chain, "style", uri=presentation_uri),
    "fontRef",
  )
  let default_font = if attribute(font_ref, "idx") == Some("major") {
    "+mj-lt"
  } else {
    "+mn-lt"
  }
  let mut units = 0
  for paragraph in current.tree.all(current.node.id, "p") {
    if !paragraphs.is_empty() {
      units += 1
    }
    let source : Ref = { tree: current.tree, node: paragraph, }
    let own = source.child("pPr")
    let level = number(
      own.bind(item => item.node.attribute("lvl")).unwrap_or("0"),
      0,
      8,
    ).to_int()
    let styles = own.map(item => [item]).unwrap_or([])
    for item in lists {
      if item.child("lvl\{level + 1}pPr") is Some(value) {
        styles.push(value)
      }
      if item.child("defPPr") is Some(value) {
        styles.push(value)
      }
    }
    for item in [master_styles, defaults] {
      if item is Some(item) {
        if item.child("lvl\{level + 1}pPr") is Some(value) {
          styles.push(value)
        }
        if item.child("defPPr") is Some(value) {
          styles.push(value)
        }
      }
    }
    let run_defaults = children(styles, "defRPr")
    let align = match attribute(styles, "algn").unwrap_or("l") {
      "l" => "left"
      "ctr" => "center"
      "r" => "right"
      _ => {
        reason = "Unsupported paragraph alignment"
        "left"
      }
    }
    let mut bullet = ""
    for item in styles {
      if item.child("buNone") is Some(_) {
        break
      }
      if item.child("buChar") is Some(value) {
        bullet = value.node.attribute("char").unwrap_or("")
        break
      }
      if item.child("buAutoNum") is Some(_) {
        reason = "Automatic numbering is unsupported"
        break
      }
      if item.child("buBlip") is Some(_) {
        reason = "Picture bullets are unsupported"
        break
      }
    }
    let mut line : @layout.LineSpacing = Auto(240)
    for item in children(styles, "lnSpc") {
      if item.child("spcPts") is Some(value) {
        line = Exact(
          number(value.node.attribute("val").unwrap_or("0"), 1, 1000000) / 5,
        )
        break
      }
      if item.child("spcPct") is Some(value) {
        line = Auto(
          number(value.node.attribute("val").unwrap_or("100000"), 1, 1000000) *
          240 /
          100000,
        )
        break
      }
    }
    let runs : Array[TextRun] = []
    for node in current.tree.children.get(paragraph.id).unwrap_or([]) {
      if node.uri != drawing_uri {
        reason = "Unknown text frame content"
        continue
      }
      if ["pPr", "endParaRPr"].contains(node.name) {
        continue
      }
      let item : Ref = { tree: current.tree, node, }
      let text = if node.name == "br" {
        "\u2028"
      } else if ["r", "fld"].contains(node.name) {
        item.child("t").map(item => item.node.text).unwrap_or("")
      } else {
        reason = "Unsupported text node: " + node.name
        ""
      }
      if node.name == "fld" {
        reason = "Fields are read-only"
      }
      let style_sources = item.child("rPr").map(item => [item]).unwrap_or([])
      style_sources.append(run_defaults)
      style_sources.append(font_ref)
      runs.push({
        source: Some(item),
        text,
        parts: styled_text(theme, style_sources, text, default_font),
      })
      units += text.length()
    }
    if runs.is_empty() {
      let style_sources = source
        .child("endParaRPr")
        .map(item => [item])
        .unwrap_or([])
      style_sources.append(run_defaults)
      style_sources.append(font_ref)
      runs.push({
        source: None,
        text: "",
        parts: styled_text(theme, style_sources, "", default_font),
      })
    }
    guard runs.iter().fold(init=0, (sum, run) => sum + run.text.length()) <=
      4096 &&
      units <= 32767 &&
      paragraphs.length() < 256 else {
      @failure.reject("limit-exceeded", "Text frame exceeds budget")
    }
    paragraphs.push({
      source,
      runs,
      align,
      bullet,
      bullet_style: if bullet.is_empty() {
        runs[0].style()
      } else {
        bullet_style(theme, styles, bullet, runs[0].style())
      },
      spacing: line,
      before: spacing(styles, "spcBef"),
      after: spacing(styles, "spcAft"),
      left: number(attribute(styles, "marL").unwrap_or("0"), 0, 182880000) /
      12700,
      right: number(attribute(styles, "marR").unwrap_or("0"), 0, 182880000) /
      12700,
      first: number(
        attribute(styles, "indent").unwrap_or("0"),
        -182880000,
        182880000,
      ) /
      12700,
    })
  }
  (paragraphs, body, reason)
}
