///|
fn Session::clipboard_table_style(
  self : Session,
  object : Object,
  resources : Map[String, Json],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let table = object.table.unwrap()
  let tree = object.source.tree
  let layers = [tree]
  let parent = if tree.document.nodes()[0].name == "sld" {
    let path = slide_layout(self.opc, tree.part, self.parts).unwrap()
    let layout = load_tree(self.opc, self.cache, path, parts=self.parts)
    layers.push(layout)
    layout
  } else {
    tree
  }
  let master = if parent.document.nodes()[0].name == "sldMaster" {
    parent
  } else {
    let path = relation(self.opc, parent.part, "slideMaster", parts=self.parts).unwrap()
    load_tree(self.opc, self.cache, path, parts=self.parts)
  }
  if master.part != parent.part {
    layers.push(master)
  }
  let path = relation(self.opc, master.part, "theme", parts=self.parts).unwrap()
  let theme = read_theme(
    load_tree(self.opc, self.cache, path, parts=self.parts),
    layers,
  )
  let regions = table_style_parts(table.styles, table.style.id)
  let content = StringBuilder()
  for name in table_style_regions {
    guard regions.get(name) is Some(region) else { continue }
    let original = source_xml(region.source)
    guard !original.contains("<!--") && !original.contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated table styles require portable copying support",
      )
    }
    content <+ "<a:\{name}>"
    if region.text is Some(text) {
      let attrs = ["b", "i"]
        .filter_map(name => {
          text.node.attribute(name).map(value => " \{name}='\{value}'")
        })
        .join("")
      content <+ "<a:tcTxStyle\{attrs}>"
      let fonts = StringBuilder()
      for (kind, sample) in [("latin", "a"), ("ea", "中"), ("cs", "א")] {
        if text.child(kind) is Some(_) {
          let family = text_style(theme, [text], sample, "Arial").font
            .split("|")
            .head()
            .unwrap()
            .to_owned()
          fonts <+ "<a:\{kind} typeface='\{xml_attribute(family)}'/>"
        }
      }
      if !fonts.is_empty() {
        content <+ "<a:font>\{fonts}</a:font>"
      }
      if paint_fill(text) is Some(_) {
        let (color, alpha) = fill_rgba(theme, [text])
        guard alpha == 1 else {
          @failure.reject(
            "protected-content", "Transparent table text requires portable copying support",
          )
        }
        content <+ "<a:srgbClr val='\{color}'/>"
      }
      content <+ "</a:tcTxStyle>"
    }
    if region.source.child("tcStyle") is Some(style) {
      content <+ "<a:tcStyle>"
      if style.child("tcBdr") is Some(borders) {
        content <+ "<a:tcBdr>"
        for edge in borders.tree.children.get(borders.node.id).unwrap_or([]) {
          let (color, width, dash) = table_style_border(theme, {
            tree: borders.tree,
            node: edge,
          })
          content <+
            "<a:\{edge.name}><a:ln w='\{((width*12700).round().to_int64()).max(1L)}'>\{paint_markup(if color.is_empty() {None} else {Some(color)})}<a:prstDash val='\{dash}'/></a:ln></a:\{edge.name}>"
        }
        content <+ "</a:tcBdr>"
      }
      if table_style_fill(theme, [region]) is Some((color, alpha)) {
        content <+
          "<a:fill>\{paint_markup(if color.is_empty() {None} else {Some(color)},opacity=alpha)}</a:fill>"
      }
      content <+ "</a:tcStyle>"
    }
    content <+ "</a:\{name}>"
  }
  let key = "tableStyle\n" + content.to_string()
  let id = if resources.get(key) is Some({ "id": String(id), .. }) {
    id
  } else {
    guard resources.length() < 256 else {
      @failure.reject(
        "limit-exceeded", "Object clipboard exceeds 256 resources",
      )
    }
    let id = "ODCLIP" + resources.length().to_string()
    resources[key] = {
      "id": id,
      "kind": "tableStyle",
      "value": "<a:tblStyle xmlns:a='\{drawing_uri}' styleId='\{id}' styleName='Clipboard source'>\{content}</a:tblStyle>",
    }
    id
  }
  let source = object.source
    .child("graphic")
    .unwrap()
    .child("graphicData")
    .unwrap()
    .child("tbl")
    .unwrap()
  let properties = source.child("tblPr")
  if properties is Some(properties) {
    let xml = source_xml(properties)
    guard !xml.contains("<!--") && !xml.contains("<?") else {
      @failure.reject(
        "protected-content", "Annotated table properties require portable copying support",
      )
    }
  }
  let attrs = properties
    .map(p => {
      p.node.attributes
      .map(a => " \{a.name}='\{xml_attribute(a.value)}'")
      .join("")
    })
    .unwrap_or("")
  let markup = "<a:tblPr xmlns:a='\{drawing_uri}'\{attrs}>\{paint_markup(if table.fill.is_empty(){None}else{Some(table.fill)},opacity=table.alpha)}<a:tableStyleId>\{id}</a:tableStyleId></a:tblPr>"
  let changes = [
    paint_child_change(source, properties.map(p => p.node), markup, [
      "tblGrid", "tr",
    ]),
  ]
  for row in table.rows {
    for cell in row.cells {
      changes.append(
        clipboard_body_style(
          cell.source,
          cell.body,
          cell.paragraphs,
          drawing_uri,
        ),
      )
      let props = cell.source.child("tcPr")
      let borders = StringBuilder()
      if props is Some(props) {
        let xml = source_xml(props)
        guard !xml.contains("<!--") && !xml.contains("<?") else {
          @failure.reject(
            "protected-content", "Annotated cell properties require portable copying support",
          )
        }
        // Keep direct border precedence; style borders retain their native regional priorities.
        for side, name in ["lnL", "lnT", "lnR", "lnB"] {
          if props.child(name) is Some(_) {
            let (color, width, dash) = cell.borders[side]
            borders <+
              "<a:\{name} w='\{((width*12700).round().to_int64()).max(1L)}'>\{paint_markup(if color.is_empty(){None}else{Some(color)})}<a:prstDash val='\{dash}'/></a:\{name}>"
          }
        }
      }
      let attrs = props
        .map(p => {
          p.node.attributes
          .map(a => " \{a.name}='\{xml_attribute(a.value)}'")
          .join("")
        })
        .unwrap_or("")
      let markup = "<a:tcPr xmlns:a='\{drawing_uri}'\{attrs}>\{borders}\{paint_markup(if cell.fill.is_empty(){None}else{Some(cell.fill)},opacity=cell.alpha)}</a:tcPr>"
      changes.push(
        paint_child_change(cell.source, props.map(p => p.node), markup, []),
      )
    }
  }
  changes
}
