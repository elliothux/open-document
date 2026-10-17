///|
priv struct StoredSort {
  bounds : Range
  source : String
}

///|
fn read_sort_state(
  tree : Tree,
  parent : Int,
) -> StoredSort? raise @failure.Failure {
  let entries = tree.all(parent, "sortState")
  guard entries.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate sort states are protected")
  }
  guard entries is [node] else { return None }
  filter_attributes(node, ["ref", "caseSensitive", "columnSort", "sortMethod"])
  let source = tree.document.source()[node.start:node.end].to_owned()
  guard !source.contains("<!--") &&
    !source.contains("<?") &&
    ["none", "pinYin", "stroke"].contains(
      node.attribute("sortMethod").unwrap_or("none"),
    ) else {
    @failure.reject("protected-content", "Unknown sort metadata is protected")
  }
  ignore(flag(node, "caseSensitive"))
  let columns = flag(node, "columnSort")
  let bounds = Range::parse(node.attribute("ref").unwrap_or(""))
  let keys = tree.children.get(node.id).unwrap_or([])
  guard keys.length() <= 64 else {
    @failure.reject(
      "protected-content", "Sort states support at most 64 value keys",
    )
  }
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  for key in keys {
    guard key.uri == spreadsheet_uri &&
      key.name == "sortCondition" &&
      tree.children.get(key.id).unwrap_or([]).is_empty() else {
      @failure.reject(
        "protected-content", "Unknown sort conditions are protected",
      )
    }
    filter_attributes(key, [
      "ref", "descending", "sortBy", "customList", "dxfId",
    ])
    let kind = key.attribute("sortBy").unwrap_or("value")
    guard ["value", "cellColor", "fontColor"].contains(kind) &&
      (if kind == "value" {
        key.attribute("dxfId") is None
      } else {
        key.attribute("dxfId") is Some(_) &&
        key.attribute("customList").unwrap_or("").is_empty()
      }) else {
      @failure.reject(
        "protected-content", "Unknown or conflicting sort properties",
      )
    }
    let dxf = if kind != "value" {
      natural(key.attribute("dxfId").unwrap(), 4095).to_string()
    } else {
      ""
    }
    if key.attribute("customList") is Some(text) && !text.is_empty() {
      let list = decode_text(text)
        .split(",")
        .map(value => value.to_owned())
        .to_array()
      check_sort_list(list)
      units += text.length()
      guard units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Stored sort lists exceed text budget",
        )
      }
    }
    ignore(flag(key, "descending"))
    let range = Range::parse(key.attribute("ref").unwrap_or(""))
    let axis = if columns { range.top } else { range.left }
    let identity = "\{axis}:\{kind}:\{dxf}"
    guard bounds.covers(range) &&
      (if columns {
        range.top == range.bottom
      } else {
        range.left == range.right
      }) &&
      !seen.contains(identity) else {
      @failure.reject(
        "protected-content", "Invalid or duplicate sort key references",
      )
    }
    seen[identity] = true
  }
  Some({ bounds, source, })
}

///|
fn stored_sort(
  target : Range,
  settings : SortSettings,
  indices : Array[Int?],
) -> StoredSort raise @failure.Failure {
  let bounds = if settings.header {
    if settings.rows {
      { ..target, top: target.top + 1, }
    } else {
      { ..target, left: target.left + 1, }
    }
  } else {
    target
  }
  let out = StringBuilder()
  out <+
    "<od:sortState xmlns:od=\"\{spreadsheet_uri}\" ref=\"\{bounds.name()}\" sortMethod=\"none\" caseSensitive=\"\{if settings.case_sensitive { 1 } else { 0 }}\" columnSort=\"\{if settings.rows { 0 } else { 1 }}\">"
  let mut units = 0
  for at, key in settings.keys {
    let range = if settings.rows {
      { ..bounds, left: key.index, right: key.index, }
    } else {
      { ..bounds, top: key.index, bottom: key.index, }
    }
    let list = sort_list_attribute(key.custom_list)
    let style = if key.sort_by == "value" {
      ""
    } else {
      let index = indices
        .get(at)
        .bind(value => value)
        .unwrap_or_error(
          @failure.Failure(
            code="invalid-operation",
            part="",
            offset=-1,
            message="Missing color sort style",
          ),
        )
      " dxfId=\"\{index}\""
    }
    units += list.length()
    guard units <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Encoded custom sort lists exceed text budget",
      )
    }
    out <+
      "<od:sortCondition ref=\"\{range.name()}\" descending=\"\{if key.descending { 1 } else { 0 }}\" sortBy=\"\{key.sort_by}\"\{style}\{list}/>"
  }
  out <+ "</od:sortState>"
  { bounds, source: out.to_string(), }
}

///|
fn write_sort_state(
  document : @xml.Document,
  state : StoredSort,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("worksheet")
  let change : @xml.SourceChange = if tree.one(root.id, "sortState")
    is Some(node) {
    {
      node: root.id,
      offset: node.start - root.start,
      length: node.end - node.start,
      xml: state.source,
    }
  } else {
    let after = [
      "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr", "conditionalFormatting",
      "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup",
      "headerFooter", "rowBreaks", "colBreaks", "customProperties", "cellWatches",
      "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF",
      "picture", "oleObjects", "controls", "webPublishItems", "tableParts", "extLst",
    ]
    if tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(n => after.contains(n.name))
      is Some(node) {
      {
        node: root.id,
        offset: node.start - root.start,
        length: 0,
        xml: state.source,
      }
    } else {
      insertion(root, state.source)
    }
  }
  document.edit_source([change])
}

///|
fn axis_sort_state(
  tree : Tree,
  node : @xml.Node,
  change : AxisChange,
) -> (Array[@xml.SourceChange], Bool) raise @failure.Failure {
  let bounds = Range::parse(node.attribute("ref").unwrap_or(""))
  if change.band is Some((low, high)) {
    let (first, last) = if change.rows {
      (bounds.left, bounds.right)
    } else {
      (bounds.top, bounds.bottom)
    }
    if first < low || last > high {
      return ([], false)
    }
  }
  guard change.range(bounds) is Some(next) else {
    return ([sheet_node_removal(tree, node)], true)
  }
  let edits = metadata_changes(node, [("ref", next.name())])
  let mut remaining = 0
  for key in tree.all(node.id, "sortCondition") {
    let range = change.range(Range::parse(key.attribute("ref").unwrap_or("")))
    if range is Some(range) && next.covers(range) {
      edits.append(metadata_changes(key, [("ref", range.name())]))
      remaining += 1
    } else {
      edits.push(sheet_node_removal(tree, key))
    }
  }
  if remaining == 0 {
    ([sheet_node_removal(tree, node)], true)
  } else {
    (edits, false)
  }
}
