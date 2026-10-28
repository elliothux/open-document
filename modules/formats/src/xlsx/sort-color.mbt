///|
fn SortKey::sort_format(self : SortKey) -> CellFormat raise @failure.Failure {
  if self.sort_by == "icon" {
    guard self.custom_list.is_empty() &&
      self.color.is_empty() &&
      (if self.icon_set.is_empty() {
        self.icon_id == 0
      } else {
        self.icon_id >= 0 &&
        self.icon_id < conditional_icon_count(self.icon_set)
      }) else {
      @failure.reject(
        "invalid-operation", "Invalid or conflicting icon sort settings",
      )
    }
    return CellFormat::new()
  }
  guard self.icon_set.is_empty() && self.icon_id == 0 else {
    @failure.reject(
      "invalid-operation", "Only icon sort keys can specify an icon",
    )
  }
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
fn Session::effective_cell_color(
  self : Session,
  index : Int32,
  address : Address,
  cell_color : Bool,
  rules : ConditionalRules,
  work : FormulaWork,
) -> String raise @failure.Failure {
  let current = self.sheets[index]
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
  work.spend()
  if cell_color {
    style.fill
  } else {
    style.color
  }
}

///|
fn Session::color_sort_key(
  self : Session,
  index : Int32,
  address : Address,
  key : SortKey,
  rules : ConditionalRules,
  rich : Map[String, Map[String, Bool]],
  work : FormulaWork,
) -> SortValue raise @failure.Failure {
  let matches = self.cell_color_matches(
    index,
    address,
    key.color,
    key.sort_by == "cellColor",
    rules,
    rich,
    work,
  )
  { value: Number(if matches { 0 } else { 1 }), rank: None, }
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
  let references : Array[Int32] = []
  for parent in parents {
    ignore(read_sort_state(tree, parent))
    if tree.one(parent, "sortState") is Some(state) {
      for key in tree.all(state.id, "sortCondition") {
        if ["cellColor", "fontColor"].contains(
            key.attribute("sortBy").unwrap_or("value"),
          ) {
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
