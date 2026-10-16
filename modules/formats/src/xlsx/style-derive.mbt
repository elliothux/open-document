///|
fn CellFormat::font_markup(
  self : CellFormat,
  tree : Tree,
  node : @xml.Node,
) -> String raise @failure.Failure {
  let document = style_fragment(tree, node)
  check_style_fragment(document)
  let changes : Array[(String, String)] = []
  let element = fn(name, value) raise @failure.Failure {
    "<od:\{name} xmlns:od=\"\{spreadsheet_uri}\" val=\"\{escaped_attribute(value)}\"/>"
  }
  if self.family is Some(value) {
    changes.append([("name", element("name", value)), ("scheme", "")])
  }
  if self.size is Some(value) {
    changes.push(("sz", element("sz", value.to_string())))
  }
  if self.bold is Some(value) {
    changes.push(("b", element("b", if value { "1" } else { "0" })))
  }
  if self.italic is Some(value) {
    changes.push(("i", element("i", if value { "1" } else { "0" })))
  }
  if self.color is Some(value) {
    changes.push(
      (
        "color",
        "<od:color xmlns:od=\"\{spreadsheet_uri}\" rgb=\"FF\{value.to_upper()}\"/>",
      ),
    )
  }
  style_children(document, changes).source()
}

///|
fn CellFormat::border_markup(
  self : CellFormat,
  tree : Tree,
  node : @xml.Node,
) -> String raise @failure.Failure {
  let document = style_fragment(tree, node)
  check_style_fragment(document)
  let changes : Array[(String, String)] = []
  for
    (name, patch) in [
      ("left", self.left),
      ("right", self.right),
      ("top", self.top),
      ("bottom", self.bottom),
    ] {
    if patch is Some(border) {
      changes.push(
        (
          name,
          if border.style == "none" {
            "<od:\{name} xmlns:od=\"\{spreadsheet_uri}\"/>"
          } else {
            "<od:\{name} xmlns:od=\"\{spreadsheet_uri}\" style=\"\{border.style}\"><od:color rgb=\"FF\{border.color.to_upper()}\"/></od:\{name}>"
          },
        ),
      )
    }
  }
  style_children(document, changes).source()
}

///|
fn CellFormat::xf_markup(
  self : CellFormat,
  tree : Tree,
  node : @xml.Node,
  font : Int,
  fill : Int,
  border : Int,
  number_format : Int?,
) -> String raise @failure.Failure {
  let original = style_fragment(tree, node)
  check_style_fragment(original)
  let children = Tree::new(original)
  let root = original.nodes()[0]
  guard children.children
    .get(root.id)
    .unwrap_or([])
    .all(node => ["alignment", "protection"].contains(node.name)) else {
    @failure.reject("protected-content", "Unknown cell format children")
  }
  let attributes = [
    ("fontId", font.to_string()),
    ("fillId", fill.to_string()),
    ("borderId", border.to_string()),
  ]
  if self.family is Some(_) ||
    self.size is Some(_) ||
    self.bold is Some(_) ||
    self.italic is Some(_) ||
    self.color is Some(_) {
    attributes.push(("applyFont", "1"))
  }
  if self.fill is Some(_) {
    attributes.push(("applyFill", "1"))
  }
  if [self.left, self.right, self.top, self.bottom].any(v => v is Some(_)) {
    attributes.push(("applyBorder", "1"))
  }
  if number_format is Some(id) {
    attributes.append([("numFmtId", id.to_string()), ("applyNumberFormat", "1")])
  }
  let mut document = metadata_attributes(original, root, attributes)
  let values : Array[(String, String)] = []
  if self.horizontal is Some(value) {
    values.push(("horizontal", value))
  }
  if self.vertical is Some(value) {
    values.push(("vertical", value))
  }
  if self.wrap is Some(value) {
    values.push(("wrapText", if value { "1" } else { "0" }))
  }
  if !values.is_empty() {
    let tree = Tree::new(document)
    let root = document.nodes()[0]
    let changes = if tree.one(root.id, "alignment") is Some(alignment) {
      metadata_changes(alignment, values)
    } else {
      let markup = "<od:alignment xmlns:od=\"\{spreadsheet_uri}\" " +
        values.map(v => "\{v.0}=\"\{v.1}\"").join(" ") +
        "/>"
      [
        if tree.one(root.id, "protection") is Some(node) {
          {
            node: root.id,
            offset: node.start - root.start,
            length: 0,
            xml: markup,
          }
        } else {
          insertion(root, markup)
        },
      ]
    }
    document = document.edit_source(changes).0
    document = metadata_attributes(document, document.nodes()[0], [
      ("applyAlignment", "1"),
    ])
  }
  document.source()
}
