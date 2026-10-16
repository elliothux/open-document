///|
fn normal_xf(tree : Tree) -> (@xml.Node?, Int?) raise @failure.Failure {
  let root = tree.root("styleSheet")
  let formats = tree
    .one(root.id, "cellStyleXfs")
    .map(node => tree.all(node.id, "xf"))
    .unwrap_or([])
  if formats.is_empty() {
    return (None, None)
  }
  let names = tree
    .one(root.id, "cellStyles")
    .map(node => tree.all(node.id, "cellStyle"))
    .unwrap_or([])
  let normal = match
    names.iter().find_first(node => node.attribute("builtinId") == Some("0")) {
    Some(node) => Some(node)
    None =>
      names.iter().find_first(node => node.attribute("name") == Some("Normal"))
  }
  let id = normal
    .map(node => {
      natural(node.attribute("xfId").unwrap_or("0"), formats.length() - 1)
    })
    .unwrap_or(0)
  (Some(formats[id]), Some(id))
}

///|
fn normal_font(
  document : @xml.Document,
) -> (String, Double) raise @failure.Failure {
  let tree = Tree::new(document)
  let (normal, _) = normal_xf(tree)
  let fonts = tree
    .one(tree.root("styleSheet").id, "fonts")
    .map(node => tree.all(node.id, "font"))
    .unwrap_or([])
  guard !fonts.is_empty() else {
    @failure.reject("malformed-xlsx", "Missing Normal font")
  }
  let id = natural(
    normal.bind(node => node.attribute("fontId")).unwrap_or("0"),
    fonts.length() - 1,
  )
  let font = fonts[id]
  let name = tree
    .one(font.id, "name")
    .bind(node => node.attribute("val"))
    .unwrap_or("Calibri")
  guard !name.is_empty() && name.length() <= 256 else {
    @failure.reject("malformed-xlsx", "Invalid Normal font")
  }
  let key = name +
    (if tree
      .one(font.id, "b")
      .map(node => flag(node, "val", fallback=true))
      .unwrap_or(false) {
      "|bold"
    } else {
      ""
    }) +
    (if tree
      .one(font.id, "i")
      .map(node => flag(node, "val", fallback=true))
      .unwrap_or(false) {
      "|italic"
    } else {
      ""
    })
  let size = tree
    .one(font.id, "sz")
    .bind(node => node.attribute("val"))
    .map(value => number(value))
    .unwrap_or(11)
  guard size > 0 && size <= 409 else {
    @failure.reject("malformed-xlsx", "Invalid Normal font size")
  }
  (key, size)
}

///|
fn Session::normal_style(
  self : Session,
) -> (Int, Array[CellStyle], Array[(String, @xml.Document, @xml.Edit)]) raise @failure.Failure {
  guard self.styles_part(self.parts) is Some(path) else {
    return (0, self.styles, [])
  }
  let source = self.part_xml(path)
  guard source.source().length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Cell styles exceed history budget")
  }
  let tree = Tree::new(source)
  let (normal, id) = normal_xf(tree)
  let fragment = if normal is Some(normal) {
    style_fragment(tree, normal)
  } else {
    @xml.Document::parse(
      @utf8.encode(
        "<od:xf xmlns:od=\"\{spreadsheet_uri}\" fontId=\"0\" fillId=\"0\" borderId=\"0\" numFmtId=\"0\"/>",
      ),
      "cell-style",
      128,
      2097152,
    )
  }
  check_style_fragment(fragment)
  let fragment = if id is Some(id) {
    fragment.edit_source(
      metadata_changes(fragment.nodes()[0], [("xfId", id.to_string())]),
    ).0
  } else {
    fragment
  }
  let pool = StylePool::new(tree, "cellXfs", "xf")
  let index = pool.intern(fragment.source())
  if index < self.styles.length() {
    return (index, self.styles, [])
  }
  let (document, edit) = source.edit_source(pool.changes())
  let styles = read_styles(document, self.theme)
  guard styles[index].diagnostic.is_empty() else {
    @failure.reject(
      "protected-content",
      "Normal style is unsupported: " + styles[index].diagnostic,
    )
  }
  (index, styles, [(path, document, edit)])
}
