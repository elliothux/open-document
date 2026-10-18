///|
priv struct TableOverride {
  bold : Bool
  color : Bool
  fill : Bool
  borders : Array[Bool]
}

///|
priv struct TableStyles {
  tables : Array[StructuredTable]
  overridden : Array[TableOverride]
  colors : Array[String]
  reason : String
  diagnostic : String
}

///|
fn TableStyles::empty() -> TableStyles {
  { tables: [], overridden: [], colors: [], reason: "", diagnostic: "", }
}

///|
fn Session::table_styles(
  self : Session,
  sheet : Sheet,
  work : FormulaWork,
  parts : Map[String, @xml.Document],
) -> TableStyles raise @failure.Failure {
  let tables = work.names.tables.filter(table => table.sheet == sheet.id)
  let none : TableOverride = {
    bold: false,
    color: false,
    fill: false,
    borders: [false, false, false, false],
  }
  let mut overridden = [none]
  let mut reason = ""
  let tree = Tree::new(sheet.document)
  let diagnostic = tree
    .one(tree.root("worksheet").id, "tableParts")
    .map(node => node.qualified)
    .unwrap_or("")
  if tree.one(tree.root("worksheet").id, "tableParts") is Some(parent) {
    if !parent.attributes.all(a => a.uri.is_empty() && a.name == "count") ||
      !tree.children
      .get(parent.id)
      .unwrap_or([])
      .all(node => {
        node.uri == spreadsheet_uri &&
        node.name == "tablePart" &&
        node.attributes.all(a => {
          a.name == "id" &&
          a.uri == relationship_uri[:relationship_uri.length() - 1].to_owned()
        })
      }) {
      reason = "Unknown table part metadata requires rendering support"
    }
    if tables.is_empty() && !tree.all(parent.id, "tablePart").is_empty() {
      reason = "Table definitions require calculation support"
    }
  }
  if tables.is_empty() {
    return { ..TableStyles::empty(), reason, diagnostic, }
  }
  if self.styles_part(parts) is Some(part) {
    let document = parts.get(part).unwrap_or_else(() => self.opc.xml(part))
    let tree = Tree::new(document)
    let root = tree.root("styleSheet")
    let fonts = tree
      .one(root.id, "fonts")
      .map(node => tree.all(node.id, "font"))
      .unwrap_or([])
    let borders = tree
      .one(root.id, "borders")
      .map(node => tree.all(node.id, "border"))
      .unwrap_or([])
    if tree.one(root.id, "cellXfs") is Some(parent) {
      overridden = tree
        .all(parent.id, "xf")
        .map(node => {
          let font_id = natural(node.attribute("fontId").unwrap_or("0"), 4095)
          let border_id = natural(
            node.attribute("borderId").unwrap_or("0"),
            4095,
          )
          let font = if flag(node, "applyFont", fallback=font_id != 0) {
            fonts.get(font_id)
          } else {
            None
          }
          let border = if flag(node, "applyBorder", fallback=border_id != 0) {
            borders.get(border_id)
          } else {
            None
          }
          TableOverride::{
            bold: font
            .map(node => tree.one(node.id, "b") is Some(_))
            .unwrap_or(false),
            color: font
            .map(node => tree.one(node.id, "color") is Some(_))
            .unwrap_or(false),
            fill: flag(
              node,
              "applyFill",
              fallback=node.attribute("fillId").unwrap_or("0") != "0",
            ),
            borders: ["left", "right", "top", "bottom"].map(side => {
              border
              .bind(node => tree.one(node.id, side))
              .bind(node => node.attribute("style"))
              .map(style => style != "none")
              .unwrap_or(false)
            }),
          }
        })
    }
    if tree.one(root.id, "tableStyles") is Some(parent) &&
      tree
      .all(parent.id, "tableStyle")
      .any(node => tables.any(table => table.style == node.attribute("name"))) {
      reason = "Custom table styles require rendering support"
    }
  }
  for table in tables {
    work.spend()
    if !table.reason.is_empty() {
      reason = table.reason
    }
    if !table.style_reason.is_empty() {
      reason = table.style_reason
    }
    if table.style is Some(name) && name != "TableStyleMedium2" {
      reason = "Table style requires rendering support: " + name
    }
  }
  {
    tables,
    overridden,
    colors: [
      self.theme[0],
      self.theme[1],
      self.theme[4],
      color_tint(self.theme[4], 0.79998168889431442),
      color_tint(self.theme[4], 0.39997558519241921),
    ],
    reason,
    diagnostic,
  }
}

///|
fn TableStyles::renders(
  self : TableStyles,
  diagnostic : String,
  sheet : String,
) -> Bool {
  !self.diagnostic.is_empty() &&
  self.reason.is_empty() &&
  diagnostic == "unrendered:" + sheet + ":" + self.diagnostic
}

///|
fn TableStyles::applied(
  self : TableStyles,
  style : CellStyle,
  sheet : Sheet,
  address : Address,
) -> CellStyle raise @failure.Failure {
  if self.tables.is_empty() || !self.reason.is_empty() {
    return style
  }
  let direct = self.overridden[sheet.style_at(address)]
  for table in self.tables {
    // shortcut: Add other built-in styles with their native differential definitions.
    if table.style != Some("TableStyleMedium2") ||
      !table.range.contains(address) {
      continue
    }
    let header = table.headers == 1 && address.row == table.range.top
    let total = table.totals == 1 && address.row == table.range.bottom
    let bold = header ||
      total ||
      (table.first_column && address.column == table.range.left) ||
      (table.last_column && address.column == table.range.right)
    let font = if direct.bold {
      style.font
    } else {
      CellFormat::new(bold=if bold { Some(true) } else { None }).applied(style).font
    }
    let fill = if direct.fill {
      style.fill
    } else if header {
      self.colors[2]
    } else if !total &&
      (
        (
          table.row_stripes &&
          (address.row - table.range.top - table.headers) % 2 == 0
        ) ||
        (table.column_stripes && (address.column - table.range.left) % 2 == 0)
      ) {
      self.colors[3]
    } else {
      ""
    }
    let borders = style.borders.copy()
    let border_priority = style.border_priority.copy()
    for side in 0..<4 {
      if direct.borders[side] {
        continue
      }
      border_priority[side] = 0
      let outside = match side {
        0 =>
          address.column ==
          (if sheet.view.rtl { table.range.right } else { table.range.left })
        1 =>
          address.column ==
          (if sheet.view.rtl { table.range.left } else { table.range.right })
        2 => true
        _ => address.row == table.range.bottom
      }
      borders[side] = if total && side == 2 {
        { style: "double", color: self.colors[2], }
      } else {
        {
          style: if outside {
            "thin"
          } else {
            "none"
          },
          color: if outside {
            self.colors[4]
          } else {
            "000000"
          },
        }
      }
    }
    return {
      ..style,
      font,
      fill,
      borders,
      border_priority,
      color: if direct.color {
        style.color
      } else if header {
        self.colors[0]
      } else {
        self.colors[1]
      },
    }
  }
  style
}

///|
fn Session::font_keys(
  self : Session,
  styles~ : Array[CellStyle] = self.styles,
  tables~ : Array[StructuredTable] = self.formula_names().tables,
) -> Array[String] raise @failure.Failure {
  let keys : Array[String] = []
  for style in styles {
    if !keys.contains(style.font) {
      keys.push(style.font)
    }
  }
  if tables.any(table => {
      table.style == Some("TableStyleMedium2") &&
      (
        table.headers == 1 ||
        table.totals == 1 ||
        table.first_column ||
        table.last_column
      )
    }) {
    let font = CellFormat::new(bold=Some(true)).applied(styles[0]).font
    if !keys.contains(font) {
      keys.push(font)
    }
  }
  guard keys.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Workbook font keys exceed budget")
  }
  keys
}
