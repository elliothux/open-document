///|
priv struct TableColumn {
  id : Int32
  name : String
  formula : String?
  total_function : String?
  total_label : String?
  total_formula : String?
} derive(Eq)

///|
priv struct StructuredTable {
  sheet : String
  part : String
  id : Int32
  name : String
  range : Range
  headers : Int32
  totals : Int32
  columns : Array[TableColumn]
  style : String?
  first_column : Bool
  last_column : Bool
  row_stripes : Bool
  column_stripes : Bool
  style_reason : String
  filtering : Bool
  filter : AutoFilterState?
  sort : StoredSort?
  reason : String
} derive(Eq)

///|
fn read_table(
  sheet : Sheet,
  part : String,
  document : @xml.Document,
) -> StructuredTable raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("table")
  let name = root.attribute("displayName").unwrap_or("")
  validate_defined_name(name)
  let id = natural(root.attribute("id").unwrap_or(""), 2147483647)
  let range = native_range(root.attribute("ref").unwrap_or(""))
  let headers = natural(root.attribute("headerRowCount").unwrap_or("1"), 1)
  let totals = natural(root.attribute("totalsRowCount").unwrap_or("0"), 1)
  guard id > 0 &&
    range.bottom - range.top + 1 >= headers + totals &&
    !sheet.merges.any(merge => merge.intersects(range)) else {
    @failure.reject(
      "malformed-xlsx",
      "Invalid table identity, rows or merged range",
      part~,
    )
  }
  let parent = tree
    .one(root.id, "tableColumns")
    .unwrap_or_error(
      @failure.Failure(
        code="malformed-xlsx",
        message="Missing table columns",
        part~,
        offset=-1,
      ),
    )
  let columns : Array[TableColumn] = []
  let ids : Map[Int32, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  let mut units = name.length()
  for node in tree.all(parent.id, "tableColumn") {
    let id = natural(node.attribute("id").unwrap_or(""), 2147483647)
    let name = decode_text(node.attribute("name").unwrap_or(""))
    units += name.length()
    guard columns.length() < 4096 && units <= 65536 else {
      @failure.reject(
        "limit-exceeded",
        "Table column metadata exceeds budget",
        part~,
      )
    }
    guard id > 0 &&
      !ids.contains(id) &&
      !name.is_empty() &&
      name.length() <= 255 &&
      !names.contains(name.to_upper()) else {
      @failure.reject(
        "malformed-xlsx",
        "Invalid or duplicate table column",
        part~,
      )
    }
    let formula = tree
      .one(node.id, "calculatedColumnFormula")
      .map(node => node.text)
    let total_function = node.attribute("totalsRowFunction")
    let total_label = node.attribute("totalsRowLabel").map(decode_text)
    let total_formula = tree
      .one(node.id, "totalsRowFormula")
      .map(node => node.text)
    guard [formula, total_formula].all(value => {
        value.map(text => text.length() <= 8192).unwrap_or(true)
      }) &&
      total_label.map(text => text.length() <= 32767).unwrap_or(true) &&
      total_function.map(text => text.length() <= 255).unwrap_or(true) else {
      @failure.reject(
        "limit-exceeded",
        "Table formula or total metadata exceeds budget",
        part~,
      )
    }
    columns.push({
      id,
      name,
      formula,
      total_function,
      total_label,
      total_formula,
    })
    ids[id] = true
    names[name.to_upper()] = true
  }
  guard columns.length() == range.right - range.left + 1 &&
    parent
    .attribute("count")
    .map(value => natural(value, 4096) == columns.length())
    .unwrap_or(true) else {
    @failure.reject(
      "malformed-xlsx",
      "Table column count disagrees with its range",
      part~,
    )
  }
  let filtering = tree
    .one(root.id, "autoFilter")
    .map(node => !tree.all(node.id, "filterColumn").is_empty())
    .unwrap_or(false)
  let (filter, filter_reason) = try {
    let state = tree
      .one(root.id, "autoFilter")
      .map(node => {
        let state = read_filter_node(sheet, tree, node)
        guard headers == 1 &&
          state.bounds == Range::{ ..range, bottom: range.bottom - totals, } else {
          @failure.reject(
            "protected-content", "Table filter range must include its header and data without totals",
          )
        }
        state
      })
    (state, "")
  } catch {
    @failure.Failure(message~, ..) => (None, message)
  }
  let (sort, sort_reason) = try {
    let sort = read_sort_state(tree, root.id)
    guard sort
      .map(sort => {
        Range::{
          ..range,
          top: range.top + headers,
          bottom: range.bottom - totals,
        }.covers(sort.bounds)
      })
      .unwrap_or(true) else {
      @failure.reject(
        "protected-content", "Table sort state is outside its data range",
      )
    }
    (sort, "")
  } catch {
    @failure.Failure(message~, ..) => (None, message)
  }
  let reason = if !sort_reason.is_empty() {
    sort_reason
  } else if !filter_reason.is_empty() &&
    tree
    .one(root.id, "autoFilter")
    .map(node => {
      !tree.children.get(node.id).unwrap_or([]).is_empty() ||
      document.source()[node.start:node.end].contains("<!--") ||
      document.source()[node.start:node.end].contains("<?")
    })
    .unwrap_or(false) {
    filter_reason
  } else if root.attribute("tableType").unwrap_or("worksheet") != "worksheet" ||
    root.attribute("connectionId") is Some(_) ||
    tree.one(root.id, "extLst") is Some(_) ||
    tree
    .all(parent.id, "tableColumn")
    .any(node => {
      tree.one(node.id, "xmlColumnPr") is Some(_) ||
      tree.one(node.id, "extLst") is Some(_)
    }) {
    "Table connections or extensions require support"
  } else {
    ""
  }
  let style = tree.one(root.id, "tableStyleInfo")
  let style_reason = if !root.attributes.all(attribute => {
      attribute.uri.is_empty() &&
      [
        "id", "name", "displayName", "ref", "headerRowCount", "totalsRowCount", "totalsRowShown",
        "comment", "insertRow", "insertRowShift", "published", "tableType", "connectionId",
      ].contains(attribute.name)
    }) ||
    !tree.children
    .get(root.id)
    .unwrap_or([])
    .all(node => {
      node.uri == spreadsheet_uri &&
      ["autoFilter", "sortState", "tableColumns", "tableStyleInfo"].contains(
        node.name,
      )
    }) ||
    tree
    .all(parent.id, "tableColumn")
    .any(node => {
      !node.attributes.all(attribute => {
        attribute.uri.is_empty() &&
        ["id", "name", "uniqueName", "totalsRowFunction", "totalsRowLabel"].contains(
          attribute.name,
        )
      }) ||
      !tree.children
      .get(node.id)
      .unwrap_or([])
      .all(node => {
        node.uri == spreadsheet_uri &&
        ["calculatedColumnFormula", "totalsRowFormula"].contains(node.name)
      })
    }) ||
    style
    .map(node => {
      !node.attributes.all(attribute => {
        attribute.uri.is_empty() &&
        [
          "name", "showFirstColumn", "showLastColumn", "showRowStripes", "showColumnStripes",
        ].contains(attribute.name)
      }) ||
      !tree.children.get(node.id).unwrap_or([]).is_empty()
    })
    .unwrap_or(false) {
    "Table differential styles or metadata require rendering support"
  } else {
    ""
  }
  {
    sheet: sheet.id,
    part,
    id,
    name,
    range,
    headers,
    totals,
    columns,
    first_column: style
    .map(node => flag(node, "showFirstColumn"))
    .unwrap_or(false),
    last_column: style
    .map(node => flag(node, "showLastColumn"))
    .unwrap_or(false),
    row_stripes: style
    .map(node => flag(node, "showRowStripes"))
    .unwrap_or(false),
    column_stripes: style
    .map(node => flag(node, "showColumnStripes"))
    .unwrap_or(false),
    style_reason,
    filtering,
    filter,
    sort,
    style: style
    .bind(node => node.attribute("name"))
    .bind(name => if name.is_empty() { None } else { Some(name) }),
    reason,
  }
}

///|
fn Session::table_definitions(
  self : Session,
  sheets : Array[Sheet],
  workbook : @xml.Document,
  parts : Map[String, @xml.Document],
  removed~ : Array[String] = self.removed,
) -> Array[StructuredTable] raise @failure.Failure {
  let result : Array[StructuredTable] = []
  if !sheets.any(sheet => {
      let tree = Tree::new(sheet.document)
      tree.one(tree.root("worksheet").id, "tableParts") is Some(_)
    }) {
    return result
  }
  let relations = self.opc.relationships(
    replacements=self.replacements(sheets, workbook, parts),
    removed~,
  )
  let ids : Map[Int32, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  let paths : Map[String, Bool] = Map([])
  let mut columns = 0
  let mut formula_units = 0
  for sheet in sheets {
    let tree = Tree::new(sheet.document)
    if tree.one(tree.root("worksheet").id, "tableParts") is Some(parent) {
      let entries = tree.all(parent.id, "tablePart")
      guard parent
        .attribute("count")
        .map(value => natural(value, 256) == entries.length())
        .unwrap_or(true) else {
        @failure.reject(
          "malformed-xlsx", "Table part count disagrees with worksheet",
        )
      }
      for node in entries {
        guard result.length() < 256 else {
          @failure.reject(
            "limit-exceeded", "Workbook table count exceeds budget",
          )
        }
        let id = node
          .attribute(
            "id",
            uri=relationship_uri[:relationship_uri.length() - 1].to_owned(),
          )
          .unwrap_or("")
        guard relations
          .iter()
          .find_first(rel => rel.owner == sheet.id && rel.id == id)
          is Some(rel) &&
          !rel.external &&
          rel.kind == relationship_uri + "table" &&
          !paths.contains(rel.target) else {
          @failure.reject(
            "malformed-xlsx",
            "Invalid or shared table relationship",
            part=sheet.id,
          )
        }
        let document = parts
          .get(rel.target)
          .unwrap_or_else(() => self.opc.xml(rel.target))
        let table = read_table(sheet, rel.target, document)
        let table = if relations.any(relation => relation.owner == table.part) {
          { ..table, reason: "Table resource relationships require support", }
        } else {
          table
        }
        guard !ids.contains(table.id) &&
          !names.contains(table.name.to_upper()) &&
          !result.any(other => {
            other.sheet == table.sheet && other.range.intersects(table.range)
          }) else {
          @failure.reject(
            "malformed-xlsx",
            "Duplicate table identity or overlapping tables",
            part=rel.target,
          )
        }
        columns += table.columns.length()
        for column in table.columns {
          for
            text in [
              column.formula,
              column.total_function,
              column.total_label,
              column.total_formula,
            ] {
            formula_units += text.map(String::length).unwrap_or(0)
          }
        }
        guard columns <= 4096 else {
          @failure.reject(
            "limit-exceeded", "Workbook table columns exceed budget",
          )
        }
        guard formula_units <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Workbook table formula and total metadata exceeds budget",
          )
        }
        result.push(table)
        ids[table.id] = true
        names[table.name.to_upper()] = true
        paths[rel.target] = true
      }
    }
  }
  result
}

///|
fn Session::calculate(
  self : Session,
  sheets : Array[Sheet],
  previous : Calculation?,
  changed : Array[(Int32, Range)],
  workbook : @xml.Document,
  parts~ : Map[String, @xml.Document] = self.parts,
  removed~ : Array[String] = self.removed,
) -> Calculation raise @failure.Failure {
  Calculation::build(
    sheets,
    previous,
    changed,
    self.date1904,
    workbook,
    tables=self.table_definitions(sheets, workbook, parts, removed~),
  )
}
