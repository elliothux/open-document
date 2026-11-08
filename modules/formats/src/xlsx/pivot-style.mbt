///|
priv struct PivotPaintStyle {
  range : Range
  header : Bool
  total : Bool
  row_stripes : Bool
  column_stripes : Bool
  fill : String
  text : String
  edge : CellBorder
  stripe_edge : CellBorder
}

///|
fn Session::pivot_paint_styles(
  self : Session,
  parts : Map[String, @xml.Document],
  sheet~ : String? = None,
) -> ReadOnlyArray[PivotPaintStyle] raise @failure.Failure {
  if !self.workbook
    .nodes()
    .any(node => node.name == "pivotCaches" && node.uri == spreadsheet_uri) {
    return []
  }
  // SDK-created pivot definitions have no native style.
  let links = self.opc
    .relationships()
    .filter(link => {
      !link.external &&
      link.kind == relationship_uri + "pivotTable" &&
      !self.removed.contains(link.target) &&
      sheet.map(id => link.owner == id).unwrap_or(true)
    })
  guard links.length() <= 64 else {
    @failure.reject("limit-exceeded", "Pivot style count exceeds budget")
  }
  links.filter_map(link => {
    let tree = Tree::new(
      parts.get(link.target).unwrap_or_else(() => self.opc.xml(link.target)),
    )
    let root = tree.root("pivotTableDefinition")
    guard tree.one(root.id, "pivotTableStyleInfo") is Some(style) &&
      style.attribute("name").map(name => name.to_lower()) ==
      Some("pivotstylelight15") &&
      tree.one(root.id, "location") is Some(location) &&
      location.attribute("firstDataRow") == Some("1") &&
      location.attribute("firstDataCol") == Some("1") &&
      tree.one(root.id, "rowFields") is Some(rows) &&
      tree.all(rows.id, "field").length() == 1 &&
      tree.one(root.id, "rowItems") is Some(items) &&
      tree.one(root.id, "colFields") is None &&
      tree.one(root.id, "pageFields") is None else {
      return None
    }
    let range = Range::parse(location.attribute("ref").unwrap_or(""))
    let rows = tree.all(items.id, "i")
    // shortcut: apply the preset to a flat report until grouped regions are supported.
    guard range.right == range.left + 1 &&
      rows.length() == range.bottom - range.top else {
      return None
    }
    for at, row in rows {
      guard (match row.attribute("t") {
        None | Some("data") => true
        Some("grand") => at == rows.length() - 1
        _ => false
      }) else {
        return None
      }
    }
    Some(PivotPaintStyle::{
      range,
      header: flag(style, "showColHeaders"),
      total: rows
      .last()
      .map(row => row.attribute("t") == Some("grand"))
      .unwrap_or(false),
      row_stripes: flag(style, "showRowStripes"),
      column_stripes: flag(style, "showColStripes"),
      fill: color_tint(self.theme[0], -0.14999847407452621, truncate=true),
      text: self.theme[1],
      edge: {
        style: "thin",
        color: color_tint(self.theme[0], -0.34998626667073579, truncate=true),
      },
      stripe_edge: {
        style: "thin",
        color: color_tint(self.theme[0], -0.249977111117893, truncate=true),
      },
    })
  })
}

///|
fn PivotPaintStyle::applied(
  self : PivotPaintStyle,
  source : CellStyle,
  address : Address,
  direct : TableOverride,
) -> CellStyle {
  let header = self.header && address.row == self.range.top
  let total = self.total && address.row == self.range.bottom
  let body = address.row > self.range.top
  let row_stripe = body &&
    self.row_stripes &&
    (address.row - self.range.top) % 2 == 1
  let column_stripe = body &&
    self.column_stripes &&
    address.column == self.range.right
  let bold = header || total
  CellFormat::new(
    bold=if bold && !direct.bold { Some(true) } else { None },
    color=if bold && !direct.color { Some(self.text) } else { None },
    fill=if (bold || row_stripe || column_stripe) && !direct.fill {
      Some(self.fill)
    } else {
      None
    },
    left=if column_stripe && !direct.borders[0] {
      Some(self.stripe_edge)
    } else {
      None
    },
    right=if column_stripe && !direct.borders[1] {
      Some(self.stripe_edge)
    } else {
      None
    },
    top=if total && !direct.borders[2] { Some(self.edge) } else { None },
    bottom=if header && !direct.borders[3] { Some(self.edge) } else { None },
  ).applied(source)
}
