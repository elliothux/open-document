///|
fn SortKey::sort_format(self : SortKey) -> CellFormat raise @failure.Failure {
  if self.sort_by == "value" {
    guard self.color.is_empty() else {
      @failure.reject(
        "invalid-operation", "Value sort keys cannot specify a color",
      )
    }
    return CellFormat::new()
  }
  guard ["cellColor", "fontColor"].contains(self.sort_by) &&
    self.custom_list.is_empty() else {
    @failure.reject(
      "invalid-operation", "Invalid or conflicting color sort settings",
    )
  }
  let patch = if self.sort_by == "cellColor" {
    CellFormat::new(fill=Some(self.color.to_upper()))
  } else {
    CellFormat::new(color=Some(self.color.to_upper()))
  }
  patch.validate()
  patch
}

///|
fn Session::color_sort_key(
  self : Session,
  index : Int,
  address : Address,
  key : SortKey,
  rules : ConditionalRules,
  work : FormulaWork,
) -> SortValue raise @failure.Failure {
  let current = self.sheets[index]
  guard key.sort_by != "fontColor" ||
    current.cells
    .get(address.name())
    .map(c => c.read_only != "Rich text cell is read-only")
    .unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Rich text font-color sorting requires run color ownership",
    )
  }
  let style = rules.applied(
    self.styles[current.style_at(address)],
    address,
    self.sheets,
    index,
    self.calculation.map(c => c.values).unwrap_or(Map([])),
    work,
  )
  guard style.diagnostic.is_empty() else {
    @failure.reject("protected-content", style.diagnostic)
  }
  let color = if key.sort_by == "cellColor" { style.fill } else { style.color }
  work.spend()
  {
    value: Number(if color.to_lower() == key.color.to_lower() { 0 } else { 1 }),
    rank: None,
  }
}

///|
fn Session::check_sort_metadata(
  self : Session,
  tree : Tree,
  table~ : Bool = false,
) -> Unit raise @failure.Failure {
  let root = tree.root(if table { "table" } else { "worksheet" })
  let parents = [root.id]
  parents.append(tree.all(root.id, "autoFilter").map(node => node.id))
  let references : Array[Int] = []
  for parent in parents {
    ignore(read_sort_state(tree, parent))
    if tree.one(parent, "sortState") is Some(state) {
      for key in tree.all(state.id, "sortCondition") {
        if key.attribute("sortBy").unwrap_or("value") != "value" {
          references.push(natural(key.attribute("dxfId").unwrap(), 4095))
        }
      }
    }
  }
  if references.is_empty() {
    return
  }
  let path = self
    .styles_part(self.parts)
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part="",
        offset=-1,
        message="Color sort styles are missing",
      ),
    )
  let styles = Tree::new(self.part_xml(path))
  let count = styles
    .one(styles.root("styleSheet").id, "dxfs")
    .map(pool => styles.all(pool.id, "dxf").length())
    .unwrap_or(0)
  guard references.all(index => index < count) else {
    @failure.reject(
      "protected-content", "Color sort style reference is missing",
    )
  }
}
