///|
fn WordTree::page_columns(
  self : WordTree,
  section : Int?,
) -> @layout.Columns raise @failure.Failure {
  guard section is Some(section) else { return @layout.Columns::new() }
  let nodes = self.table_children(section, "cols")
  guard nodes.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate column properties")
  }
  guard nodes.get(0) is Some(id) else { return @layout.Columns::new() }
  let node = self.nodes[id]
  guard node.text.trim().is_empty() &&
    node.attributes.all(a => {
      a.uri == word_uri &&
      ["num", "space", "sep", "equalWidth"].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "Unknown columns require layout support",
    )
  }
  let count = self.number(section, "cols", "num").unwrap_or(1)
  let gap = self.number(section, "cols", "space").unwrap_or(720) / 20
  let flag = node.attribute("sep", uri=word_uri).unwrap_or("0")
  let equal = node.attribute("equalWidth", uri=word_uri).unwrap_or("1")
  guard count >= 1 &&
    count <= 12 &&
    count.floor() == count &&
    gap >= 0 &&
    gap <= 14400 &&
    (gap * 20).floor() == gap * 20 &&
    ["0", "1", "false", "true", "on", "off"].contains(flag) &&
    ["0", "1", "false", "true", "on", "off"].contains(equal) else {
    @failure.reject("protected-content", "Invalid page column settings")
  }
  let custom : Array[@layout.Column] = []
  for child in self.children[id] {
    let column = self.nodes[child]
    guard !["1", "true", "on"].contains(equal) &&
      column.uri == word_uri &&
      column.name == "col" &&
      column.text.trim().is_empty() &&
      self.children[child].is_empty() &&
      column.attributes.all(a => {
        a.uri == word_uri && ["w", "space"].contains(a.name)
      }) else {
      @failure.reject("protected-content", "Unknown custom column properties")
    }
    let width = @string.parse_double(
      column.attribute("w", uri=word_uri).unwrap_or("0"),
    ) catch {
      _ => @failure.reject("protected-content", "Invalid column width")
    }
    let gap = @string.parse_double(
      column.attribute("space", uri=word_uri).unwrap_or("0"),
    ) catch {
      _ => @failure.reject("protected-content", "Invalid column spacing")
    }
    guard custom.length() < 12 &&
      width >= 240 &&
      width <= 288000 &&
      width.floor() == width &&
      gap >= 0 &&
      gap <= 288000 &&
      gap.floor() == gap else {
      @failure.reject("protected-content", "Invalid custom column extent")
    }
    custom.push({ width: width / 20, gap: gap / 20, })
  }
  guard ["1", "true", "on"].contains(equal) || !custom.is_empty() else {
    @failure.reject(
      "protected-content", "Custom columns require explicit widths",
    )
  }
  @layout.Columns::new(
    count=if custom.is_empty() { count.to_int() } else { custom.length() },
    gap~,
    separator=["1", "true", "on"].contains(flag),
    custom~,
  )
}

///|
fn Session::page_columns_query(self : Session, tree : WordTree) -> Json {
  try {
    let section = self.editable_page_section(tree)
    let columns = tree.page_columns(section)
    ignore(columns.width(self.flow().page))
    { "value": columns, "reason": "" }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": message }
  }
}

///|
pub fn Session::set_page_columns(
  self : Session,
  revision : Int,
  value : @layout.Columns?,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let original = self.document()
  let tree = WordTree::new(original)
  let section = self.editable_page_section(tree)
  let columns = value.unwrap_or(@layout.Columns::new())
  ignore(columns.width(self.flow().page))
  guard columns.gap * 20 == (columns.gap * 20).round() else {
    @failure.reject(
      "invalid-operation", "Column spacing requires integer twips",
    )
  }
  if Json(tree.page_columns(section)) == Json(columns) &&
    (value is Some(_) || section.bind(id => tree.child(id, "cols")) is None) {
    return self.edit_state()
  }
  if section.bind(id => tree.child(id, "cols")) is Some(id) {
    let node = tree.nodes[id]
    guard !original.source()[node.start:node.end].contains("<!--") &&
      !original.source()[node.start:node.end].contains("<?") else {
      @failure.reject(
        "protected-content", "Opaque column properties are protected",
      )
    }
  }
  let (candidate, edits, section) = page_section(original, tree, section)
  let tree = WordTree::new(candidate)
  let markup = if value is None {
    ""
  } else {
    let children = columns.custom
      .map(column => {
        "<w:col w:w=\"\{(column.width*20).round().to_int()}\" w:space=\"\{(column.gap*20).round().to_int()}\"/>"
      })
      .join("")
    let opening = "<w:cols xmlns:w=\"\{word_uri}\" w:num=\"\{columns.count}\" w:space=\"\{(columns.gap*20).round().to_int()}\" w:equalWidth=\"\{if columns.custom.is_empty() {1} else {0}}\" w:sep=\"\{if columns.separator {1} else {0}}\""
    opening +
    (if columns.custom.is_empty() {
      "/>"
    } else {
      ">" + children + "</w:cols>"
    })
  }
  let change = if tree.child(section, "cols") is None &&
    value is Some(_) &&
    !tree.nodes[section].empty {
    let previous = tree.children[section]
      .filter(id => {
        [
          "headerReference", "footerReference", "footnotePr", "endnotePr", "type",
          "pgSz", "pgMar", "paperSrc", "pgBorders", "lnNumType", "pgNumType",
        ].contains(tree.nodes[id].name)
      })
      .last()
    Some(@xml.SourceChange::{
      node: section,
      offset: previous
      .map(id => tree.nodes[id].end)
      .unwrap_or(tree.nodes[section].opening_end) -
      tree.nodes[section].start,
      length: 0,
      xml: markup,
    })
  } else {
    properties_change(tree, candidate, section, "cols", markup)
  }
  guard change is Some(change) else { return self.edit_state() }
  let (candidate, edit) = candidate.edit_source([change])
  edits.push(edit)
  self.commit_running(
    candidate,
    edits,
    self.parts.copy(),
    Map([]),
    Map([]),
    probe~,
    profile~,
    images~,
  )
}
