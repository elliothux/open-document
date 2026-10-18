///|
pub(all) struct TableStyleSettings {
  id : String
  first_row : Bool
  last_row : Bool
  first_column : Bool
  last_column : Bool
  band_rows : Bool
  band_columns : Bool
} derive(Eq)

///|
pub extend TableStyleSettings with Eq::{equal, not_equal}

///|
priv struct TableStyleBook {
  part : String?
  default_id : String
  styles : Map[String, Ref]
  reason : String
}

///|
priv struct TableStylePart {
  source : Ref
  text : Ref?
}

///|
let table_style_regions : Array[String] = [
  "wholeTbl", "band1H", "band2H", "band1V", "band2V", "lastCol", "firstCol", "lastRow",
  "firstRow", "seCell", "swCell", "neCell", "nwCell",
]

///|
fn read_table_styles(
  opc : @opc.Package,
  main : Tree,
  cache : Map[String, Tree],
  parts : Map[String, @xml.Document],
) -> TableStyleBook raise @failure.Failure {
  let builtins = builtin_table_styles()
  let styles : Map[String, Ref] = Map([])
  for node in builtins.all(builtins.document.nodes()[0].id, "tblStyle") {
    styles[node.attribute("styleId").unwrap().to_upper()] = {
      tree: builtins,
      node,
    }
  }
  let replacements : Map[String, Bytes] = Map([])
  for part, document in parts {
    replacements[part] = document.bytes()
  }
  let links = opc
    .relationships(replacements~)
    .filter(link => {
      link.owner == main.part && link.kind == relationship_uri + "/tableStyles"
    })
  table_profile(links.length() <= 1, "Multiple table style resources")
  guard links.get(0) is Some(link) else {
    return { part: None, default_id: "", styles, reason: "", }
  }
  table_profile(!link.external, "External table styles are protected")
  let tree = load_tree(opc, cache, link.target, parts~)
  let root = tree.root("tblStyleLst", uri=drawing_uri)
  table_profile(
    root.attributes.all(a => a.uri.is_empty() && a.name == "def"),
    "Unknown table style catalog attributes",
  )
  let nodes = tree.all(root.id, "tblStyle")
  table_profile(
    nodes.length() <= 256 &&
    tree.children.get(root.id).unwrap_or([]).length() == nodes.length(),
    "Unsupported table style catalog",
  )
  let seen : Map[String, Bool] = Map([])
  for node in nodes {
    let id = node.attribute("styleId").unwrap_or("").to_upper()
    table_profile(
      !id.is_empty() &&
      id.length() <= 80 &&
      !seen.contains(id) &&
      node.attribute("styleName").unwrap_or("").length() <= 1024,
      "Invalid or duplicate table style identity",
    )
    seen[id] = true
    styles[id] = { tree, node, }
  }
  {
    part: Some(link.target),
    default_id: root.attribute("def").unwrap_or("").to_upper(),
    styles,
    reason: "",
  }
}

///|
fn table_style_settings(
  properties : Ref?,
  book : TableStyleBook,
) -> TableStyleSettings raise @failure.Failure {
  let id = properties
    .bind(p => p.child("tableStyleId"))
    .map(p => p.node.text.trim().to_owned().to_upper())
    .unwrap_or(book.default_id)
  let enabled = fn(name : String) raise @failure.Failure {
    properties.map(p => flag(p.node, name)).unwrap_or(false)
  }
  {
    id,
    first_row: enabled("firstRow"),
    last_row: enabled("lastRow"),
    first_column: enabled("firstCol"),
    last_column: enabled("lastCol"),
    band_rows: enabled("bandRow"),
    band_columns: enabled("bandCol"),
  }
}

///|
fn table_style_parts(
  book : TableStyleBook,
  id : String,
) -> Map[String, TableStylePart] raise @failure.Failure {
  table_profile(book.reason.is_empty(), book.reason)
  let parts : Map[String, TableStylePart] = Map([])
  if id.is_empty() {
    return parts
  }
  guard book.styles.get(id.to_upper()) is Some(style) else {
    @failure.reject("unsupported-table", "Unknown table style: " + id)
  }
  table_profile(
    style.node.attributes.all(a => {
      a.uri.is_empty() && ["styleId", "styleName"].contains(a.name)
    }),
    "Unknown table style attributes",
  )
  style.table_children(table_style_regions)
  for name in table_style_regions {
    if style.child(name) is Some(region) {
      table_profile(
        region.node.attributes.is_empty(),
        "Unknown table region attributes",
      )
      region.table_children(["tcTxStyle", "tcStyle"])
      if region.child("tcStyle") is Some(cell) {
        table_profile(
          cell.node.attributes.is_empty(),
          "Unknown table cell style attributes",
        )
        cell.table_children(["tcBdr", "fill", "fillRef"])
        table_profile(
          !(cell.child("fill") is Some(_) && cell.child("fillRef") is Some(_)),
          "Combined table style fills",
        )
        if name != "wholeTbl" && cell.child("tcBdr") is Some(edges) {
          edges.table_children(["left", "top", "right", "bottom"])
        }
      }
      let text = table_style_text(region)
      let cell = region.child("tcStyle")
      let paint = cell.bind(cell => cell.child("fill")) is Some(_) ||
        cell.bind(cell => cell.child("fillRef")) is Some(_) ||
        cell
        .bind(cell => cell.child("tcBdr"))
        .map(edges => {
          !edges.tree.children.get(edges.node.id).unwrap_or([]).is_empty()
        })
        .unwrap_or(false)
      if text is Some(_) || paint {
        parts[name] = { source: region, text, }
      }
    }
  }
  parts
}

///|
fn table_style_layers(
  settings : TableStyleSettings,
  parts : Map[String, TableStylePart],
  row : Int,
  column : Int,
  last_row : Int,
  last_column : Int,
) -> Array[TableStylePart] {
  let names : Array[String] = ["wholeTbl"]
  if settings.band_rows {
    names.push(
      if (row - (if settings.first_row { 1 } else { 0 })) % 2 == 0 {
        "band1H"
      } else {
        "band2H"
      },
    )
  }
  if settings.band_columns {
    names.push(
      if (
          column -
          (if settings.first_column && parts.contains("firstCol") {
            1
          } else {
            0
          })
        ) %
        2 ==
        0 {
        "band1V"
      } else {
        "band2V"
      },
    )
  }
  for
    (enabled, condition, name) in [
      (settings.last_column, column == last_column, "lastCol"),
      (settings.first_column, column == 0, "firstCol"),
      (settings.last_row, row == last_row, "lastRow"),
      (settings.first_row, row == 0, "firstRow"),
      (
        settings.last_row && settings.last_column,
        row == last_row && column == last_column,
        "seCell",
      ),
      (
        settings.last_row && settings.first_column,
        row == last_row && column == 0,
        "swCell",
      ),
      (
        settings.first_row && settings.last_column,
        row == 0 && column == last_column,
        "neCell",
      ),
      (
        settings.first_row && settings.first_column,
        row == 0 && column == 0,
        "nwCell",
      ),
    ] {
    if enabled && condition {
      names.push(name)
    }
  }
  names.rev().filter_map(name => parts.get(name))
}
