///|
fn rich_run_colors(
  tree : Tree,
  root : @xml.Node,
  theme : Array[String],
  work : FormulaWork,
) -> Map[String, Bool] raise @failure.Failure {
  let runs = tree.all(root.id, "r")
  conditional_node(tree, root, [], if runs.is_empty() { ["t"] } else { ["r"] })
  let colors : Map[String, Bool] = Map([])
  // The empty key inherits the current effective cell font color.
  if runs.is_empty() {
    colors[""] = true
  }
  for run in runs {
    work.spend()
    conditional_node(tree, run, [], ["rPr", "t"])
    ignore(tree.one(run.id, "t"))
    let properties = tree.one(run.id, "rPr")
    if properties is Some(properties) {
      conditional_node(tree, properties, [], [
        "rFont", "charset", "family", "b", "i", "strike", "outline", "shadow", "condense",
        "extend", "color", "sz", "u", "vertAlign", "scheme",
      ])
    }
    let color = properties.bind(properties => tree.one(properties.id, "color"))
    colors[color
    .map(color => conditional_color(tree, color, theme))
    .unwrap_or("")] = true
  }
  colors
}

///|
fn Session::rich_text_sources(
  self : Session,
  current : Sheet,
  addresses : Array[Address],
  work : FormulaWork,
  parts~ : Map[String, @xml.Document] = self.parts,
) -> Map[String, (Tree, @xml.Node)] raise @failure.Failure {
  let result : Map[String, (Tree, @xml.Node)] = Map([])
  let cells = addresses
    .filter_map(address => current.cells.get(address.name()))
    .filter(cell => cell.read_only == "Rich text cell is read-only")
  if cells.is_empty() {
    return result
  }
  let inline = Tree::new(current.document)
  let mut shared : (Tree, Array[@xml.Node])? = None
  for cell in cells {
    work.spend()
    let colors = if cell.shared is Some(index) {
      if shared is None {
        let path = self.strings_part.unwrap_or_else(() => {
          @failure.reject(
            "protected-content", "Rich shared strings are missing",
          )
        })
        let tree = Tree::new(
          parts.get(path).unwrap_or_else(() => self.part_xml(path)),
        )
        shared = Some((tree, tree.all(tree.root("sst").id, "si")))
      }
      let (tree, items) = shared.unwrap()
      let root = items
        .get(index)
        .unwrap_or_else(() => {
          @failure.reject(
            "protected-content", "Rich shared string reference is missing",
          )
        })
      (tree, root)
    } else {
      let root = inline
        .one(cell.node, "is")
        .unwrap_or_else(() => {
          @failure.reject("protected-content", "Rich inline string is missing")
        })
      (inline, root)
    }
    result[cell.address.name()] = colors
  }
  result
}

///|
fn Session::rich_text_colors(
  self : Session,
  index : Int,
  addresses : Array[Address],
  work : FormulaWork,
) -> Map[String, Map[String, Bool]] raise @failure.Failure {
  let sheet = self.sheets[index]
  let sources = self.rich_text_sources(sheet, addresses, work)
  let result : Map[String, Map[String, Bool]] = Map([])
  let cache : Map[Int, Map[String, Bool]] = Map([])
  for name, (tree, root) in sources {
    let shared = sheet.cells[name].shared
    let colors = shared
      .bind(index => cache.get(index))
      .unwrap_or_else(() => {
        let colors = rich_run_colors(tree, root, self.theme, work)
        if shared is Some(index) {
          cache[index] = colors
        }
        colors
      })
    result[name] = colors
  }
  result
}

///|
fn Session::cell_color_matches(
  self : Session,
  index : Int,
  address : Address,
  wanted : String,
  cell_color : Bool,
  rules : ConditionalRules,
  rich : Map[String, Map[String, Bool]],
  work : FormulaWork,
) -> Bool raise @failure.Failure {
  let color = self
    .effective_cell_color(index, address, cell_color, rules, work)
    .to_lower()
  let wanted = wanted.to_lower()
  if !cell_color && rich.get(address.name()) is Some(colors) {
    colors.contains(wanted) || (colors.contains("") && color == wanted)
  } else {
    color == wanted
  }
}
