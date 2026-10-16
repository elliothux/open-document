///|
priv struct Cell {
  address : Address
  node : Int
  style : Int
  value : Value
  formula : String?
  group : Int?
  shared : Int?
  read_only : String
  calculation_supported : Bool
}

///|
priv struct Sheet {
  id : String
  name : String
  state : String
  document : @xml.Document
  cells : Map[String, Cell]
  rows : Map[Int, Int]
  merges : Array[Range]
  locked : Bool
  data : Int
  dimensions : Dimensions
  row_styles : Map[Int, Int]
  column_styles : Array[(Int, Int, Int)]
}

///|
fn Sheet::read(
  id : String,
  name : String,
  state : String,
  document : @xml.Document,
  strings : Array[(String, Bool)],
  style_count : Int,
) -> Sheet raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let data = tree
    .one(root.id, "sheetData")
    .unwrap_or_error(
      @failure.Failure(
        code="malformed-xlsx",
        message="Missing sheetData",
        part=id,
        offset=-1,
      ),
    )
  let locked = tree
    .one(root.id, "sheetProtection")
    .map(node => {
      let value = node.attribute("sheet").unwrap_or("0")
      guard ["0", "1", "true", "false"].contains(value) else {
        @failure.reject(
          "malformed-xlsx",
          "Invalid worksheet protection flag",
          part=id,
        )
      }
      value == "1" || value == "true"
    })
    .unwrap_or(false)
  let cells : Map[String, Cell] = Map([])
  let rows : Map[Int, Int] = Map([])
  let row_styles : Map[Int, Int] = Map([])
  let column_styles : Array[(Int, Int, Int)] = []
  if tree.one(root.id, "cols") is Some(cols) {
    for column in tree.all(cols.id, "col") {
      if column.attribute("style") is Some(style) {
        let first = natural(column.attribute("min").unwrap_or(""), 16384)
        let last = natural(column.attribute("max").unwrap_or(""), 16384)
        guard first > 0 && last >= first else {
          @failure.reject("malformed-xlsx", "Invalid styled column bounds")
        }
        column_styles.push((first, last, natural(style, style_count - 1)))
      }
    }
    column_styles.sort_by((a, b) => a.0.compare(b.0))
    for i in 1..<column_styles.length() {
      guard column_styles[i - 1].1 < column_styles[i].0 else {
        @failure.reject("malformed-xlsx", "Overlapping styled columns")
      }
    }
  }
  let mut previous_row = 0
  for row in tree.all(data.id, "row") {
    guard rows.length() < 100000 else {
      @failure.reject(
        "limit-exceeded",
        "Worksheet row count exceeds budget",
        part=id,
      )
    }
    let row_index = natural(
      row.attribute("r").unwrap_or((previous_row + 1).to_string()),
      1048576,
    )
    guard row_index > 0 && !rows.contains(row_index) else {
      @failure.reject("malformed-xlsx", "Duplicate or invalid row", part=id)
    }
    rows[row_index] = row.id
    if row.attribute("s") is Some(style) {
      row_styles[row_index] = natural(style, style_count - 1)
    }
    previous_row = row_index
    let mut previous_column = 0
    for node in tree.all(row.id, "c") {
      let address = match node.attribute("r") {
        Some(value) => Address::parse(value)
        None => { row: row_index, column: previous_column + 1, }
      }
      let key = address.name()
      guard address.row == row_index && !cells.contains(key) else {
        @failure.reject(
          "malformed-xlsx",
          "Duplicate cell or mismatched row",
          part=id,
        )
      }
      previous_column = address.column
      let style = node
        .attribute("s")
        .map(value => natural(value, style_count - 1))
        .unwrap_or_else(() => {
          row_styles
          .get(row_index)
          .unwrap_or(column_style(column_styles, address.column))
        })
      let kind = node.attribute("t").unwrap_or("n")
      let raw = tree.one(node.id, "v").map(node => node.text)
      let mut rich = false
      let mut shared : Int? = None
      let value = match kind {
        "n" => raw.map(value => Value::Number(number(value))).unwrap_or(Blank)
        "b" =>
          match raw {
            Some("1") => Boolean(true)
            Some("0") => Boolean(false)
            _ =>
              @failure.reject("malformed-xlsx", "Invalid boolean cell", part=id)
          }
        "e" => {
          guard raw is Some(error) &&
            [
              "#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A",
              "#GETTING_DATA",
            ].contains(error) else {
            @failure.reject("malformed-xlsx", "Invalid cell error", part=id)
          }
          Error(error)
        }
        "s" => {
          guard raw is Some(index) else {
            @failure.reject("malformed-xlsx", "Missing string index", part=id)
          }
          let index = natural(index, strings.length() - 1)
          shared = Some(index)
          let (text, is_rich) = strings[index]
          rich = is_rich
          Text(text)
        }
        "inlineStr" => {
          let inline = tree
            .one(node.id, "is")
            .unwrap_or_error(
              @failure.Failure(
                code="malformed-xlsx",
                message="Missing inline string",
                part=id,
                offset=-1,
              ),
            )
          let (text, is_rich) = tree.text(inline.id)
          rich = is_rich
          Text(text)
        }
        "str" =>
          raw.map(value => Value::Text(decode_text(value))).unwrap_or(Blank)
        _ => raw.map(value => Value::Text(value)).unwrap_or(Blank)
      }
      let formula_node = tree.one(node.id, "f")
      let formula = formula_node.map(node => node.text)
      let group = if formula_node is Some(node) &&
        node.attribute("t") == Some("shared") {
        Some(natural(node.attribute("si").unwrap_or(""), 2147483647))
      } else {
        None
      }
      let unknown = tree.children
        .get(node.id)
        .unwrap_or([])
        .any(child => {
          child.uri != spreadsheet_uri ||
          !["f", "v", "is", "extLst"].contains(child.name)
        }) ||
        node.attributes
        .iter()
        .any(attribute => {
          attribute.uri != "" || !["r", "s", "t"].contains(attribute.name)
        })
      let read_only = if locked {
        "Worksheet is protected"
      } else if rich {
        "Rich text cell is read-only"
      } else if unknown ||
        !["n", "b", "e", "s", "inlineStr", "str"].contains(kind) {
        "Unsupported cell editing semantics"
      } else if formula_node is Some(node) &&
        !["normal", "shared"].contains(node.attribute("t").unwrap_or("normal")) {
        "Unsupported formula group"
      } else {
        ""
      }
      cells[key] = {
        address,
        node: node.id,
        style,
        value,
        formula,
        group,
        shared,
        read_only,
        calculation_supported: ["n", "b", "e", "s", "inlineStr", "str"].contains(
          kind,
        ),
      }
      guard cells.length() <= 100000 else {
        @failure.reject(
          "limit-exceeded",
          "Worksheet cell budget exceeded",
          part=id,
        )
      }
    }
  }
  let merges : Array[Range] = []
  if tree.one(root.id, "mergeCells") is Some(parent) {
    for node in tree.all(parent.id, "mergeCell") {
      let range = Range::parse(node.attribute("ref").unwrap_or(""))
      guard merges.length() < 1024 &&
        !merges.any(existing => existing.intersects(range)) else {
        @failure.reject(
          "malformed-xlsx",
          "Overlapping or excessive merged cells",
          part=id,
        )
      }
      merges.push(range)
    }
  }
  let sheet : Sheet = {
    id,
    name,
    state,
    document,
    cells,
    rows,
    merges,
    locked,
    data: data.id,
    dimensions: read_dimensions(tree, root, data),
    row_styles,
    column_styles,
  }
  sheet.expand_shared(tree)
  sheet
}

///|
fn Sheet::cell_json(
  self : Sheet,
  address : Address,
  reason : String,
  calculated : Value?,
) -> Json raise @failure.Failure {
  let key = address.name()
  let cell = self.cells.get(key)
  let value = cell.map(cell => cell.value).unwrap_or(Blank)
  let formula = cell.bind(cell => cell.formula)
  let cell_reason = cell
    .map(cell => cell.read_only)
    .unwrap_or(if self.locked { "Worksheet is protected" } else { "" })
  {
    "address": key,
    "row": address.row,
    "column": address.column,
    "style": self.style_at(address),
    "value": value,
    "input": formula
    .map(source => "=" + source)
    .unwrap_or(
      match value {
        Text(text) => "'" + text
        _ => value.display()
      },
    ),
    "formula": formula.map(Json::string).unwrap_or(Json::null()),
    "cached": if formula is Some(_) {
      value.to_json()
    } else {
      Json::null()
    },
    "calculated": calculated
    .map(value => value.to_json())
    .unwrap_or(Json::null()),
    "calculation": if calculated is Some(_) {
      "calculated"
    } else if formula is Some(_) {
      if value == Blank {
        "uncalculated"
      } else {
        "imported-cache"
      }
    } else {
      "value"
    },
    "display": if formula is Some(_) && value == Blank && calculated is None {
      "Not calculated"
    } else {
      calculated.unwrap_or(value).display()
    },
    "readOnlyReason": if !reason.is_empty() {
      reason
    } else {
      cell_reason
    },
  }
}
