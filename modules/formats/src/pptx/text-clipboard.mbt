///|
let text_fragment_uri = "urn:open-document:pptx:text:1"

///|
fn clipboard_run_style(style : @layout.TextStyle) -> TextFormat {
  let font = style.font.split("|").to_array()
  TextFormat::new(
    font=font[0].to_owned(),
    size=style.size,
    spacing=style.spacing,
    bold=font.contains("bold"),
    italic=font.contains("italic"),
    color=style.color,
    underline=style.underline,
    strike=style.strike,
    highlight=style.highlight,
    script=style.script,
  )
}

///|
fn Session::clipboard_paragraph_piece(
  self : Session,
  paragraph : TextParagraph,
  start : Int,
  end : Int,
  links : ReadOnlyArray[@opc.Relationship],
  destinations : Set[String],
) -> String raise @failure.Failure {
  let output = StringBuilder()
  let mut cursor = 0
  for run in paragraph.runs {
    let limit = cursor + run.text.length()
    if start < limit && end > cursor {
      // shortcut: atomic text uses plain text until native fields and equations can be transferred.
      guard run.math is None &&
        run.date_field is None &&
        run.source.map(source => source.node.name != "fld").unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Rich text fields and equations require native clipboard support",
        )
      }
      let properties = run.source.bind(source => source.child("rPr"))
      let hyperlink = self.clipboard_text_link(properties, links, destinations) catch {
        @failure.Failure(code="limit-exceeded", ..) as error => raise error
        @failure.Failure(message~, ..) =>
          @failure.reject("protected-content", message)
      }
      if properties is Some(properties) {
        let pending = [properties.node]
        for index = 0; index < pending.length(); index = index + 1 {
          let node = pending[index]
          if node.uri == drawing_uri && node.name == "hlinkClick" {
            continue
          }
          guard !node.attributes.any(a => a.uri == relationship_uri) &&
            node.name != "hlinkMouseOver" &&
            (
              node.name != "alpha" ||
              (
                properties.tree.nodes[properties.tree.nodes[node.parent].parent].name ==
                "highlight" &&
                node.attribute("val") == Some("0")
              )
            ) else {
            @failure.reject(
              "protected-content", "Rich text hover links and transparency require clipboard support",
            )
          }
          pending.append(properties.tree.children.get(node.id).unwrap_or([]))
        }
      }
      let mut offset = cursor
      for (style, text) in run.parts {
        let a = (start - offset).max(0)
        let b = (end - offset).min(text.length())
        if a < b {
          let properties = formatted_properties(
            None,
            "rPr",
            Some(clipboard_run_style(style)),
            hyperlink~,
          )
          output.write_string(
            generated_text(text[a:b].to_owned(), "a:", properties),
          )
        }
        offset += text.length()
      }
    }
    cursor = limit
  }
  output.to_string()
}

///|
fn clipboard_paragraph_properties(
  paragraph : TextParagraph,
  properties~ : Ref? = None,
) -> String raise @failure.Failure {
  fn gap(value : ParagraphGap) -> TextSpacing {
    match value {
      Points(value) => { unit: "point", value, }
      Percent(value) => { unit: "percent", value: value * 100, }
    }
  }
  let format = ParagraphFormat::new(
    left=paragraph.left,
    right=paragraph.right,
    first=paragraph.first,
    before=gap(paragraph.before),
    after=gap(paragraph.after),
    line=match paragraph.spacing {
      Auto(value) => { unit: "percent", value: value * 100 / 240, }
      Exact(value) | AtLeast(value) => { unit: "point", value: value / 20, }
    },
    list=paragraph.list,
    rtl=paragraph.rtl,
    list_font=Some(
      paragraph.bullet_style.font.split("|").head().unwrap().to_owned(),
    ),
    list_size=Some(paragraph.bullet_size),
    list_color=Some(paragraph.bullet_style.color),
    tabs=Some(paragraph.tabs),
    default_tab=Some(paragraph.default_tab),
  )
  let markup = paragraph_markup(
    paragraph,
    properties,
    Some(format),
    style=true,
    alignment=Some(paragraph.align),
  )
  if properties.bind(p => p.node.attribute("lvl")) is Some(_) {
    markup
  } else {
    let qualified = properties.map(p => p.node.qualified).unwrap_or("a:pPr")
    markup.replace(
      old="<" + qualified,
      new="<" + qualified + " lvl='\{paragraph.level}'",
    )
  }
}

///|
fn Session::capture_text_fragment(
  self : Session,
) -> String raise @failure.Failure {
  let object = self.current().object(self.selection.object)
  guard object.text_reason.is_empty() else {
    @failure.reject("protected-content", object.text_reason)
  }
  if object.table is Some(table) && table.range(self.selection).multiple() {
    @failure.reject(
      "protected-content", "Rich multi-cell clipboard requires a cell fragment",
    )
  }
  let a = self.selection.anchor.min(self.selection.focus)
  let b = self.selection.anchor.max(self.selection.focus)
  let (first, start) = paragraph_location(object, a)
  let (last, end) = paragraph_location(object, b)
  guard last - first < 256 else {
    @failure.reject(
      "limit-exceeded", "Presentation text clipboard exceeds 256 paragraphs",
    )
  }
  let output = StringBuilder()
  let links = self.relationships()
  let destinations : Set[String] = Set([])
  output.write_string(
    "<od:fragment xmlns:od='\{text_fragment_uri}' xmlns:a='\{drawing_uri}'>",
  )
  for index in first..<=last {
    let paragraph = object.paragraphs[index]
    let content = self.clipboard_paragraph_piece(
      paragraph,
      if index == first {
        start
      } else {
        0
      },
      if index == last {
        end
      } else {
        paragraph_length(paragraph)
      },
      links,
      destinations,
    )
    let properties = clipboard_paragraph_properties(paragraph)
    let ending = formatted_properties(
      None,
      "endParaRPr",
      Some(clipboard_run_style(paragraph.runs.last().unwrap().style())),
    )
    output.write_string("<a:p>\{properties}\{content}\{ending}</a:p>")
  }
  output.write_string("</od:fragment>")
  let fragment = output.to_string()
  guard fragment.length() <= 1048576 else {
    @failure.reject(
      "limit-exceeded", "Presentation text clipboard exceeds 1Mi units",
    )
  }
  fragment
}

///|
/// Captures displayed text and an independent native fragment when the selected content supports it.
pub fn Session::copy(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  if self.selection.mode == "object" {
    return self.copy_object_fragment(revision)
  }
  let text = self.copy_text(revision)
  let (fragment, reason) = (Json(self.capture_text_fragment()), "") catch {
    @failure.Failure(code="protected-content", message~, ..) =>
      (Json::null(), message)
    error => raise error
  }
  { "text": text, "fragment": fragment, "reason": reason }
}
