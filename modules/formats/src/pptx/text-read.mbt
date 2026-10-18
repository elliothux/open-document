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
  let underline = attribute(sources, "u").unwrap_or("none")
  let strike = attribute(sources, "strike").unwrap_or("noStrike")
  // ONLYOFFICE interprets DrawingML baseline by sign, using shared script metrics.
  let baseline = number(
    attribute(sources, "baseline").unwrap_or("0"),
    -2147483648,
    2147483647,
  )
  guard ["none", "sng", "0", "false"].contains(underline) &&
    ["noStrike", "sngStrike", "0", "false"].contains(strike) else {
    @failure.reject("unsupported-text", "Unsupported underline or strike style")
  }
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
    for name in ["cap", "spc", "kumimoji"] {
      if source.node.attribute(name) is Some(value) &&
        !["none", "noStrike", "0", "false"].contains(value) {
        @failure.reject(
          "unsupported-text",
          "Unsupported text decoration: " + name,
        )
      }
    }
    for child in source.tree.children.get(source.node.id).unwrap_or([]) {
      if child.uri == drawing_uri && ["uFillTx", "uLnTx"].contains(child.name) {
        guard child.attributes.is_empty() &&
          child.text.trim().is_empty() &&
          source.tree.children.get(child.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "unsupported-text", "Extended underline settings are protected",
          )
        }
      }
      if child.uri == drawing_uri &&
        ["effectLst", "effectDag", "ln", "uLn", "uFill"].contains(child.name) {
        @failure.reject(
          "unsupported-text",
          "Unsupported text effect: " + child.name,
        )
      }
    }
  }
  {
    font: font_key(theme, family, text, bold, italic),
    underline: underline == "sng" ||
    sources.any(source => {
      ["rPr", "endParaRPr"].contains(source.node.name) &&
      source.child("hlinkClick") is Some(_)
    }),
    strike: strike == "sngStrike",
    highlight: text_highlight(theme, sources),
    script: if baseline > 0 {
      "superscript"
    } else if baseline < 0 {
      "subscript"
    } else {
      "baseline"
    },
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
        number(points.node.attribute("val").unwrap_or("0"), 0, 158400) / 100,
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
  page_number : String,
  date_time : DateTime?,
  run_styles~ : Array[Ref] = [],
) -> (Array[TextParagraph], Body, String) raise @failure.Failure {
  let bodies = children(
    chain,
    "txBody",
    uri=if chain[0].node.name == "tc" { drawing_uri } else { presentation_uri },
  )
  let properties = children(bodies, "bodyPr")
  let fit = for item in properties {
    if item.child("noAutofit") is Some(_) {
      break "none"
    }
    if item.child("spAutoFit") is Some(_) {
      break "resize"
    }
    if item.child("normAutofit") is Some(_) {
      break "shrink"
    }
  } nobreak {
    "none"
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
  for item in properties {
    let fit_reason = text_fit_reason(item)
    if !fit_reason.is_empty() {
      reason = fit_reason
      break
    }
  }
  if !["t", "ctr", "b"].contains(body.anchor) ||
    !["horz"].contains(attribute(properties, "vert").unwrap_or("horz")) ||
    attribute(properties, "numCol").unwrap_or("1") != "1" ||
    !children(properties, "prstTxWarp").is_empty() {
    reason = "Unsupported text frame direction or columns"
  }
  if ["1", "true"].contains(attribute(properties, "upright").unwrap_or("0")) {
    reason = "Upright text requires independent frame resize geometry"
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
    let local_count = styles.length()
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
    let run_defaults = children(styles[:local_count].to_owned(), "defRPr")
    run_defaults.append(run_styles)
    run_defaults.append(children(styles[local_count:].to_owned(), "defRPr"))
    let rtl = match attribute(styles, "rtl") {
      None | Some("0" | "false") => false
      Some("1" | "true") => true
      _ => @failure.reject("unsupported-text", "Invalid paragraph direction")
    }
    let align = match
      attribute(styles, "algn").unwrap_or(if rtl { "r" } else { "l" }) {
      "l" => "left"
      "ctr" => "center"
      "r" => "right"
      "just" => "justify"
      _ => {
        reason = "Unsupported paragraph alignment"
        "left"
      }
    }
    let list = read_list(styles)
    let bullet = list_label(list, level, paragraphs)
    let mut line : @layout.LineSpacing = Auto(240)
    for item in children(styles, "lnSpc") {
      if item.child("spcPts") is Some(value) {
        line = Exact(
          number(value.node.attribute("val").unwrap_or("0"), 1, 158400) / 5,
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
      let style_sources = item.child("rPr").map(item => [item]).unwrap_or([])
      style_sources.append(run_defaults)
      style_sources.append(font_ref)
      let date_text = date_time.bind(time => {
        presentation_date_text(item, style_sources, time)
      })
      let text = if node.name == "br" {
        "\u2028"
      } else if slide_number_field(item) {
        page_number
      } else if date_text is Some(text) {
        text
      } else if ["r", "fld"].contains(node.name) {
        item.child("t").map(item => item.node.text).unwrap_or("")
      } else {
        reason = "Unsupported text node: " + node.name
        ""
      }
      if node.name == "fld" {
        if slide_number_field(item) {
          if reason.is_empty() {
            reason = slide_number_text_reason
          }
        } else if date_text is Some(_) {
          if reason.is_empty() {
            reason = date_field_text_reason
          }
        } else {
          reason = "Fields are read-only"
        }
      }
      runs.push({
        source: Some(item),
        date_field: date_text.bind(_ => {
          presentation_date_format(item, style_sources)
        }),
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
        date_field: None,
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
      rtl,
      bullet,
      list,
      level,
      bullet_size: bullet_size(styles),
      bullet_style: bullet_style(theme, styles, bullet, runs[0].style()),
      spacing: line,
      before: spacing(styles, "spcBef"),
      after: spacing(styles, "spcAft"),
      left: number(attribute(styles, "marL").unwrap_or("0"), 0, 51206400) /
      12700,
      right: number(attribute(styles, "marR").unwrap_or("0"), 0, 51206400) /
      12700,
      first: number(
        attribute(styles, "indent").unwrap_or("0"),
        -51206400,
        51206400,
      ) /
      12700,
    })
  }
  (paragraphs, body, reason)
}

///|
fn slide_font_keys(
  slides : Array[Slide],
) -> Array[String] raise @failure.Failure {
  let fonts : Array[String] = []
  for slide in slides {
    for object in slide.objects {
      for paragraph in object.paragraphs {
        if !paragraph.bullet.is_empty() &&
          !fonts.contains(paragraph.bullet_style.font) {
          fonts.push(paragraph.bullet_style.font)
        }
        for run in paragraph.runs {
          for (style, _) in run.parts {
            if !fonts.contains(style.font) {
              fonts.push(style.font)
            }
          }
        }
        guard fonts.length() <= 256 else {
          @failure.reject("limit-exceeded", "Font keys exceed 256")
        }
      }
    }
  }
  fonts
}
