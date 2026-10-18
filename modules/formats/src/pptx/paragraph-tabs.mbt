///|
pub(all) struct ParagraphTab {
  position : Double
  align : String
} derive(Eq, ToJson)

///|
pub extend ParagraphTab with Eq::{equal, not_equal}

///|
pub extend ParagraphTab with ToJson::{to_json}

///|
fn paragraph_tabs_check(
  tabs : Array[ParagraphTab],
) -> Unit raise @failure.Failure {
  guard tabs.length() <= 32 else {
    @failure.reject("limit-exceeded", "DrawingML allows at most 32 tab stops")
  }
  @layout.validate_tabs(
    tabs.map(t => { position: t.position, align: t.align, leader: "none", }),
  )
  guard tabs.all(t => t.align != "bar") else {
    @failure.reject("invalid-operation", "DrawingML does not support bar tabs")
  }
}

///|
fn read_paragraph_tabs(
  styles : Array[Ref],
) -> Array[ParagraphTab] raise @failure.Failure {
  let tabs : Array[ParagraphTab] = []
  for style in styles.rev() {
    if style.child("tabLst") is Some(list) {
      guard list.node.attributes.is_empty() && list.node.text.trim().is_empty() else {
        @failure.reject(
          "unsupported-text", "Unsupported tab list attributes or text",
        )
      }
      let nodes = list.tree.children.get(list.node.id).unwrap_or([])
      guard nodes.length() <= 32 else {
        @failure.reject("limit-exceeded", "Too many paragraph tabs")
      }
      for node in nodes {
        guard node.uri == drawing_uri &&
          node.name == "tab" &&
          node.attributes.all(a => {
            a.uri.is_empty() && ["pos", "algn"].contains(a.name)
          }) &&
          node.text.trim().is_empty() &&
          list.tree.children.get(node.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "unsupported-text", "Unsupported paragraph tab content",
          )
        }
        let align = match node.attribute("algn").unwrap_or("l") {
          "l" => "left"
          "ctr" => "center"
          "r" => "right"
          "dec" => "decimal"
          _ => @failure.reject("unsupported-text", "Unsupported tab alignment")
        }
        let tab : ParagraphTab = {
          position: number(node.attribute("pos").unwrap_or("0"), 0, 20116800) /
          12700,
          align,
        }
        if tabs.search_by(t => t.position == tab.position) is Some(index) {
          tabs[index] = tab
        } else {
          tabs.push(tab)
        }
      }
    }
  }
  tabs.sort_by((a, b) => a.position.compare(b.position))
  paragraph_tabs_check(tabs) catch {
    @failure.Failure(code="invalid-operation", ..) =>
      @failure.reject(
        "unsupported-text", "Paragraph tab positions require ordered twip precision",
      )
    error => raise error
  }
  tabs
}

///|
fn paragraph_tab_markup(
  paragraph : TextParagraph,
  format : ParagraphFormat,
  attrs : Map[String, String],
  changes : Map[String, String],
) -> Array[String] raise @failure.Failure {
  let properties = paragraph.source.child("pPr")
  let removed = []
  if format.default_tab is Some(value) {
    if value is Some(value) {
      if value != paragraph.default_tab {
        attrs["defTabSz"] = (value * 12700).round().to_int().to_string()
      }
    } else if properties.bind(p => p.node.attribute("defTabSz")) is Some(_) {
      removed.push("defTabSz")
    }
  }
  if format.tabs is Some(value) {
    if properties.bind(p => p.child("tabLst")) is Some(list) {
      guard !source_xml(list).contains("<!--") &&
        !source_xml(list).contains("<?") else {
        @failure.reject(
          "protected-content", "Retained tab list source prevents replacing tabs",
        )
      }
    }
    if value is Some(tabs) {
      guard paragraph.inherited_tabs.is_empty() || tabs == paragraph.tabs else {
        @failure.reject(
          "protected-content", "Inherited tab stops require style-level tab editing",
        )
      }
      if tabs != paragraph.tabs {
        changes["tabLst"] = "<a:tabLst xmlns:a=\"\{drawing_uri}\">" +
          tabs
          .map(t => {
            let align = match t.align {
              "center" => "ctr"
              "right" => "r"
              "decimal" => "dec"
              _ => "l"
            }
            "<a:tab pos=\"\{(t.position * 12700).round().to_int()}\" algn=\"\{align}\"/>"
          })
          .join("") +
          "</a:tabLst>"
      }
    } else if properties.bind(p => p.child("tabLst")) is Some(_) {
      changes["tabLst"] = ""
    }
  }
  removed
}
