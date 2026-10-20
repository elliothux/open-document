///|
pub(all) struct CopiedHyperlink {
  range : Range
  target : String
  display : String?
  tooltip : String?
}

///|
fn CopiedCells::check_copied_hyperlinks(
  self : CopiedCells,
) -> Unit raise @failure.Failure {
  guard self.hyperlinks.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Copied hyperlinks exceed budget")
  }
  let bounds : Range = {
    top: self.top,
    left: self.left,
    bottom: self.top + self.cells.length() - 1,
    right: self.left + self.cells[0].length() - 1,
  }
  let occupied : Map[Int, Bool] = Map([])
  let mut units = 0
  for link in self.hyperlinks {
    let r = link.range
    guard r.top <= r.bottom && r.left <= r.right && bounds.covers(r) else {
      @failure.reject(
        "invalid-operation", "Copied hyperlink leaves source rectangle",
      )
    }
    check_hyperlink_target(link.target)
    units += link.target.length()
    for text in [link.display, link.tooltip] {
      if text is Some(text) {
        guard text.length() <= 32767 && @xml.valid_text(text) else {
          @failure.reject(
            "invalid-operation", "Invalid copied hyperlink metadata",
          )
        }
        units += text.length()
      }
    }
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Copied hyperlink text exceeds budget")
    }
    for row in r.top..<=r.bottom {
      for column in r.left..<=r.right {
        let key = (row - self.top) * self.cells[0].length() + column - self.left
        guard !occupied.contains(key) else {
          @failure.reject(
            "protected-content", "Overlapping copied hyperlinks are protected",
          )
        }
        occupied[key] = true
      }
    }
  }
}

///|
fn Session::capture_hyperlinks(
  self : Session,
  sheet : Sheet,
  selected : Range,
  complete~ : Bool = false,
) -> Array[CopiedHyperlink] raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let relations = self.hyperlink_relations(sheet.id)
  hyperlink_nodes(tree).filter_map(node => {
    let range = Range::parse(node.attribute("ref").unwrap_or(""))
    if !range.intersects(selected) || (complete && !selected.covers(range)) {
      return None
    }
    Some(CopiedHyperlink::{
      range: {
        top: range.top.max(selected.top),
        bottom: range.bottom.min(selected.bottom),
        left: range.left.max(selected.left),
        right: range.right.min(selected.right),
      },
      target: hyperlink_target(tree, node, relations),
      display: node.attribute("display"),
      tooltip: node.attribute("tooltip"),
    })
  })
}

///|
fn Session::prepare_hyperlinks(
  self : Session,
  plan : CellEditPlan,
  index : Int,
  target : Range,
  hyperlinks : Array[CopiedHyperlink],
) -> Unit raise @failure.Failure {
  let sheet = plan.sheets[index]
  let tree = Tree::new(sheet.document)
  let changes : Array[@xml.SourceChange] = []
  let nodes = hyperlink_nodes(tree)
  let mut count = nodes.length()
  let mut units = 0
  for node in nodes {
    let range = Range::parse(node.attribute("ref").unwrap_or(""))
    if !range.intersects(target) {
      continue
    }
    hyperlink_source(tree, node)
    let pieces = range.without(target)
    let xml = pieces
      .map(piece => hyperlink_fragment(tree, node, piece, None, None))
      .join("")
    count += pieces.length() - 1
    units += xml.length()
    guard count <= 4096 && units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Pasted hyperlinks exceed source budget",
      )
    }
    changes.push({
      node: node.parent,
      offset: node.start - tree.nodes[node.parent].start,
      length: node.end - node.start,
      xml,
    })
  }
  let additions = StringBuilder()
  for link in hyperlinks {
    let range = link.range
    let destination = if link.target.has_prefix("#") {
      "location=\"\{escaped_attribute(link.target[1:].to_owned())}\""
    } else {
      let relation = self.hyperlink_relation(
        sheet,
        link.target,
        plan.parts,
        plan.edits,
        plan.created_parts,
      )
      "xmlns:odRel=\"\{relationship_uri[:relationship_uri.length() - 1]}\" odRel:id=\"\{relation}\""
    }
    let attributes = StringBuilder()
    for (name, value) in [("display", link.display), ("tooltip", link.tooltip)] {
      if value is Some(text) {
        attributes.write_string(" \{name}=\"\{escaped_attribute(text)}\"")
      }
    }
    let xml = "<od:hyperlink xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{range.name()}\" \{destination}\{attributes.to_string()}/>"
    count += 1
    units += xml.length()
    guard count <= 4096 && units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Pasted hyperlinks exceed source budget",
      )
    }
    additions.write_string(xml)
  }
  guard count <= 4096 && units <= 2097152 else {
    @failure.reject("limit-exceeded", "Pasted hyperlinks exceed source budget")
  }
  if !additions.is_empty() {
    changes.push(hyperlink_insertion(tree, additions.to_string()))
  }
  if changes.is_empty() {
    return
  }
  let (document, edit) = sheet.document.edit_source(join_insertions(changes))
  if document.source() == sheet.document.source() {
    return
  }
  plan.edits.push((sheet.id, edit))
  plan.sheets[index] = Sheet::read(
    sheet.id,
    sheet.name,
    sheet.state,
    document,
    self.strings,
    plan.styles.length(),
  )
}
