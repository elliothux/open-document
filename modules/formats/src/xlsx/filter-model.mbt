///|
pub(all) struct FilterValues {
  column : Int
  values : Array[String]
  blank : Bool
} derive(Eq)

///|
pub(all) struct FilterSettings {
  range : String
  columns : Array[FilterValues]
} derive(Eq)

///|
pub extend FilterValues with Eq::{equal, not_equal}

///|
pub extend FilterSettings with Eq::{equal, not_equal}

///|
priv struct AutoFilterState {
  settings : FilterSettings
  bounds : Range
  manual : Array[Int]
  filtered : Array[Int]
  tracked : Bool
  flags : Map[Int, Array[(String, String)]]
}

///|
let filter_state_uri = "urn:open-document:xlsx:filter-state"

///|
fn filter_rows(
  text : String,
  range : Range,
) -> Array[Int] raise @failure.Failure {
  let result : Array[Int] = []
  for token in text.split(" ") {
    if token.is_empty() {
      continue
    }
    let row = natural(token.to_owned(), 1048576)
    guard row > range.top &&
      row <= range.bottom &&
      !result.contains(row) &&
      result.length() < 4096 else {
      @failure.reject(
        "protected-content", "Invalid filter visibility provenance",
      )
    }
    result.push(row)
  }
  result.sort()
  result
}

///|
fn filter_settings(settings : FilterSettings) -> Range raise @failure.Failure {
  let range = Range::parse(settings.range)
  guard range.bottom > range.top &&
    (range.bottom - range.top + 1).to_int64() *
    (range.right - range.left + 1).to_int64() <=
    4096 &&
    settings.columns.length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Filters require a header and at most 4096 cells and 256 columns",
    )
  }
  let seen : Map[Int, Bool] = Map([])
  let mut units = 0
  for column in settings.columns {
    guard column.column >= range.left &&
      column.column <= range.right &&
      !seen.contains(column.column) &&
      column.values.length() <= 4096 else {
      @failure.reject("invalid-operation", "Invalid or duplicate filter column")
    }
    seen[column.column] = true
    let values : Map[String, Bool] = Map([])
    for value in column.values {
      units += value.length()
      guard value.length() <= 32767 &&
        @xml.valid_text(value) &&
        !values.contains(value) &&
        units <= 1048576 else {
        @failure.reject(
          "invalid-operation", "Invalid filter values or text budget",
        )
      }
      values[value] = true
    }
  }
  range
}

///|
fn filter_attributes(
  node : @xml.Node,
  names : Array[String],
) -> Unit raise @failure.Failure {
  guard node.attributes.all(a => a.uri.is_empty() && names.contains(a.name)) &&
    node.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown filter metadata is protected")
  }
}

///|
fn read_filter(sheet : Sheet) -> AutoFilterState? raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  guard tree.one(tree.root("worksheet").id, "autoFilter") is Some(root) else {
    return None
  }
  filter_attributes(root, ["ref"])
  let source = sheet.document.source()[root.start:root.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject("protected-content", "Opaque filter source is protected")
  }
  let range = Range::parse(root.attribute("ref").unwrap_or(""))
  ignore(filter_settings({ range: range.name(), columns: [], }))
  let columns : Array[FilterValues] = []
  let flags : Map[Int, Array[(String, String)]] = Map([])
  let mut manual : Array[Int] = []
  let mut filtered : Array[Int] = []
  let mut tracked = false
  for node in tree.children.get(root.id).unwrap_or([]) {
    guard node.uri == spreadsheet_uri else {
      @failure.reject(
        "protected-content", "Unknown filter content is protected",
      )
    }
    if node.name == "filterColumn" {
      filter_attributes(node, ["colId", "hiddenButton", "showButton"])
      let column = range.left +
        natural(node.attribute("colId").unwrap_or(""), 16383)
      guard column <= range.right &&
        !flags.contains(column) &&
        flags.length() < 256 else {
        @failure.reject(
          "protected-content", "Invalid or duplicate source filter column",
        )
      }
      let children = tree.children.get(node.id).unwrap_or([])
      let metadata : Array[(String, String)] = []
      for key in ["hiddenButton", "showButton"] {
        if node.attribute(key) is Some(value) {
          ignore(flag(node, key))
          metadata.push((key, value))
        }
      }
      flags[column] = metadata
      if children.is_empty() {
        continue
      }
      guard children is [filters] &&
        filters.uri == spreadsheet_uri &&
        filters.name == "filters" else {
        @failure.reject(
          "protected-content", "This filter kind requires evaluation support",
        )
      }
      filter_attributes(filters, ["blank"])
      let entries = tree.children.get(filters.id).unwrap_or([])
      guard entries.length() <= 4096 else {
        @failure.reject("limit-exceeded", "Too many filter values")
      }
      let values = entries.map(value => {
        guard value.uri == spreadsheet_uri &&
          value.name == "filter" &&
          tree.children.get(value.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "protected-content", "Date groups and unknown filter values are protected",
          )
        }
        filter_attributes(value, ["val"])
        value
        .attribute("val")
        .unwrap_or_error(
          @failure.Failure(
            code="protected-content",
            part=sheet.id,
            offset=-1,
            message="Filter value is missing",
          ),
        )
      })
      columns.push({ column, values, blank: flag(filters, "blank"), })
    } else if node.name == "extLst" {
      filter_attributes(node, [])
      let extensions = tree.children.get(node.id).unwrap_or([])
      guard extensions is [extension] &&
        extension.uri == spreadsheet_uri &&
        extension.name == "ext" &&
        extension.attribute("uri") == Some(filter_state_uri) else {
        @failure.reject(
          "protected-content", "Unknown filter extensions are protected",
        )
      }
      filter_attributes(extension, ["uri"])
      let children = tree.children.get(extension.id).unwrap_or([])
      guard children is [state] &&
        state.uri == filter_state_uri &&
        state.name == "visibility" &&
        tree.children.get(state.id).unwrap_or([]).is_empty() &&
        !tracked else {
        @failure.reject(
          "protected-content", "Unknown filter visibility metadata is protected",
        )
      }
      filter_attributes(state, ["manual", "filtered"])
      manual = filter_rows(state.attribute("manual").unwrap_or(""), range)
      filtered = filter_rows(state.attribute("filtered").unwrap_or(""), range)
      tracked = true
    } else {
      @failure.reject(
        "protected-content", "Unknown filter content is protected",
      )
    }
  }
  let settings : FilterSettings = { range: range.name(), columns, }
  ignore(filter_settings(settings))
  if tracked {
    for row in (range.top + 1)..<=range.bottom {
      guard (sheet.dimensions.rows.size(row) == 0) ==
        (manual.contains(row) || filtered.contains(row)) else {
        @failure.reject(
          "protected-content", "Filter visibility metadata no longer matches source rows",
        )
      }
    }
  }
  Some({ settings, bounds: range, manual, filtered, tracked, flags, })
}
