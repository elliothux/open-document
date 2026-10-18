///|
fn table_style_text(region : Ref) -> Ref? raise @failure.Failure {
  guard region.child("tcTxStyle") is Some(style) else { return None }
  table_profile(
    style.node.attributes.all(a => {
      a.uri.is_empty() && ["b", "i"].contains(a.name)
    }),
    "Unknown table text style attributes",
  )
  style.table_children(["fontRef", "font", "srgbClr", "schemeClr", "sysClr"])
  let attrs = StringBuilder()
  for name in ["b", "i"] {
    match style.node.attribute(name) {
      Some("on" | "1" | "true") => attrs <+ " \{name}=\"1\""
      Some("off" | "0" | "false") => attrs <+ " \{name}=\"0\""
      None | Some("def") => ()
      _ => @failure.reject("unsupported-table", "Unknown table text style flag")
    }
  }
  let markup = StringBuilder()
  let reference = style.child("fontRef")
  if reference is Some(reference) {
    let kind = reference.node.attribute("idx").unwrap_or("")
    table_profile(
      ["major", "minor", "none"].contains(kind),
      "Unknown table font reference",
    )
    if kind != "none" {
      for (name, suffix) in [("latin", "lt"), ("ea", "ea"), ("cs", "cs")] {
        markup <+
          "<a:\{name} typeface=\"+\{if kind == "major" {"mj"}else{"mn"}}-\{suffix}\"/>"
      }
    }
  }
  if style.child("font") is Some(font) {
    table_profile(reference is None, "Combined table font definitions")
    font.table_children(["latin", "ea", "cs", "font"])
    for node in font.tree.children.get(font.node.id).unwrap_or([]) {
      table_profile(
        ["latin", "ea", "cs"].contains(node.name),
        "Supplemental table fonts require resolution",
      )
      markup.write_string(
        font.tree.standalone_markup(font.tree.document, node.id),
      )
    }
  }
  let color = style.tree.children
    .get(style.node.id)
    .unwrap_or([])
    .filter(node => ["srgbClr", "schemeClr", "sysClr"].contains(node.name))
  table_profile(color.length() <= 1, "Multiple table text colors")
  let own_color = color.get(0).map(node => (style.tree, node))
  let color = if own_color is Some(_) {
    own_color
  } else {
    reference.bind(reference => {
      let nodes = reference.tree.children.get(reference.node.id).unwrap_or([])
      table_profile(nodes.length() <= 1, "Unknown table font color")
      nodes.get(0).map(node => (reference.tree, node))
    })
  }
  if color is Some((tree, node)) {
    markup <+
      "<a:solidFill>\{tree.standalone_markup(tree.document,node.id)}</a:solidFill>"
  }
  if attrs.is_empty() && markup.is_empty() {
    return None
  }
  let document = @xml.Document::parse(
    @utf8.encode(
      "<a:defRPr xmlns:a=\"\{drawing_uri}\"\{attrs}>\{markup}</a:defRPr>",
    ),
    "table-text-style",
    64,
    1048576,
  )
  let tree = Tree::new("table-text-style", document)
  Some({ tree, node: document.nodes()[0], })
}
