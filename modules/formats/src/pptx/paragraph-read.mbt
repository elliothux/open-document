///|
fn read_paragraph_style(
  source : Ref,
  own : Ref?,
  styles : Array[Ref],
  level : Int,
  runs : Array[TextRun],
  theme : Theme,
  previous : Array[TextParagraph],
) -> (TextParagraph, String) raise @failure.Failure {
  let mut reason = ""
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
  let bullet = list_label(list, level, previous)
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
  let paragraph : TextParagraph = {
    source,
    runs,
    align,
    rtl,
    bullet,
    list,
    level,
    bullet_size: bullet_size(styles),
    tabs: read_paragraph_tabs(styles),
    inherited_tabs: read_paragraph_tabs(
      styles.filter(item => {
        own
        .map(p => p.tree.part != item.tree.part || p.node.id != item.node.id)
        .unwrap_or(true)
      }),
    ),
    default_tab: number(
      attribute(styles, "defTabSz").unwrap_or("914400"),
      0,
      20116800,
    ) /
    12700,
    bullet_style: bullet_style(
      theme,
      styles,
      bullet,
      runs[0].style(),
      numbered=list is Numbered(_, _),
    ),
    spacing: line,
    before: spacing(styles, "spcBef"),
    after: spacing(styles, "spcAft"),
    left: number(attribute(styles, "marL").unwrap_or("0"), 0, 51206400) / 12700,
    right: number(attribute(styles, "marR").unwrap_or("0"), 0, 51206400) / 12700,
    first: number(
      attribute(styles, "indent").unwrap_or("0"),
      -51206400,
      51206400,
    ) /
    12700,
  }
  (paragraph, reason)
}
