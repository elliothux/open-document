///|
pub(all) struct PrintRange {
  area : String
  rows : String
  columns : String
} derive(Eq, ToJson)

///|
pub extend PrintRange with Eq::{equal, not_equal}

///|
pub extend PrintRange with ToJson::{to_json}

///|
fn print_area(value : String) -> Range raise @failure.Failure {
  guard value.length() <= 64 else {
    @failure.reject("invalid-address", "Print range exceeds address budget")
  }
  let ends = value.trim().split(":").to_array()
  guard ends.length() == 1 || ends.length() == 2 else {
    @failure.reject("invalid-address", "Expected one rectangular print range")
  }
  let first = formula_address(ends[0].to_owned()).address
  let last = formula_address(ends[ends.length() - 1].to_owned()).address
  Range::parse(first.name() + ":" + last.name())
}

///|
fn print_title(
  value : String,
  rows : Bool,
) -> (Int, Int) raise @failure.Failure {
  guard value.length() <= 32 else {
    @failure.reject("invalid-address", "Print title exceeds address budget")
  }
  let ends = value.trim().split(":").to_array()
  guard ends.length() == 2 else {
    @failure.reject(
      "invalid-address", "Expected a whole-row or whole-column interval",
    )
  }
  let parsed : Array[Int] = []
  for end in ends {
    let text = end.strip_prefix("$").unwrap_or(end).to_owned().to_upper()
    for offset in 0..<text.length() {
      guard (if rows {
        text[offset] >= 48 && text[offset] <= 57
      } else {
        text[offset] >= 65 && text[offset] <= 90
      }) else {
        @failure.reject(
          "invalid-address", "Expected a whole-row or whole-column interval",
        )
      }
    }
    let cell = Address::parse(if rows { "A" + text } else { text + "1" })
    parsed.push(if rows { cell.row } else { cell.column })
  }
  guard parsed[0] <= parsed[1] else {
    @failure.reject("invalid-address", "Print title endpoints must be ordered")
  }
  (parsed[0], parsed[1])
}

///|
fn print_column(index : Int) -> String raise @failure.Failure {
  let address : Address = { row: 1, column: index, }
  let name = address.name()
  name[:name.length() - 1].to_owned()
}

///|
fn PrintRange::normalized(
  self : PrintRange,
) -> PrintRange raise @failure.Failure {
  let title = fn(value : String, rows : Bool) -> String raise @failure.Failure {
    if value.trim().is_empty() {
      return ""
    }
    let (first, last) = print_title(value, rows)
    if rows {
      first.to_string() + ":" + last.to_string()
    } else {
      print_column(first) + ":" + print_column(last)
    }
  }
  {
    area: if self.area.trim().is_empty() {
      ""
    } else {
      print_area(self.area).name()
    },
    rows: title(self.rows, true),
    columns: title(self.columns, false),
  }
}

///|
fn Session::print_names(
  self : Session,
  index : Int,
) -> Array[@xml.Node] raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  guard tree.one(tree.root("workbook").id, "definedNames") is Some(parent) else {
    return []
  }
  let names : Array[@xml.Node] = []
  for node in tree.all(parent.id, "definedName") {
    if !["_xlnm.Print_Area", "_xlnm.Print_Titles"].contains(
        node.attribute("name").unwrap_or(""),
      ) {
      continue
    }
    guard node.attribute("localSheetId") is Some(scope) else {
      @failure.reject(
        "unsupported-print", "Unscoped print definitions are protected",
      )
    }
    if natural(scope, self.sheets.length() - 1) != index {
      continue
    }
    guard !names.any(other => other.attribute("name") == node.attribute("name")) &&
      tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.opening_end <= node.closing_start &&
      !self.workbook.source()[node.opening_end:node.closing_start].contains("<") &&
      node.attributes.all(a => a.uri.is_empty()) else {
      @failure.reject(
        "unsupported-print", "Ambiguous or extended print definitions are protected",
      )
    }
    names.push(node)
  }
  names
}

///|
fn Session::read_print_range(
  self : Session,
  index : Int,
) -> PrintRange raise @failure.Failure {
  let mut area = ""
  let mut rows = ""
  let mut columns = ""
  for node in self.print_names(index) {
    let is_area = node.attribute("name") == Some("_xlnm.Print_Area")
    let spans : Array[(Int, Int)] = []
    let tokens = formula_tokens(node.text, spans~)
    let mut start = 0
    for cursor, token in tokens {
      if !(token is Operator(",") || token is End) {
        continue
      }
      guard cursor >= start + 3 &&
        tokens[start + 1] is Operator("!") &&
        (match tokens[start] {
          Word(name) | Quoted(name, true) =>
            name.to_lower() == self.sheets[index].name.to_lower()
          _ => false
        }) else {
        @failure.reject(
          "unsupported-print", "Print definitions must reference their own worksheet",
        )
      }
      let value = node.text[spans[start + 2].0:spans[cursor - 1].1].to_owned()
      if is_area {
        guard area.is_empty() else {
          @failure.reject(
            "unsupported-print", "Multiple print areas require separate-area pagination",
          )
        }
        area = print_area(value).name()
      } else {
        let ends = value.split(":").to_array()
        guard ends.length() == 2 else {
          @failure.reject(
            "unsupported-print", "Print titles require whole rows or columns",
          )
        }
        let head = ends[0].strip_prefix("$").unwrap_or(ends[0])
        let by_row = head.length() > 0 && head[0] >= 48 && head[0] <= 57
        if by_row {
          guard rows.is_empty() else {
            @failure.reject("unsupported-print", "Duplicate print title rows")
          }
          rows = value
        } else {
          guard columns.is_empty() else {
            @failure.reject(
              "unsupported-print", "Duplicate print title columns",
            )
          }
          columns = value
        }
      }
      start = cursor + 1
    }
  }
  ({ area, rows, columns, } : PrintRange).normalized()
}

///|
fn Session::print_range_query(self : Session, index : Int) -> Json {
  let (settings, reason) = (
    self.read_print_range(index),
    self.print_range_reason(index),
  ) catch {
    @failure.Failure(message~, ..) =>
      (({ area: "", rows: "", columns: "", } : PrintRange), message)
  }
  let json = settings.to_json()
  if json is Object(fields) {
    fields["readOnlyReason"] = Json(reason)
  }
  json
}

///|
fn Session::print_range_reason(
  self : Session,
  index : Int,
) -> String raise @failure.Failure {
  let reason = self.dimension_reason(self.sheets[index])
  if !reason.is_empty() {
    return reason
  }
  let tree = Tree::new(self.workbook)
  if tree
    .one(tree.root("workbook").id, "workbookProtection")
    .map(n => flag(n, "lockStructure"))
    .unwrap_or(false) {
    "Workbook structure is protected"
  } else {
    ""
  }
}

///|
fn Session::set_print_range(
  self : Session,
  id : String,
  settings : PrintRange,
) -> Json raise @failure.Failure {
  let settings = settings.normalized()
  let index = self.sheet_index(id)
  let reason = self.print_range_reason(index)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let tree = Tree::new(self.workbook)
  let root = tree.root("workbook")
  if self.read_print_range(index) == settings {
    return self.query()
  }
  let names = self.print_names(index)
  let quoted = "'" +
    self.sheets[index].name.replace_all(old="'", new="''") +
    "'!"
  let area = if settings.area.is_empty() {
    ""
  } else {
    let bounds = print_area(settings.area)
    quoted +
    "$" +
    print_column(bounds.left) +
    "$" +
    bounds.top.to_string() +
    ":$" +
    print_column(bounds.right) +
    "$" +
    bounds.bottom.to_string()
  }
  let titles : Array[String] = []
  for (value, by_row) in [(settings.columns, false), (settings.rows, true)] {
    if !value.is_empty() {
      let (first, last) = print_title(value, by_row)
      titles.push(
        quoted +
        "$" +
        (if by_row { first.to_string() } else { print_column(first) }) +
        ":$" +
        (if by_row { last.to_string() } else { print_column(last) }),
      )
    }
  }
  let changes : Array[@xml.SourceChange] = []
  let added = StringBuilder()
  for
    (name, value) in [
      ("_xlnm.Print_Area", area),
      ("_xlnm.Print_Titles", titles.join(",")),
    ] {
    if names.iter().find_first(n => n.attribute("name") == Some(name))
      is Some(node) {
      if value.is_empty() {
        changes.push(sheet_node_removal(tree, node))
      } else if value != node.text {
        changes.push({
          node: node.id,
          offset: node.opening_end - node.start,
          length: node.closing_start - node.opening_end,
          xml: @xml.escape_text(value),
        })
      }
    } else if !value.is_empty() {
      added.write_string(
        "<od:definedName xmlns:od=\"\{spreadsheet_uri}\" name=\"\{name}\" localSheetId=\"\{index}\">\{@xml.escape_text(value)}</od:definedName>",
      )
    }
  }
  let markup = added.to_string()
  if !markup.is_empty() {
    if tree.one(root.id, "definedNames") is Some(parent) {
      changes.push(insertion(parent, markup))
    } else {
      let markup = "<od:definedNames xmlns:od=\"\{spreadsheet_uri}\">\{markup}</od:definedNames>"
      let after = [
        "calcPr", "oleSize", "customWorkbookViews", "pivotCaches", "smartTagPr",
        "smartTagTypes", "webPublishing", "fileRecoveryPr", "webPublishObjects",
        "extLst",
      ]
      changes.push(
        if tree.children
          .get(root.id)
          .unwrap_or([])
          .iter()
          .find_first(n => after.contains(n.name))
          is Some(next) {
          {
            node: root.id,
            offset: next.start - root.start,
            length: 0,
            xml: markup,
          }
        } else {
          insertion(root, markup)
        },
      )
    }
  }
  let (workbook, edit) = self.workbook.edit_source(changes)
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    self.sheets.copy(),
    workbook,
    self.calculation.unwrap(),
    [(self.main, edit)],
    self.selection,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
