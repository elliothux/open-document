///|
fn Session::filter_color(
  self : Session,
  rule : FilterRule,
) -> (String, Bool) raise @failure.Failure {
  match rule {
    Color(value, cell_color~) =>
      (
        value.map(color_hex).unwrap_or(if cell_color { "" } else { "000000" }),
        cell_color,
      )
    ColorStyle(index, cell_color~) => {
      let path = self
        .styles_part(self.parts)
        .unwrap_or_else(() => {
          @failure.reject(
            "protected-content", "Color filter styles are missing",
          )
        })
      let tree = Tree::new(self.part_xml(path))
      let pool = tree
        .one(tree.root("styleSheet").id, "dxfs")
        .unwrap_or_else(() => {
          @failure.reject(
            "protected-content", "Color filter styles are missing",
          )
        })
      let node = tree
        .all(pool.id, "dxf")
        .get(index)
        .unwrap_or_else(() => {
          @failure.reject(
            "protected-content", "Color filter style reference is missing",
          )
        })
      let patch = conditional_style(tree, node, self.theme)
      // ONLYOFFICE stores the comparison color in dxf.fill for both filter modes.
      let selected = match patch.fill {
        Some(value) => Some(value)
        None => if cell_color { None } else { patch.color }
      }
      let value = selected.unwrap_or_else(() => {
        @failure.reject(
          "protected-content", "Color filter style has no supported color",
        )
      })
      (
        if value.is_empty() && !cell_color {
          "000000"
        } else {
          value.to_lower()
        },
        cell_color,
      )
    }
    _ => @failure.reject("invalid-operation", "Expected a color filter")
  }
}

///|
fn Session::filter_column_json(
  self : Session,
  column : FilterColumn,
) -> Json raise @failure.Failure {
  if column.rule is ColorStyle(_, ..) {
    let (color, cell_color) = self.filter_color(column.rule)
    return FilterColumn::{
      ..column,
      rule: Color(
        if color.is_empty() {
          None
        } else {
          Some(color)
        },
        cell_color~,
      ),
    }.json()
  }
  column.json()
}

///|
fn color_filter_format(rule : FilterRule) -> CellFormat {
  match rule {
    Color(value, ..) =>
      CellFormat::new(fill=Some(value.unwrap_or("").to_upper()))
    _ => CellFormat::new()
  }
}
