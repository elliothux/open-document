///|
pub(all) struct TableStyleElement {
  kind : String
  size : Int
  format : CellFormat
  vertical : CellBorder?
  horizontal : CellBorder?
} derive(Eq)

///|
pub extend TableStyleElement with Eq::{equal, not_equal}

///|
fn TableStyleElement::json(self : TableStyleElement) -> Json {
  {
    "kind": self.kind,
    "size": if self.kind.has_suffix("Stripe") {
      self.size
    } else {
      1
    },
    "format": self.format.patch_json(),
    "vertical": self.vertical
    .map(border => Json({ ..border, color: border.color.to_lower(), }))
    .unwrap_or(Json::null()),
    "horizontal": self.horizontal
    .map(border => Json({ ..border, color: border.color.to_lower(), }))
    .unwrap_or(Json::null()),
  }
}

///|
priv struct CustomTableStyle {
  name : String
  elements : Map[String, TableStyleElement]
  reason : String
}

///|
fn table_element_order() -> Array[String] {
  [
    "wholeTable", "firstColumnStripe", "secondColumnStripe", "firstRowStripe", "secondRowStripe",
    "lastColumn", "firstColumn", "headerRow", "totalRow", "firstHeaderCell", "lastHeaderCell",
    "firstTotalCell", "lastTotalCell",
  ]
}

///|
fn Session::custom_table_styles(
  self : Session,
  parts : Map[String, @xml.Document],
) -> Map[String, CustomTableStyle] raise @failure.Failure {
  let result : Map[String, CustomTableStyle] = Map([])
  guard self.styles_part(parts) is Some(path) else { return result }
  let tree = Tree::new(
    parts.get(path).unwrap_or_else(() => self.part_xml(path)),
  )
  let root = tree.root("styleSheet")
  guard tree.one(root.id, "tableStyles") is Some(parent) else { return result }
  let nodes = tree.all(parent.id, "tableStyle")
  guard nodes.length() <= 256 else {
    @failure.reject("limit-exceeded", "Custom table styles exceed 256")
  }
  let dxfs = tree
    .one(root.id, "dxfs")
    .map(node => tree.all(node.id, "dxf"))
    .unwrap_or([])
  let mut units = 0
  for node in nodes {
    let name = node.attribute("name").unwrap_or("")
    units += name.length()
    guard !name.is_empty() &&
      name.trim() == name &&
      name.iter().all(c => c >= ' ' && c != '\u007f') &&
      name.length() <= 255 &&
      units <= 65536 &&
      !result.contains(name.to_upper()) else {
      @failure.reject(
        "protected-content", "Invalid or duplicate custom table style name",
      )
    }
    let elements : Map[String, TableStyleElement] = Map([])
    let reason = try {
      conditional_node(
        tree,
        parent,
        ["count", "defaultTableStyle", "defaultPivotStyle"],
        ["tableStyle"],
      )
      conditional_node(tree, node, ["name", "pivot", "table", "count"], [
        "tableStyleElement",
      ])
      guard parent.text.trim().is_empty() && node.text.trim().is_empty() else {
        @failure.reject(
          "protected-content", "Unexpected custom table style text",
        )
      }
      guard flag(node, "table", fallback=true) else {
        @failure.reject(
          "protected-content", "Pivot-only style cannot format a table",
        )
      }
      ignore(flag(node, "pivot", fallback=true))
      let entries = tree.all(node.id, "tableStyleElement")
      guard entries.length() <= 13 &&
        node
        .attribute("count")
        .map(value => natural(value, 13) == entries.length())
        .unwrap_or(true) else {
        @failure.reject(
          "protected-content", "Invalid custom table style element count",
        )
      }
      for entry in entries {
        conditional_node(tree, entry, ["type", "size", "dxfId"], [])
        let kind = entry.attribute("type").unwrap_or("")
        let size = natural(entry.attribute("size").unwrap_or("1"), 1048576)
        guard table_element_order().contains(kind) &&
          !elements.contains(kind) &&
          entry.text.trim().is_empty() &&
          (!kind.has_suffix("Stripe") || size > 0) else {
          @failure.reject(
            "protected-content", "Unsupported custom table style element",
          )
        }
        let dxf = entry
          .attribute("dxfId")
          .map(value => {
            dxfs
            .get(natural(value, 4095))
            .unwrap_or_error(
              @failure.Failure(
                code="protected-content",
                message="Custom table style differential format is missing",
                part=path,
                offset=entry.start,
              ),
            )
          })
        let format = dxf
          .map(node => conditional_style(tree, node, self.theme, table=true))
          .unwrap_or(CellFormat::new())
        let inner = ["vertical", "horizontal"].map(side => {
          dxf
          .bind(node => tree.one(node.id, "border"))
          .bind(node => tree.one(node.id, side))
          .map(edge => {
            style: edge.attribute("style").unwrap_or("none"),
            color: tree
            .one(edge.id, "color")
            .map(node => conditional_color(tree, node, self.theme))
            .unwrap_or("000000"),
          })
        })
        elements[kind] = {
          kind,
          size,
          format,
          vertical: inner[0],
          horizontal: inner[1],
        }
      }
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    }
    result[name.to_upper()] = { name, elements, reason, }
  }
  result
}

///|
fn TableStyleElement::bounds(
  self : TableStyleElement,
  table : StructuredTable,
  address : Address,
  elements : Map[String, TableStyleElement],
) -> Range? {
  let bounds = table.range
  let body = {
    ..bounds,
    top: bounds.top + table.headers,
    bottom: bounds.bottom - table.totals,
  }
  let header = table.headers == 1 && address.row == bounds.top
  let total = table.totals == 1 && address.row == bounds.bottom
  let point : Range = {
    top: address.row,
    bottom: address.row,
    left: address.column,
    right: address.column,
  }
  match self.kind {
    "wholeTable" => Some(bounds)
    "firstColumn" if table.first_column && address.column == bounds.left =>
      Some({ ..bounds, right: bounds.left, })
    "lastColumn" if table.last_column && address.column == bounds.right =>
      Some({ ..bounds, left: bounds.right, })
    "headerRow" if header => Some({ ..bounds, bottom: bounds.top, })
    "totalRow" if total => Some({ ..bounds, top: bounds.bottom, })
    "firstHeaderCell" if header && address.column == bounds.left => Some(point)
    "lastHeaderCell" if header && address.column == bounds.right => Some(point)
    "firstTotalCell" if total && address.column == bounds.left => Some(point)
    "lastTotalCell" if total && address.column == bounds.right => Some(point)
    kind if kind.has_suffix("Stripe") && !header && !total => {
      let rows = kind.contains("Row")
      guard (if rows { table.row_stripes } else { table.column_stripes }) else {
        return None
      }
      let first = if rows { "firstRowStripe" } else { "firstColumnStripe" }
      let second = if rows { "secondRowStripe" } else { "secondColumnStripe" }
      let a = elements.get(first).map(entry => entry.size).unwrap_or(1)
      let b = elements.get(second).map(entry => entry.size).unwrap_or(1)
      let start = if rows { body.top } else { body.left }
      let position = if rows { address.row } else { address.column }
      let offset = (position - start) % (a + b)
      guard (offset < a) == (kind == first) else { return None }
      let low = position - offset + (if kind == first { 0 } else { a })
      let high = low + self.size - 1
      Some(
        if rows {
          { ..body, top: low, bottom: high.min(body.bottom), }
        } else {
          { ..body, left: low, right: high.min(body.right), }
        },
      )
    }
    _ => None
  }
}

///|
fn CustomTableStyle::applied(
  self : CustomTableStyle,
  table : StructuredTable,
  address : Address,
  rtl : Bool,
  direct : TableOverride,
  source : CellStyle,
) -> CellStyle {
  let mut style = source
  for kind in table_element_order() {
    guard self.elements.get(kind) is Some(element) &&
      element.bounds(table, address, self.elements) is Some(bounds) else {
      continue
    }
    let patch = element.format
    let borders = [patch.left, patch.right, patch.top, patch.bottom].mapi((
      side,
      border,
    ) => {
      if direct.borders[side] {
        return None
      }
      let outside = match side {
        0 => address.column == (if rtl { bounds.right } else { bounds.left })
        1 => address.column == (if rtl { bounds.left } else { bounds.right })
        2 => address.row == bounds.top
        _ => address.row == bounds.bottom
      }
      if outside {
        border
      } else if side < 2 {
        element.vertical
      } else {
        element.horizontal
      }
    })
    style = {
      underline: if direct.properties.contains("underline") {
        None
      } else {
        patch.underline
      },
      strike: if direct.properties.contains("strike") {
        None
      } else {
        patch.strike
      },
      script: if direct.properties.contains("script") {
        None
      } else {
        patch.script
      },
      bold: if direct.bold {
        None
      } else {
        patch.bold
      },
      color: if direct.color {
        None
      } else {
        patch.color
      },
      fill: if direct.fill {
        None
      } else {
        patch.fill
      },
      family: if direct.properties.contains("family") {
        None
      } else {
        patch.family
      },
      size: if direct.properties.contains("size") {
        None
      } else {
        patch.size
      },
      italic: if direct.properties.contains("italic") {
        None
      } else {
        patch.italic
      },
      numberFormat: if direct.properties.contains("numberFormat") {
        None
      } else {
        patch.numberFormat
      },
      horizontal: if direct.properties.contains("horizontal") {
        None
      } else {
        patch.horizontal
      },
      vertical: if direct.properties.contains("vertical") {
        None
      } else {
        patch.vertical
      },
      locked: None,
      formulaHidden: None,
      wrap: if direct.properties.contains("wrap") {
        None
      } else {
        patch.wrap
      },
      left: borders[0],
      right: borders[1],
      top: borders[2],
      bottom: borders[3],
    }.applied(style)
  }
  {
    ..style,
    border_priority: style.border_priority.mapi((side, value) => {
      if direct.borders[side] {
        value
      } else {
        0
      }
    }),
  }
}
