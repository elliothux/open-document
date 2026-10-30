///|
priv struct MarkupList {
  instance : Int32
  level : Int32
  value : Int32
  format : String
  native : Bool
  markdown : Bool
  rtl : Bool
}

///|
fn MarkupList::tag(self : MarkupList) -> String {
  if self.format == "bullet" {
    "ul"
  } else {
    "ol"
  }
}

///|
fn MarkupList::css(self : MarkupList) -> String {
  if !self.native {
    return "none"
  }
  match self.format {
    "bullet" => "disc"
    "decimalZero" => "decimal-leading-zero"
    "lowerLetter" => "lower-alpha"
    "upperLetter" => "upper-alpha"
    "lowerRoman" => "lower-roman"
    "upperRoman" => "upper-roman"
    _ => "decimal"
  }
}

///|
fn Session::markup_lists(
  self : Session,
  tree : WordTree,
  styles : Styles,
  flow : @layout.Flow,
) -> Map[Int32, MarkupList] raise @failure.Failure {
  let paragraphs = flow.paragraphs.copy()
  paragraphs.append(flow.tables.map(table => table.paragraphs()).flatten())
  let models = Map::from_array(paragraphs.map(p => (p.id, p)))
  let lists : Map[Int32, MarkupList] = Map([])
  let counters : Map[Int32, NumberCounter] = Map([])
  let mut context : NumberingContext? = None
  for id in tree.order {
    guard models.get(id) is Some(paragraph) &&
      paragraph.marker is Some(marker) &&
      styles.numbering_reference(tree, id) is Some((instance, index)) else {
      continue
    }
    let numbers = context.unwrap_or_else(() => {
      let numbers = self.numbering_context()
      context = Some(numbers)
      numbers
    })
    let definition = numbers.definition(instance)
    let level = definition.levels[index]
    let counter = counters.get_or_init(definition.abstract_id, () => {
      values: Array::make(9, 0),
      seen: Map([]),
      previous: -1,
    })
    counter.advance(definition, instance, index)
    let bullet = level.format == "bullet"
    let simple = if bullet {
      level.pattern == "•"
    } else {
      level.pattern == "%" + (index + 1).to_string() + "."
    }
    // HTML counter styles use decimal fallback outside their defined alphabetic/Roman domain.
    let value = counter.values[index]
    let range = match level.format {
      "lowerLetter" | "upperLetter" => value > 0 && value <= 26
      "lowerRoman" | "upperRoman" => value > 0 && value <= 3999
      _ => true
    }
    let native = simple &&
      range &&
      level.suffix != "nothing" &&
      !marker.style.underline &&
      !marker.style.strike &&
      marker.style.highlight.is_empty() &&
      marker.style.spacing == 0 &&
      marker.style.script == "baseline"
    lists[id] = {
      instance,
      level: index,
      value,
      format: level.format,
      native,
      rtl: paragraph.rtl,
      markdown: native &&
      !paragraph.rtl &&
      (bullet || (level.format == "decimal" && value <= 999999999)),
    }
  }
  lists
}

///|
fn Session::markup_list_html(
  self : Session,
  tree : WordTree,
  styles : Styles,
  paragraphs : Array[@layout.Paragraph],
  output : MarkupOutput,
) -> Unit raise @failure.Failure {
  let stack : Array[(MarkupList, Double)] = []
  for paragraph in paragraphs {
    let list = output.lists[paragraph.id]
    while stack.last().map(frame => frame.0.level > list.level).unwrap_or(false) {
      let frame = stack.pop().unwrap()
      output.add("</li></" + frame.0.tag() + ">\n")
    }
    if stack.last() is Some((previous, _)) && previous.level == list.level {
      if previous.instance == list.instance &&
        previous.format == list.format &&
        previous.native == list.native &&
        previous.rtl == list.rtl {
        output.add("</li>\n")
      } else {
        ignore(stack.pop())
        output.add("</li></" + previous.tag() + ">\n")
      }
    }
    if stack.last().map(frame => frame.0.level != list.level).unwrap_or(true) {
      let left = stack.last().map(frame => frame.1).unwrap_or(0)
      output.add(
        "<" +
        list.tag() +
        " dir=\"" +
        (if list.rtl { "rtl" } else { "ltr" }) +
        "\" role=\"list\"" +
        (if list.tag() == "ol" {
          " start=\"" + list.value.to_string() + "\""
        } else {
          ""
        }) +
        " style=\"margin:0;padding-inline-start:" +
        (paragraph.left - left).max(0).to_string() +
        "pt;list-style-type:" +
        list.css() +
        "\">\n",
      )
      stack.push((list, paragraph.left))
    }
    let marker = paragraph.marker.unwrap()
    let family = marker.style.font.split("|").to_array()[0].to_owned()
    let css = "font-family:" +
      markup_css_string(family) +
      ";font-size:" +
      marker.style.size.to_string() +
      "pt;color:#" +
      marker.style.color +
      ";font-weight:" +
      (if marker.style.font.contains("|bold") { "bold" } else { "normal" }) +
      ";font-style:" +
      (if marker.style.font.contains("|italic") { "italic" } else { "normal" })
    output.add(
      "<li aria-level=\"" +
      (list.level + 1).to_string() +
      "\"" +
      (if list.tag() == "ol" {
        " value=\"" + list.value.to_string() + "\""
      } else {
        ""
      }) +
      " style=\"" +
      property_attribute(css) +
      "\">",
    )
    self.markup_paragraph(
      tree,
      styles,
      paragraph,
      output,
      html=true,
      listed=true,
    )
  }
  while stack.pop() is Some((list, _)) {
    output.add("</li></" + list.tag() + ">\n")
  }
  output.add("\n")
}

///|
fn Session::markup_list_markdown(
  self : Session,
  tree : WordTree,
  styles : Styles,
  paragraphs : Array[@layout.Paragraph],
  output : MarkupOutput,
) -> Unit raise @failure.Failure {
  let stack : Array[(Int32, Int32, Int32)] = []
  for paragraph in paragraphs {
    let list = output.lists[paragraph.id]
    while stack.last().map(frame => frame.0 > list.level).unwrap_or(false) {
      ignore(stack.pop())
    }
    let indent = if stack.last() is Some(frame) {
      if frame.0 == list.level {
        frame.1
      } else {
        frame.1 + frame.2
      }
    } else {
      0
    }
    let prefix = if list.tag() == "ul" {
      "- "
    } else {
      list.value.to_string() + ". "
    }
    if stack.last().map(frame => frame.0 == list.level).unwrap_or(false) {
      ignore(stack.pop())
    }
    stack.push((list.level, indent, prefix.length()))
    let paragraph_output = {
      ..output,
      builder: StringBuilder(),
      units: 0,
      limit: output.limit - output.units,
    }
    self.markup_paragraph(
      tree,
      styles,
      paragraph,
      paragraph_output,
      listed=true,
    )
    let text = paragraph_output.builder.to_string()
    let lines = text[:text.length() - 2].split("\n").to_array()
    for index, line in lines {
      output.add(
        " ".repeat(indent) +
        (if index == 0 { prefix } else { " ".repeat(prefix.length()) }) +
        line.to_owned() +
        "\n",
      )
    }
  }
  output.add("\n")
}

///|
fn Session::markup_paragraphs(
  self : Session,
  tree : WordTree,
  styles : Styles,
  paragraphs : Array[@layout.Paragraph],
  output : MarkupOutput,
  html~ : Bool = false,
) -> Unit raise @failure.Failure {
  let mut index = 0
  while index < paragraphs.length() {
    if !output.lists.contains(paragraphs[index].id) {
      let block = output.markdown &&
        !html &&
        paragraphs[index].spans.any(span => {
          span.drawing is Some({ content: @layout.TextBox(_, _), .. }) ||
          span.drawing is Some({ content: Math(_), .. }) ||
          span.drawing is Some({ content: Chart(_), .. })
        })
      if block {
        output.add(
          "<div style=\"background-color:#" + output.background + "\">\n",
        )
      }
      self.markup_paragraph(
        tree,
        styles,
        paragraphs[index],
        output,
        html=html || block,
      )
      if block {
        output.add("</div>\n\n")
      }
      index += 1
      continue
    }
    let start = index
    while index < paragraphs.length() &&
          output.lists.contains(paragraphs[index].id) {
      index += 1
    }
    let group = paragraphs[start:index].to_owned()
    let first = output.lists[group[0].id]
    let mut previous = -1
    let markdown = output.markdown &&
      !html &&
      group.all(p => {
        let list = output.lists[p.id]
        let nested = list.level <= previous + 1
        previous = list.level
        nested &&
        list.markdown &&
        list.instance == first.instance &&
        !p.spans.any(span => {
          span.drawing is Some({ content: @layout.TextBox(_, _), .. }) ||
          span.drawing is Some({ content: Math(_), .. }) ||
          span.drawing is Some({ content: Chart(_), .. })
        })
      })
    if markdown {
      self.markup_list_markdown(tree, styles, group, output)
    } else {
      if output.markdown && !html {
        output.add(
          "<div style=\"background-color:#" + output.background + "\">\n",
        )
      }
      self.markup_list_html(tree, styles, group, output)
      if output.markdown && !html {
        output.add("</div>\n\n")
      }
    }
  }
}
