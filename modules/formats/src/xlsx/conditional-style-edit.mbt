///|
priv struct ConditionalStyleEdit {
  indices : Array[Int?]
  parts : Map[String, @xml.Document]
  edits : Array[(String, @xml.Edit)]
  created_parts : Map[String, @xml.Document]
}

///|
fn CellFormat::dxf_markup(
  self : CellFormat,
  number_id : Int?,
  inner~ : Array[CellBorder?] = [None, None],
) -> String raise @failure.Failure {
  guard self.locked is None && self.formulaHidden is None else {
    @failure.reject(
      "invalid-operation", "Differential styles cannot change cell protection",
    )
  }
  let document = @xml.Document::parse(
    @utf8.encode("<dxf xmlns=\"\{spreadsheet_uri}\"><font/><border/></dxf>"),
    "conditional-style",
    128,
    2097152,
  )
  let tree = Tree::new(document)
  let root = document.nodes()[0]
  let text = StringBuilder()
  text.write_string("<od:dxf xmlns:od=\"\{spreadsheet_uri}\">")
  if self.family is Some(_) ||
    self.size is Some(_) ||
    self.bold is Some(_) ||
    self.italic is Some(_) ||
    self.underline is Some(_) ||
    self.strike is Some(_) ||
    self.script is Some(_) ||
    self.color is Some(_) {
    text.write_string(
      self.font_markup(tree, tree.one(root.id, "font").unwrap()),
    )
  }
  if self.numberFormat is Some(code) {
    text.write_string(
      "<od:numFmt numFmtId=\"\{number_id.unwrap()}\" formatCode=\"\{escaped_attribute(code)}\"/>",
    )
  }
  if self.fill is Some(color) {
    text.write_string(
      if color.is_empty() {
        "<od:fill><od:patternFill patternType=\"none\"/></od:fill>"
      } else {
        "<od:fill><od:patternFill patternType=\"solid\"><od:bgColor rgb=\"FF\{color.to_upper()}\"/></od:patternFill></od:fill>"
      },
    )
  }
  let alignment = StringBuilder()
  for
    (key, value) in [
      ("horizontal", self.horizontal),
      ("vertical", self.vertical),
      ("wrapText", self.wrap.map(v => if v { "1" } else { "0" })),
      ("indent", self.indent.map(v => v.to_string())),
    ] {
    if value is Some(value) {
      alignment.write_string(" \{key}=\"\{value}\"")
    }
  }
  if !alignment.to_string().is_empty() {
    text.write_string("<od:alignment\{alignment.to_string()}/>")
  }
  if [self.left, self.right, self.top, self.bottom, ..inner].any(e => {
      e is Some(_)
    }) {
    let border = @xml.Document::parse(
      @utf8.encode(
        self.border_markup(tree, tree.one(root.id, "border").unwrap()),
      ),
      "differential-border",
      128,
      2097152,
    )
    let changes = ["vertical", "horizontal"]
      .mapi((i, name) => inner[i].map(border => (name, border.markup(name))))
      .iter()
      .filter_map(v => v)
      .to_array()
    text.write_string(style_children(border, changes).source())
  }
  text.write_string("</od:dxf>")
  text.to_string()
}

///|
fn Session::derive_conditional_styles(
  self : Session,
  patches : Array[CellFormat],
  inner~ : Array[Array[CellBorder?]] = patches.map(_ => [None, None]),
  parts~ : Map[String, @xml.Document] = self.parts,
) -> ConditionalStyleEdit raise @failure.Failure {
  guard inner.length() == patches.length() &&
    inner.all(edges => edges.length() == 2) else {
    @failure.reject("invalid-operation", "Invalid differential inner borders")
  }
  let empty = patches.mapi((index, patch) => {
    patch == CellFormat::new() && inner[index].all(edge => edge is None)
  })
  if empty.all(value => value) {
    return {
      indices: patches.map(_ => None),
      parts: parts.copy(),
      edits: [],
      created_parts: Map([]),
    }
  }
  let parts = parts.copy()
  let existing = self.styles_part(parts)
  let (path, metadata) = existing
    .map(path => (path, []))
    .unwrap_or_else(() => self.new_styles_part())
  let original = if existing is Some(_) {
    parts.get(path).unwrap_or_else(() => self.part_xml(path))
  } else {
    @xml.Document::parse(
      empty_cell_styles(),
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
  }
  guard original.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Conditional styles exceed history budget",
    )
  }
  let tree = Tree::new(original)
  let root = tree.root("styleSheet")
  let (ids, numbers) = format_numbers(tree, patches)
  let changes = format_number_changes(tree, numbers)
  let container = tree.one(root.id, "dxfs")
  let indices = if container is Some(_) {
    let pool = StylePool::new(tree, "dxfs", "dxf")
    let indices = patches.mapi((index, patch) => {
      if empty[index] {
        None
      } else {
        Some(
          pool.intern(
            patch.dxf_markup(
              patch.numberFormat.bind(code => ids.get(code)),
              inner=inner[index],
            ),
          ),
        )
      }
    })
    changes.append(pool.changes())
    indices
  } else {
    let entries : Array[String] = []
    let indices = patches.mapi((index, patch) => {
      if empty[index] {
        None
      } else {
        let markup = patch.dxf_markup(
          patch.numberFormat.bind(code => ids.get(code)),
          inner=inner[index],
        )
        let index = entries
          .search(markup)
          .unwrap_or_else(() => {
            let index = entries.length()
            entries.push(markup)
            index
          })
        Some(index)
      }
    })
    let next = tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(n => ["tableStyles", "colors", "extLst"].contains(n.name))
    let markup = "<od:dxfs xmlns:od=\"\{spreadsheet_uri}\" count=\"\{entries.length()}\">\{entries.join("")}</od:dxfs>"
    changes.push(
      if next is Some(next) {
        {
          node: root.id,
          offset: next.start - root.start,
          length: 0,
          xml: markup,
        }
      } else {
        insertion(root, markup)
      },
    )
    indices
  }
  let (document, edit) = original.edit_source(join_insertions(changes))
  guard document.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Derived conditional styles exceed history budget",
    )
  }
  parts[path] = document
  let edits = []
  for (part, document, edit) in metadata {
    parts[part] = document
    edits.push((part, edit))
  }
  let created_parts : Map[String, @xml.Document] = Map([])
  if existing is Some(_) {
    if original.source() != document.source() {
      edits.push((path, edit))
    }
  } else {
    created_parts[path] = document
  }
  { indices, parts, edits, created_parts, }
}
