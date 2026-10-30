///|
pub(all) struct FilterCondition {
  operator : String
  value : String
} derive(Eq)

///|
pub(all) enum FilterRule {
  Values(Array[String], blank~ : Bool)
  Custom(Array[FilterCondition], all~ : Bool)
  Rank(Int32, top~ : Bool, percent~ : Bool)
  Average(above~ : Bool)
  Calendar(String, Int32)
  Relative(String, (Double, Double)?)
  Dates(Array[String], values~ : Array[String], blank~ : Bool)
  Color(String?, cell_color~ : Bool)
  ColorStyle(Int32, cell_color~ : Bool)
  Icon(String, Int32?)
} derive(Eq)

///|
pub(all) struct FilterColumn {
  column : Int32
  rule : FilterRule
} derive(Eq)

///|
pub(all) struct FilterSettings {
  range : String
  columns : Array[FilterColumn]
} derive(Eq)

///|
pub extend FilterColumn with Eq::{equal, not_equal}

///|
pub extend FilterCondition with Eq::{equal, not_equal}

///|
pub extend FilterRule with Eq::{equal, not_equal}

///|
pub extend FilterSettings with Eq::{equal, not_equal}

///|
priv struct AutoFilterState {
  settings : FilterSettings
  bounds : Range
  manual : Array[Int32]
  filtered : Array[Int32]
  tracked : Bool
  flags : Map[Int32, Array[(String, String)]]
  sort : StoredSort?
} derive(Eq)

///|
let filter_state_uri = "urn:open-document:xlsx:filter-state"

///|
fn filter_rows(
  text : String,
  range : Range,
) -> Array[Int32] raise @failure.Failure {
  let result : Array[Int32] = []
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
  let seen : Map[Int32, Bool] = Map([])
  let mut units = 0
  for column in settings.columns {
    guard column.column >= range.left &&
      column.column <= range.right &&
      !seen.contains(column.column) else {
      @failure.reject("invalid-operation", "Invalid or duplicate filter column")
    }
    seen[column.column] = true
    let labels = match column.rule {
      Icon(set, id) => {
        guard conditional_icon_count(set) > 0 &&
          id
          .map(id => id >= 0 && id < conditional_icon_count(set))
          .unwrap_or(true) else {
          @failure.reject(
            "invalid-operation", "Invalid filter icon set or index",
          )
        }
        []
      }
      Color(value, ..) => {
        CellFormat::new(color=value).validate()
        []
      }
      ColorStyle(index, ..) => {
        guard index >= 0 && index < 4096 else {
          @failure.reject("invalid-operation", "Invalid color filter style")
        }
        []
      }
      Average(..) => []
      Relative(period, cache) => {
        validate_relative_filter(period, cache)
        []
      }
      Calendar(unit, value) => {
        ignore(filter_calendar_type(unit, value))
        []
      }
      Dates(groups, values~, ..) => {
        guard !groups.is_empty() && groups.length() + values.length() <= 4096 else {
          @failure.reject(
            "invalid-operation", "Date filters require 1..4096 groups and at most 4096 combined entries",
          )
        }
        let seen : Map[String, Bool] = Map([])
        for group in groups {
          guard !seen.contains(group) else {
            @failure.reject("invalid-operation", "Duplicate date filter group")
          }
          ignore(filter_date_parts(group))
          units += group.length()
          seen[group] = true
        }
        guard units <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Date filter groups exceed text budget",
          )
        }
        values
      }
      Rank(value, percent~, ..) => {
        guard value >= 1 && value <= (if percent { 100 } else { 500 }) else {
          @failure.reject(
            "invalid-operation", "Rank filters require 1..500 items or 1..100 percent",
          )
        }
        []
      }
      Values(values, ..) => {
        guard values.length() <= 4096 else {
          @failure.reject("invalid-operation", "Too many filter labels")
        }
        values
      }
      Custom(conditions, ..) => {
        guard conditions.length() >= 1 && conditions.length() <= 2 else {
          @failure.reject(
            "invalid-operation", "Custom filters require one or two conditions",
          )
        }
        for condition in conditions {
          ignore(filter_operator(condition.operator))
        }
        conditions.map(c => c.value)
      }
    }
    let seen_labels : Map[String, Bool] = Map([])
    for value in labels {
      units += value.length()
      guard value.length() <= 32767 &&
        @xml.valid_text(value) &&
        (
          !(column.rule is Values(_, ..) || column.rule is Dates(_, ..)) ||
          !seen_labels.contains(value)
        ) &&
        units <= 1048576 else {
        @failure.reject(
          "invalid-operation", "Invalid filter values or text budget",
        )
      }
      seen_labels[value] = true
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
  Some(
    read_filter_node(
      sheet,
      tree,
      root,
      visibility=tree.one(tree.root("worksheet").id, "tableParts") is None,
    ),
  )
}

///|
fn read_filter_node(
  sheet : Sheet,
  tree : Tree,
  root : @xml.Node,
  visibility~ : Bool = false,
) -> AutoFilterState raise @failure.Failure {
  filter_attributes(root, ["ref"])
  let source = tree.document.source()[root.start:root.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject("protected-content", "Opaque filter source is protected")
  }
  let range = native_range(root.attribute("ref").unwrap_or(""))
  ignore(filter_settings({ range: range.name(), columns: [], }))
  let columns : Array[FilterColumn] = []
  let flags : Map[Int32, Array[(String, String)]] = Map([])
  let sort = read_sort_state(tree, root.id)
  guard sort.map(state => range.covers(state.bounds)).unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Sort state is outside its filter range",
    )
  }
  let mut manual : Array[Int32] = []
  let mut filtered : Array[Int32] = []
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
      guard children is [filters] && filters.uri == spreadsheet_uri else {
        @failure.reject(
          "protected-content", "This filter kind requires evaluation support",
        )
      }
      if filters.name == "iconFilter" {
        filter_attributes(filters, ["iconSet", "iconId"])
        guard tree.children.get(filters.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "protected-content", "Extended icon filter is protected",
          )
        }
        columns.push({
          column,
          rule: Icon(
            filters.attribute("iconSet").unwrap_or(""),
            filters.attribute("iconId").map(value => natural(value, 4)),
          ),
        })
        continue
      }
      if filters.name == "colorFilter" {
        filter_attributes(filters, ["dxfId", "cellColor"])
        guard tree.children.get(filters.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "protected-content", "Extended color filter is protected",
          )
        }
        columns.push({
          column,
          rule: ColorStyle(
            natural(filters.attribute("dxfId").unwrap_or(""), 4095),
            cell_color=flag(filters, "cellColor", fallback=true),
          ),
        })
        continue
      }
      if filters.name == "top10" {
        filter_attributes(filters, ["top", "percent", "val", "filterVal"])
        guard tree.children.get(filters.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "protected-content", "Extended rank filter is protected",
          )
        }
        if filters.attribute("filterVal") is Some(value) {
          let value = @string.parse_double(value[:]) catch {
            _ =>
              @failure.reject("protected-content", "Invalid rank filter cache")
          }
          guard !value.is_nan() && !value.is_inf() else {
            @failure.reject("protected-content", "Invalid rank filter cache")
          }
        }
        columns.push({
          column,
          rule: Rank(
            natural(filters.attribute("val").unwrap_or(""), 500),
            top=flag(filters, "top", fallback=true),
            percent=flag(filters, "percent"),
          ),
        })
        continue
      }
      if filters.name == "dynamicFilter" {
        filter_attributes(filters, ["type", "val", "maxVal"])
        let kind = filters.attribute("type").unwrap_or("")
        let calendar = read_calendar_filter(kind)
        let relative = relative_filter_periods.contains(kind)
        guard tree.children.get(filters.id).unwrap_or([]).is_empty() &&
          (
            ["aboveAverage", "belowAverage"].contains(kind) ||
            calendar is Some(_) ||
            relative
          ) else {
          @failure.reject(
            "protected-content", "This dynamic filter requires evaluation support",
          )
        }
        for key in ["val", "maxVal"] {
          if filters.attribute(key) is Some(value) {
            let value = @string.parse_double(value[:]) catch {
              _ =>
                @failure.reject(
                  "protected-content", "Invalid dynamic filter cache",
                )
            }
            guard !value.is_nan() && !value.is_inf() else {
              @failure.reject(
                "protected-content", "Invalid dynamic filter cache",
              )
            }
          }
        }
        let relative_cache = if relative {
          match (filters.attribute("val"), filters.attribute("maxVal")) {
            (Some(start), Some(end)) => {
              let bounds = (
                @string.parse_double(start[:]) catch {
                  _ => abort("Checked cache")
                },
                @string.parse_double(end[:]) catch {
                  _ => abort("Checked cache")
                },
              )
              guard bounds.0 < bounds.1 else {
                @failure.reject(
                  "protected-content", "Invalid relative date filter cache",
                )
              }
              Some(bounds)
            }
            (None, None) => None
            _ =>
              @failure.reject(
                "protected-content", "Incomplete relative date filter cache",
              )
          }
        } else {
          None
        }
        columns.push({
          column,
          rule: if relative {
            Relative(kind, relative_cache)
          } else {
            calendar.unwrap_or(Average(above=kind == "aboveAverage"))
          },
        })
        continue
      }
      if filters.name == "customFilters" {
        filter_attributes(filters, ["and"])
        let entries = tree.children.get(filters.id).unwrap_or([])
        guard entries.length() >= 1 && entries.length() <= 2 else {
          @failure.reject("protected-content", "Invalid custom filter count")
        }
        let conditions = entries.map(value => {
          guard value.uri == spreadsheet_uri &&
            value.name == "customFilter" &&
            tree.children.get(value.id).unwrap_or([]).is_empty() else {
            @failure.reject(
              "protected-content", "Unknown custom filter content",
            )
          }
          filter_attributes(value, ["operator", "val"])
          guard value.attribute("val") is Some(text) else {
            @failure.reject(
              "protected-content", "Custom filter value is missing",
            )
          }
          {
            operator: value.attribute("operator").unwrap_or("equal"),
            value: text,
          }
        })
        columns.push({
          column,
          rule: Custom(conditions, all=flag(filters, "and")),
        })
        continue
      }
      guard filters.name == "filters" else {
        @failure.reject(
          "protected-content", "This filter kind requires evaluation support",
        )
      }
      filter_attributes(filters, ["blank"])
      let entries = tree.children.get(filters.id).unwrap_or([])
      guard entries.length() <= 4096 else {
        @failure.reject("limit-exceeded", "Too many filter values")
      }
      let groups : Array[String] = []
      let values : Array[String] = []
      for value in entries {
        guard value.uri == spreadsheet_uri &&
          tree.children.get(value.id).unwrap_or([]).is_empty() else {
          @failure.reject(
            "protected-content", "Unknown filter values are protected",
          )
        }
        if value.name == "dateGroupItem" {
          groups.push(read_filter_date(tree, value))
          continue
        }
        guard value.name == "filter" else {
          @failure.reject(
            "protected-content", "Unknown filter entry is protected",
          )
        }
        filter_attributes(value, ["val"])
        values.push(
          value
          .attribute("val")
          .unwrap_or_error(
            @failure.Failure(
              code="protected-content",
              part=sheet.id,
              offset=-1,
              message="Filter value is missing",
            ),
          ),
        )
      }
      columns.push({
        column,
        rule: if groups.is_empty() {
          Values(values, blank=flag(filters, "blank"))
        } else {
          Dates(groups, values~, blank=flag(filters, "blank"))
        },
      })
    } else if node.name == "sortState" {
      continue
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
  if tracked && visibility {
    for row in (range.top + 1)..<=range.bottom {
      guard (sheet.dimensions.rows.size(row) == 0) ==
        (manual.contains(row) || filtered.contains(row)) else {
        @failure.reject(
          "protected-content", "Filter visibility metadata no longer matches source rows",
        )
      }
    }
  }
  { settings, bounds: range, manual, filtered, tracked, flags, sort, }
}
