///|
fn text_source_color(
  theme : Theme,
  sources : Array[Ref],
) -> String raise @failure.Failure {
  for source in sources {
    let value = if source.node.name == "fontRef" {
      if source.tree.children.get(source.node.id).unwrap_or([]).is_empty() {
        ""
      } else {
        color(theme, source)
      }
    } else {
      fill(theme, [source])
    }
    if !value.is_empty() {
      break value
    }
  } nobreak {
    "000000"
  }
}

///|
fn text_style(
  theme : Theme,
  sources : Array[Ref],
  text : String,
  default_font : String,
) -> @layout.TextStyle raise @failure.Failure {
  // ONLYOFFICE imports DrawingML font sizes at half-point precision.
  let size = (number(attribute(sources, "sz").unwrap_or("1800"), 100, 102400) /
    50).round() /
    2
  let spacing = number(
    attribute(sources, "spc").unwrap_or("0"),
    -158400,
    158400,
  )
  guard spacing.floor() == spacing else {
    @failure.reject(
      "unsupported-text", "Character spacing requires integer hundredths of a point",
    )
  }
  let bold = attribute(sources, "b")
    .map(value => value == "1" || value == "true")
    .unwrap_or(false)
  let italic = attribute(sources, "i")
    .map(value => value == "1" || value == "true")
    .unwrap_or(false)
  let underline = attribute(sources, "u").unwrap_or("none")
  let strike = attribute(sources, "strike").unwrap_or("noStrike")
  let caps = attribute(sources, "cap").unwrap_or("none")
  guard ["none", "all"].contains(caps) else {
    @failure.reject("unsupported-text", "Unsupported text decoration: cap")
  }
  // ONLYOFFICE interprets DrawingML baseline by sign, using shared script metrics.
  let baseline = number(
    attribute(sources, "baseline").unwrap_or("0"),
    -2147483648,
    2147483647,
  )
  guard ["none", "sng", "heavy", "0", "false"].contains(underline) &&
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
  let family = for source in sources {
    // A shape's theme font reference overrides inherited character fonts.
    if source.node.name == "fontRef" {
      let kind = if source.node.attribute("idx") == Some("major") {
        "+mj-"
      } else {
        "+mn-"
      }
      break kind + (if font_kind == "latin" { "lt" } else { font_kind })
    }
    if source.child(font_kind) is Some(font) &&
      font.node.attribute("typeface") is Some(value) &&
      !value.is_empty() {
      break value
    }
  } nobreak {
    attribute(children(sources, "latin"), "typeface").unwrap_or(default_font)
  }
  let source_color = text_source_color(theme, sources)
  for source in sources {
    if source.node.attribute("cap") is Some(value) &&
      !["none", "all", "small"].contains(value) {
      @failure.reject("unsupported-text", "Unsupported text decoration: cap")
    }
    // ONLYOFFICE keeps drawing text when kumimoji is set.
    if source.node.attribute("kumimoji") is Some(value) &&
      !["0", "1", "false", "true"].contains(value) {
      @failure.reject("unsupported-text", "Invalid kumimoji flag")
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
      if child.uri == drawing_uri && child.name == "uFill" {
        let reference = { tree: source.tree, node: child, }
        guard child.attributes.is_empty() &&
          child.text.trim().is_empty() &&
          source.tree.children.get(child.id).unwrap_or([]).length() == 1 &&
          !source_xml(reference).contains("<!--") &&
          !source_xml(reference).contains("<?") &&
          paint_fill(reference) is Some({ name: "solidFill", .. }) else {
          @failure.reject("unsupported-text", "Unsupported underline fill")
        }
        // ONLYOFFICE skips the uFill record and paints with the text color.
        ignore(fill_rgba(theme, [reference]))
      }
      if child.uri == drawing_uri &&
        ["effectLst", "effectDag", "ln", "uLn"].contains(child.name) {
        check_text_effect(theme, { tree: source.tree, node: child, })
      }
    }
  }
  let hyperlink = sources.any(source => {
    ["rPr", "endParaRPr"].contains(source.node.name) &&
    source.child("hlinkClick") is Some(_)
  })
  let color = if hyperlink {
    let key = theme.mapping.get("hlink").unwrap_or("hlink")
    guard theme.colors.get(key) is Some(source) else {
      @failure.reject("unsupported-style", "Unknown theme color: hlink")
    }
    // Native click links paint with the mapped theme color while retaining direct source fills.
    color(theme, source)
  } else {
    source_color
  }
  {
    font: font_key(theme, family, text, bold, italic),
    // ONLYOFFICE imports DrawingML heavy into the same boolean underline as sng.
    underline: ["sng", "heavy"].contains(underline) || hyperlink,
    strike: strike == "sngStrike",
    highlight: text_highlight(theme, sources),
    spacing: spacing / 100,
    kerning: "none",
    fontLeading: true,
    caps: caps == "all",
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
fn text_overflow_clip(
  sources : Array[Ref],
  name : String,
) -> Bool raise @failure.Failure {
  match attribute(sources, name).unwrap_or("overflow") {
    "overflow" => false
    "clip" => true
    _ =>
      @failure.reject("unsupported-text", "Unsupported text overflow: " + name)
  }
}

///|
fn no_text_warp(properties : Array[Ref]) -> Bool raise @failure.Failure {
  guard children(properties, "prstTxWarp").get(0) is Some(warp) else {
    return true
  }
  let lists = warp.tree.children.get(warp.node.id).unwrap_or([])
  warp.node.attribute("prst") == Some("textNoShape") &&
  warp.node.attributes.all(a => a.uri.is_empty() && a.name == "prst") &&
  warp.node.text.trim().is_empty() &&
  lists.length() <= 1 &&
  lists.all(list => {
    list.uri == drawing_uri &&
    list.name == "avLst" &&
    list.attributes.is_empty() &&
    list.text.trim().is_empty() &&
    warp.tree.children.get(list.id).unwrap_or([]).is_empty()
  })
}

///|
fn read_text(
  opc : @opc.Package,
  theme : Theme,
  chain : Array[Ref],
  master : Tree,
  defaults : Ref?,
  page_number : String,
  date_time : DateTime?,
  parts : Map[String, @xml.Document],
  media : Map[String, Bytes],
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
  let normal_fit = if fit == "shrink" {
    children(properties, "normAutofit").get(0)
  } else {
    None
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
    fontScale: normal_fit
    .bind(item => item.node.attribute("fontScale"))
    .map(value => number(value, 1000, 100000) / 100000),
    lineSpaceReduction: normal_fit
    .map(item => {
      number(item.node.attribute("lnSpcReduction").unwrap_or("0"), 0, 20000) /
      100000
    })
    .unwrap_or(0),
    firstLastSpacing: match
      attribute(properties, "spcFirstLastPara").unwrap_or("0") {
      "1" | "true" => true
      "0" | "false" => false
      _ =>
        @failure.reject("malformed-pptx", "Invalid paragraph end spacing flag")
    },
    clipHorizontal: text_overflow_clip(properties, "horzOverflow"),
    clipVertical: text_overflow_clip(properties, "vertOverflow"),
    direction: attribute(properties, "vert").unwrap_or("horz"),
    upright: match attribute(properties, "upright").unwrap_or("0") {
      "1" | "true" => true
      "0" | "false" => false
      _ => @failure.reject("malformed-pptx", "Invalid upright text flag")
    },
    rotation: number(
      attribute(properties, "rot").unwrap_or("0"),
      -2147483648,
      2147483647,
    ) /
    60000,
    columns: number(attribute(properties, "numCol").unwrap_or("1"), 1, 16).to_int(),
    columnGap: number(
      attribute(properties, "spcCol").unwrap_or("0"),
      0,
      182880000,
    ) /
    12700,
    rtlColumns: match attribute(properties, "rtlCol").unwrap_or("0") {
      "1" | "true" => true
      "0" | "false" => false
      _ => @failure.reject("malformed-pptx", "Invalid text column direction")
    },
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
    !["horz", "vert", "vert270"].contains(body.direction) ||
    !no_text_warp(properties) {
    reason = "Unsupported text frame direction"
  }
  if chain[0].node.name == "tc" && (body.rotation != 0 || body.upright) {
    reason = "Independent table cell text orientation requires cell text matrices"
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
    // ONLYOFFICE gives presentation defaults priority for ordinary shapes only.
    let inherited = if ph is Some(_) || chain[0].node.name == "tc" {
      [master_styles, defaults]
    } else {
      [defaults, master_styles]
    }
    for item in inherited {
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
    run_defaults.append(font_ref)
    run_defaults.append(children(styles[local_count:].to_owned(), "defRPr"))
    let runs : Array[TextRun] = []
    let mut math_align : String? = None
    for node in current.tree.children.get(paragraph.id).unwrap_or([]) {
      let item : Ref = { tree: current.tree, node, }
      if item.math_source() is Some((source, align)) {
        let formula = source.read_math(
          text_style(theme, run_defaults, "0", default_font),
        )
        runs.push({
          source: Some(item),
          date_field: None,
          math: Some(
            @layout.MathFormula::new(
              formula.expression,
              formula.style,
              display=align is Some(_),
            ),
          ),
          text: "\ufffc",
          parts: [(formula.style, "\ufffc")],
        })
        units += formula.expression.linear_text().length()
        if align is Some(_) {
          math_align = align
        }
        if reason.is_empty() {
          reason = math_text_reason
        }
        continue
      }
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
        math: None,
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
      runs.push({
        source: None,
        math: None,
        date_field: None,
        text: "",
        parts: styled_text(theme, style_sources, "", default_font),
      })
    }
    guard runs.iter().fold(init=0, (sum, run) => sum + run.text.length()) <=
      TextParagraphUnits &&
      units <= TextFrameUnits &&
      paragraphs.length() < TextFrameParagraphs else {
      @failure.reject("limit-exceeded", "Text frame exceeds budget")
    }
    let (resolved, diagnostic) = read_paragraph_style(
      opc, source, own, styles, level, runs, run_defaults, theme, paragraphs, parts,
      media,
    )
    if !diagnostic.is_empty() {
      reason = diagnostic
    }
    if math_align is Some(align) {
      guard runs.length() == 1 else {
        @failure.reject(
          "unsupported-math", "Display math requires its own paragraph",
        )
      }
      paragraphs.push({ ..resolved, align, })
    } else {
      paragraphs.push(resolved)
    }
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
      if object.metafile is Some(file) {
        for command in file.commands {
          if command is @layout.Label(text) && !fonts.contains(text.font) {
            fonts.push(text.font)
          }
        }
      }
      if object.chart is Some(_) && !fonts.contains("Arial") {
        fonts.push("Arial")
      }
      guard fonts.length() <= 256 else {
        @failure.reject("limit-exceeded", "Font keys exceed 256")
      }
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
