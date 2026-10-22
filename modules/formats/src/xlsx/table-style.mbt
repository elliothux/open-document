///|
priv struct TableOverride {
  bold : Bool
  color : Bool
  fill : Bool
  borders : Array[Bool]
  properties : Array[String]
}

///|
priv struct TableStyles {
  tables : Array[StructuredTable]
  overridden : Array[TableOverride]
  colors : Array[Array[String]]
  reason : String
  diagnostic : String
  custom : Map[String, CustomTableStyle]
}

///|
fn TableStyles::empty() -> TableStyles {
  {
    tables: [],
    overridden: [],
    colors: [],
    reason: "",
    diagnostic: "",
    custom: Map([]),
  }
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
    properties: [],
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
  let custom = self.custom_table_styles(parts)
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
            properties: [
              "family", "size", "italic", "underline", "strike", "script", "numberFormat",
              "horizontal", "vertical", "wrap", "indent", "shrinkToFit",
            ].filter(property => {
              match property {
                "family"
                | "size"
                | "italic"
                | "underline"
                | "strike"
                | "script" =>
                  font
                  .map(node => {
                    tree.one(
                      node.id,
                      match property {
                        "family" => "name"
                        "size" => "sz"
                        "underline" => "u"
                        "strike" => "strike"
                        "script" => "vertAlign"
                        _ => "i"
                      },
                    )
                    is Some(_)
                  })
                  .unwrap_or(false)
                "numberFormat" =>
                  flag(
                    node,
                    "applyNumberFormat",
                    fallback=node.attribute("numFmtId").unwrap_or("0") != "0",
                  )
                _ =>
                  tree
                  .one(node.id, "alignment")
                  .map(node => {
                    node.attribute(
                      if property == "wrap" {
                        "wrapText"
                      } else {
                        property
                      },
                    )
                    is Some(_)
                  })
                  .unwrap_or(false)
              }
            }),
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
  }
  for table in tables {
    work.spend()
    if !table.reason.is_empty() {
      reason = table.reason
    }
    if !table.style_reason.is_empty() {
      reason = table.style_reason
    }
    if table.style is Some(name) {
      if custom.get(name.to_upper()) is Some(style) {
        if !style.reason.is_empty() {
          reason = style.reason
        }
      } else if table_style_index(Some(name)) is None {
        reason = "Table style requires rendering support: " + name
      }
    }
  }
  {
    tables,
    overridden,
    colors: [1, 4, 5, 6, 7, 8, 9].map(index => {
      [
        self.theme[0],
        self.theme[1],
        self.theme[index],
        if index == 1 {
          color_tint(self.theme[0], -0.14999847407452621)
        } else {
          color_tint(self.theme[index], 0.79998168889431442)
        },
        if index == 1 {
          self.theme[1]
        } else {
          color_tint(self.theme[index], 0.39997558519241921)
        },
        if index == 1 {
          color_tint(self.theme[0], -0.34998626667073579)
        } else {
          color_tint(self.theme[index], 0.59999389629810485)
        },
        color_tint(self.theme[0], -0.14999847407452621),
        if index == 1 {
          self.theme[1]
        } else {
          color_tint(self.theme[index], -0.249977111117893)
        },
        if index == 1 {
          color_tint(self.theme[1], 0.14999847407452621)
        } else {
          color_tint(self.theme[index], -0.499984740745262)
        },
        if index == 1 {
          color_tint(self.theme[1], 0.44999542222357858)
        } else {
          self.theme[index]
        },
        if index == 1 {
          color_tint(self.theme[1], 0.249977111117893)
        } else {
          color_tint(self.theme[index], -0.249977111117893)
        },
      ]
    }),
    reason,
    diagnostic,
    custom,
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
    if table.range.contains(address) &&
      table.style.bind(name => self.custom.get(name.to_upper())) is Some(custom) {
      return custom.applied(table, address, sheet.view.rtl, direct, style)
    }
    guard table_style_index(table.style) is Some(index) &&
      table.range.contains(address) else {
      continue
    }
    // Native groups repeat seven palettes; the final four Dark styles pair accents.
    let family = index / 7
    let colors = self.colors[if family == 8 {
        [0, 1, 3, 5][index - 56]
      } else {
        index % 7
      }]
    let header = table.headers == 1 && address.row == table.range.top
    let total = table.totals == 1 && address.row == table.range.bottom
    let emphasized = (table.first_column && address.column == table.range.left) ||
      (table.last_column && address.column == table.range.right)
    let bold = (header && family != 8) || (total && family != 2) || emphasized
    let font = if direct.bold {
      style.font
    } else {
      CellFormat::new(bold=if bold { Some(true) } else { None }).applied(style).font
    }
    let striped = !header &&
      !total &&
      (
        (
          table.row_stripes &&
          (address.row - table.range.top - table.headers) % 2 == 0
        ) ||
        (table.column_stripes && (address.column - table.range.left) % 2 == 0)
      )
    let light_text = match family {
      0 => header
      1 => header || total || emphasized
      2 => header || emphasized
      5 => header
      7 => true
      8 => header
      _ => false
    }
    let fill = if direct.fill {
      style.fill
    } else {
      match family {
        0 => if header { colors[2] } else if striped { colors[3] } else { "" }
        1 =>
          if header || total || emphasized {
            colors[2]
          } else if striped {
            colors[5]
          } else {
            colors[3]
          }
        2 =>
          if header || emphasized {
            colors[2]
          } else if striped {
            colors[6]
          } else {
            ""
          }
        3 => if striped { colors[5] } else { colors[3] }
        5 => if header { colors[2] } else { "" }
        7 =>
          if header {
            colors[1]
          } else if total {
            colors[8]
          } else if emphasized || striped {
            colors[10]
          } else {
            colors[9]
          }
        8 =>
          if header {
            self.colors[[0, 2, 4, 6][index - 56]][2]
          } else if striped {
            colors[5]
          } else {
            colors[3]
          }
        _ => if striped { colors[3] } else { "" }
      }
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
        2 => address.row == table.range.top
        _ => address.row == table.range.bottom
      }
      borders[side] = match family {
        0 =>
          if total && side == 2 {
            { style: "double", color: colors[2], }
          } else {
            let present = outside || side == 2
            {
              style: if present {
                "thin"
              } else {
                "none"
              },
              color: if present {
                colors[4]
              } else {
                "000000"
              },
            }
          }
        1 => {
          let thick = (header && side == 3) || (total && side == 2)
          {
            style: if thick {
              "thick"
            } else if !outside {
              "thin"
            } else {
              "none"
            },
            color: colors[0],
          }
        }
        2 => {
          let medium = (outside && side >= 2) || (header && side == 3)
          {
            style: if total && side == 2 {
              "double"
            } else if medium {
              "medium"
            } else if index % 7 == 0 {
              "thin"
            } else {
              "none"
            },
            color: colors[1],
          }
        }
        3 =>
          {
            style: if total && side == 2 {
              "medium"
            } else {
              "thin"
            },
            color: if total && side == 2 {
              colors[2]
            } else {
              colors[4]
            },
          }
        4 => {
          let present = (side == 2 && (outside || total)) ||
            (side == 3 && (outside || header))
          { style: if present { "thin" } else { "none" }, color: colors[2], }
        }
        5 => {
          let data = !header && !total
          let present = outside ||
            (
              data &&
              (
                (side == 2 && table.row_stripes) ||
                (side == 0 && table.column_stripes)
              )
            )
          {
            style: if total && side == 2 {
              "double"
            } else if present {
              "thin"
            } else {
              "none"
            },
            color: colors[2],
          }
        }
        6 =>
          {
            style: if total && side == 2 {
              "double"
            } else if header && side == 3 {
              "medium"
            } else {
              "thin"
            },
            color: colors[2],
          }
        7 => {
          let separated = (
              table.first_column &&
              address.column == table.range.left &&
              side == 1
            ) ||
            (
              table.last_column &&
              address.column == table.range.right &&
              side == 0
            )
          let present = separated ||
            (header && side == 3) ||
            (total && side == 2)
          if present {
            { style: "medium", color: colors[0], }
          } else {
            border_priority[side] = style.border_priority[side]
            style.borders[side]
          }
        }
        _ =>
          if total && side == 2 {
            { style: "double", color: colors[1], }
          } else {
            border_priority[side] = style.border_priority[side]
            style.borders[side]
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
      } else if family == 4 {
        colors[7]
      } else if light_text {
        colors[0]
      } else if family == 8 && !total && !emphasized {
        style.color
      } else {
        colors[1]
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
  parts~ : Map[String, @xml.Document] = self.parts,
) -> Array[String] raise @failure.Failure {
  let keys : Array[String] = []
  for style in styles {
    if !keys.contains(style.font) {
      keys.push(style.font)
    }
  }
  if tables.any(table => {
      table_style_index(table.style) is Some(index) &&
      (
        (table.headers == 1 && index / 7 != 8) ||
        (table.totals == 1 && index / 7 != 2) ||
        table.first_column ||
        table.last_column
      )
    }) {
    let font = CellFormat::new(bold=Some(true)).applied(styles[0]).font
    if !keys.contains(font) {
      keys.push(font)
    }
  }
  let custom = self.custom_table_styles(parts)
  let used : Map[String, Bool] = Map([])
  let fonts : Map[String, Bool] = Map(keys.map(key => (key, true)))
  let mut work = 0
  for table in tables {
    guard table.style is Some(name) &&
      !used.contains(name.to_upper()) &&
      custom.get(name.to_upper()) is Some(style) &&
      style.reason.is_empty() else {
      continue
    }
    used[name.to_upper()] = true
    for kind in table_element_order() {
      guard style.elements.get(kind) is Some(element) &&
        (
          element.format.family is Some(_) ||
          element.format.bold is Some(_) ||
          element.format.italic is Some(_)
        ) else {
        continue
      }
      for key in fonts.keys().to_array() {
        work += 1
        guard work <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Custom table font variants exceed work budget",
          )
        }
        let next = element.format.applied({ ..default_style(), font: key, }).font
        if !fonts.contains(next) {
          fonts[next] = true
          keys.push(next)
          guard keys.length() <= 4096 else {
            @failure.reject(
              "limit-exceeded", "Workbook font keys exceed budget",
            )
          }
        }
      }
    }
  }
  for key in self.drawing_font_keys(parts) {
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  guard keys.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Workbook font keys exceed budget")
  }
  keys
}
