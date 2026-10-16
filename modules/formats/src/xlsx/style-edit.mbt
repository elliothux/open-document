///|
priv struct StyleEdit {
  indices : Map[String, Int]
  styles : Array[CellStyle]
  parts : Map[String, @xml.Document]
  edits : Array[(String, @xml.Edit)]
  created_parts : Map[String, @xml.Document]
}

///|
fn Session::derive_formats(
  self : Session,
  originals : Map[String, (Int, Int)],
  patches : Array[CellFormat],
  border_sides~ : Map[Int, Array[String]] = Map([]),
) -> StyleEdit raise @failure.Failure {
  let bases : Map[(Int, Int), Bool] = Map([])
  for key in originals.values() {
    bases[key] = true
  }
  let parts = self.parts.copy()
  let existing = self.styles_part(parts)
  let (path, metadata) = if existing is Some(path) {
    (path, [])
  } else {
    self.new_styles_part()
  }
  let original = if existing is Some(_) {
    self.part_xml(path)
  } else {
    @xml.Document::parse(
      empty_cell_styles(),
      path,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    )
  }
  guard original.source().length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Cell styles exceed history budget")
  }
  let tree = Tree::new(original)
  let fonts = StylePool::new(tree, "fonts", "font")
  let fills = StylePool::new(tree, "fills", "fill")
  let borders = StylePool::new(tree, "borders", "border")
  let formats = StylePool::new(tree, "cellXfs", "xf")
  let mappings : Map[(Int, Int), Int] = Map([])
  let (number_ids, new_formats) = format_numbers(tree, patches)
  let mut units = 0
  for key in bases.keys() {
    let (base, id) = key
    let patch = patches[id]
    let xf = formats.nodes[base]
    let font = natural(xf.attribute("fontId").unwrap_or("0"), 4095)
    let fill = natural(xf.attribute("fillId").unwrap_or("0"), 4095)
    let border = natural(xf.attribute("borderId").unwrap_or("0"), 4095)
    let derived_font = if patch.family is Some(_) ||
      patch.size is Some(_) ||
      patch.bold is Some(_) ||
      patch.italic is Some(_) ||
      patch.color is Some(_) {
      fonts.intern(patch.font_markup(tree, fonts.nodes[font]))
    } else {
      font
    }
    let derived_fill = if patch.fill is Some(color) {
      fills.intern(
        if color.is_empty() {
          "<od:fill xmlns:od=\"\{spreadsheet_uri}\"><od:patternFill patternType=\"none\"/></od:fill>"
        } else {
          "<od:fill xmlns:od=\"\{spreadsheet_uri}\"><od:patternFill patternType=\"solid\"><od:fgColor rgb=\"FF\{color.to_upper()}\"/><od:bgColor indexed=\"64\"/></od:patternFill></od:fill>"
        },
      )
    } else {
      fill
    }
    let derived_border = if border_sides.get(id) is Some(sides) {
      let original = style_fragment(tree, borders.nodes[border])
      check_style_fragment(original)
      let replacements : Array[(String, String)] = []
      for side, name in ["left", "right", "top", "bottom"] {
        replacements.push((name, sides[side]))
      }
      borders.intern(style_children(original, replacements).source())
    } else if [patch.left, patch.right, patch.top, patch.bottom].any(v => {
        v is Some(_)
      }) {
      borders.intern(patch.border_markup(tree, borders.nodes[border]))
    } else {
      border
    }
    let markup = patch.xf_markup(
      tree,
      xf,
      derived_font,
      derived_fill,
      derived_border,
      patch.numberFormat.bind(code => number_ids.get(code)),
    )
    units += markup.length() +
      fonts.entries[derived_font].length() +
      fills.entries[derived_fill].length() +
      borders.entries[derived_border].length()
    guard units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Derived cell styles exceed source budget",
      )
    }
    mappings[key] = formats.intern(markup)
  }
  let changes = [
    ..fonts.changes(),
    ..fills.changes(),
    ..borders.changes(),
    ..formats.changes(),
  ]
  changes.append(format_number_changes(tree, new_formats))
  let generated = changes
    .iter()
    .fold(init=0L, (sum, change) => sum + change.xml.length().to_int64())
  guard generated <= 2097152L else {
    @failure.reject(
      "limit-exceeded", "Cell format source exceeds history budget",
    )
  }
  let (document, style_edit) = original.edit_source(changes)
  guard document.source().length() <= 2097152 else {
    @failure.reject(
      "limit-exceeded", "Derived cell styles exceed source budget",
    )
  }
  parts[path] = document
  let edits : Array[(String, @xml.Edit)] = []
  for (name, document, edit) in metadata {
    parts[name] = document
    edits.push((name, edit))
  }
  let created_parts : Map[String, @xml.Document] = Map([])
  if existing is Some(_) {
    edits.push((path, style_edit))
  } else {
    created_parts[path] = document
  }
  let styles = read_styles(document, self.theme)
  let indices : Map[String, Int] = Map([])
  for name, key in originals {
    indices[name] = mappings[key]
  }
  { indices, styles, parts, edits, created_parts, }
}
