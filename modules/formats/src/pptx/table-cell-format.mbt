///|
fn DrawingTable::format_range(
  self : DrawingTable,
  selection : Selection,
) -> TableRange raise @failure.Failure {
  if selection.mode == "text" {
    return self.range(selection)
  }
  {
    top: 0,
    bottom: self.rows.length() - 1,
    left: 0,
    right: self.widths.length() - 1,
    owners: self.rows.fold(init=0, (sum, row) => {
      sum + row.cells.filter(cell => cell.owner()).length()
    }),
  }
}

///|
fn table_format_reason(object : Object) -> String {
  if !["", "Group members are read-only"].contains(object.read_only) {
    object.read_only
  } else {
    object.text_reason
  }
}

///|
fn table_cell_values(
  cell : DrawingCell,
  borders : Array[(String, Double)],
) -> Array[Json] {
  let (color, width) = borders[0]
  [
    Json(cell.fill),
    if borders.all(edge => edge.0 == color) {
      Json(color)
    } else {
      Json::null()
    },
    if borders.all(edge => {
        (if edge.0.is_empty() { 0.0 } else { edge.1 }) ==
        (if color.is_empty() { 0.0 } else { width })
      }) {
      Json(if color.is_empty() { 0.0 } else { width })
    } else {
      Json::null()
    },
    Json(cell.body.left),
    Json(cell.body.top),
    Json(cell.body.right),
    Json(cell.body.bottom),
    Json(cell.body.anchor),
    Json(cell.body.direction),
  ]
}

///|
fn table_format_query(
  object : Object,
  selection : Selection,
) -> Json raise @failure.Failure {
  let table = object.table.unwrap()
  let range = table.format_range(selection)
  let values : Array[Array[Json]] = []
  for r in range.top..<=range.bottom {
    for c in range.left..<=range.right {
      let cell = table.rows[r].cells[c]
      if cell.owner() {
        values.push(table_cell_values(cell, table.cell_borders(r, c)))
      }
    }
  }
  let result : Map[String, Json] = {
    "reason": Json(table_format_reason(object)),
    "borderReason": Json(""),
  }
  for
    i, name in [
      "fill", "borderColor", "borderWidth", "left", "top", "right", "bottom", "anchor",
      "direction",
    ] {
    result[name] = if values.all(row => row[i] == values[0][i]) {
      values[0][i]
    } else {
      Json::null()
    }
  }
  ignore(table.border_targets(range)) catch {
    @failure.Failure(message~, ..) => result["borderReason"] = Json(message)
  }
  Json(result)
}

///|
fn Session::format_table_cells(
  self : Session,
  change : ObjectEdit,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let original = self.current()
  let object = original.object(self.selection.object)
  let reason = table_format_reason(object)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let table = object.table.unwrap()
  let range = table.format_range(self.selection)
  let attributes : Map[String, String] = Map([])
  let (color, width) = match change {
    Fill(color) => (color, None)
    Stroke(color, width) => {
      guard !width.is_nan() && !width.is_inf() && width >= 0.1 && width <= 1000 else {
        @failure.reject(
          "invalid-operation", "Line width must be within 0.1 and 1000 points",
        )
      }
      (color, Some((width * 12700).round() / 12700))
    }
    TextInsets(left, top, right, bottom) => {
      for
        (key, value) in [
          ("marL", left),
          ("marT", top),
          ("marR", right),
          ("marB", bottom),
        ] {
        guard !value.is_nan() && !value.is_inf() && value >= 0 && value <= 14400 else {
          @failure.reject(
            "invalid-operation", "Cell margins must be within 0 and 14400 points",
          )
        }
        attributes[key] = (value * 12700).round().to_int64().to_string()
      }
      (None, None)
    }
    TextAnchor(anchor) => {
      guard ["t", "ctr", "b"].contains(anchor) else {
        @failure.reject("invalid-operation", "Unknown cell anchor")
      }
      attributes["anchor"] = anchor
      (None, None)
    }
    TextDirection(direction) => {
      guard ["horz", "vert", "vert270"].contains(direction) else {
        @failure.reject("invalid-operation", "Unsupported table cell direction")
      }
      attributes["vert"] = direction
      (None, None)
    }
    _ => @failure.reject("invalid-operation", "Unknown table cell format")
  }
  if color is Some(color) {
    guard color.length() == 6 && color.iter().all(c => c.is_ascii_hexdigit()) else {
      @failure.reject(
        "invalid-operation", "Cell color requires six hexadecimal digits or null",
      )
    }
  }
  let targets = if width is Some(_) { table.border_targets(range) } else { [] }
  let changes : Array[@xml.SourceChange] = []
  let grow_rows : Map[Int, Bool] = Map([])
  for r, row in table.rows {
    for c, cell in row.cells {
      if !cell.owner() {
        continue
      }
      if width is Some(width) {
        changes.append(table_border_changes(cell, targets[r][c], color, width))
        continue
      }
      if r < range.top || r > range.bottom || c < range.left || c > range.right {
        continue
      }
      let properties = cell.source.child("tcPr")
      if change is Fill(_) {
        if properties is Some(properties) {
          if !same_paint(properties, color, opacity=cell.alpha) {
            changes.push(
              paint_child_change(
                properties,
                paint_fill(properties),
                paint_markup(color, opacity=cell.alpha),
                [],
              ),
            )
          }
        } else {
          changes.push(
            insertion(
              cell.source.node,
              "<a:tcPr xmlns:a=\"\{drawing_uri}\">\{paint_markup(color, opacity=cell.alpha)}</a:tcPr>",
            ),
          )
        }
        continue
      }
      if change is TextInsets(_, _, _, _) {
        guard number(attributes["marL"], 0, 182880000) / 12700 +
          number(attributes["marR"], 0, 182880000) / 12700 <
          table.width(c, cell) else {
          @failure.reject(
            "invalid-transform", "Cell margins leave no text width",
          )
        }
      }
      let current : Map[String, String] = {
        "marL": (cell.body.left * 12700).round().to_int64().to_string(),
        "marT": (cell.body.top * 12700).round().to_int64().to_string(),
        "marR": (cell.body.right * 12700).round().to_int64().to_string(),
        "marB": (cell.body.bottom * 12700).round().to_int64().to_string(),
        "anchor": cell.body.anchor,
        "vert": cell.body.direction,
      }
      if attributes.iter().all(pair => current[pair.0] == pair.1) {
        continue
      }
      if change is TextDirection(direction) &&
        direction != "horz" &&
        row.height < 720000.0 / 12700 {
        grow_rows[r] = true
      }
      if properties is Some(properties) {
        changes.push({
          node: cell.source.node.id,
          offset: properties.node.start - cell.source.node.start,
          length: properties.node.opening_end - properties.node.start,
          xml: frame_opening(properties, attributes) +
          (if properties.node.empty {
            "</\{properties.node.qualified}>"
          } else {
            ""
          }),
        })
      } else {
        let attrs = attributes
          .iter()
          .map(pair => " \{pair.0}=\"\{pair.1}\"")
          .to_array()
          .join("")
        changes.push(
          insertion(
            cell.source.node,
            "<a:tcPr xmlns:a=\"\{drawing_uri}\"\{attrs}/>",
          ),
        )
      }
    }
  }
  if !grow_rows.is_empty() {
    let reason = self.table_geometry_reason(object, self.selection)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let parent = object.source.parent_matrix()
    let sy = (parent.c * parent.c + parent.d * parent.d).sqrt()
    let mut extent = 0L
    // ONLYOFFICE's direction command raises each affected native row minimum to 20 mm.
    for r, row in table.rows {
      let native = if grow_rows.contains(r) {
        (720000.0 / sy).ceil().to_int64()
      } else {
        number(row.source.node.attribute("h").unwrap(), 1, 182880000).to_int64()
      }
      extent += native
      if grow_rows.contains(r) {
        changes.push(attribute_change(row.source, "h", native.to_string()))
      }
    }
    guard extent <= 182880000L && extent.to_double() * sy <= 182880000.5 else {
      @failure.reject("limit-exceeded", "Table extent exceeds 14400 points")
    }
    let transform = object.source.child("xfrm", uri=presentation_uri).unwrap()
    changes.push(
      attribute_change(
        transform.child("ext").unwrap(),
        "cy",
        extent.to_string(),
      ),
    )
  }
  if changes.is_empty() {
    return self.query()
  }
  let (candidate, edit) = self.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  self.commit(candidate, edit, self.selection, probe~, profile~)
  self.query()
}
