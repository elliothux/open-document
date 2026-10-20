///|
let sparkline_uri = "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"

///|
let sparkline_formula_uri = "http://schemas.microsoft.com/office/excel/2006/main"

///|
let sparkline_extension_uri = "{05C60535-1F16-4fd2-B633-F4F36F0B64E0}"

///|
priv struct Sparkline {
  cell : Address
  source : Range?
  kind : String
} derive(Eq)

///|
priv struct Sparklines {
  items : Array[Sparkline]
  reason : String
}

///|
fn sparkline_source(
  text : String,
  sheet : String,
) -> Range? raise @failure.Failure {
  if text == "#REF!" {
    return None
  }
  guard text.length() <= 256 &&
    parse_formula(text) is Reference(target, first, last) &&
    target.map(name => name.to_lower() == sheet.to_lower()).unwrap_or(true) else {
    @failure.reject(
      "protected-content", "Sparkline requires a local cell range",
    )
  }
  let range = first.range(last.unwrap_or(first))
  guard (range.top == range.bottom || range.left == range.right) &&
    range.bottom - range.top + range.right - range.left < 256 else {
    @failure.reject(
      "limit-exceeded", "Sparkline requires at most 256 cells in one row or column",
    )
  }
  Some(range)
}

///|
fn read_sparklines(
  tree : Tree,
  sheet : String,
  merges : Array[Range],
) -> Sparklines {
  let items : Array[Sparkline] = []
  let reason = try {
    let extensions = tree.one(tree.root("worksheet").id, "extLst")
    let mut seen = false
    for
      extension in extensions
      .map(n => tree.children.get(n.id).unwrap_or([]))
      .unwrap_or([]) {
      if extension.attribute("uri") != Some(sparkline_extension_uri) {
        continue
      }
      guard !seen && extension.uri == spreadsheet_uri && extension.name == "ext" else {
        @failure.reject(
          "protected-content", "Unknown or duplicate sparkline extension",
        )
      }
      seen = true
      filter_attributes(extension, ["uri"])
      let children = tree.children.get(extension.id).unwrap_or([])
      guard children is [groups] &&
        groups.uri == sparkline_uri &&
        groups.name == "sparklineGroups" else {
        @failure.reject("protected-content", "Unknown sparkline extension")
      }
      filter_attributes(groups, [])
      guard tree.children.get(groups.id).unwrap_or([]).length() <= 256 else {
        @failure.reject("limit-exceeded", "Sparkline groups exceed 256")
      }
      for group in tree.children.get(groups.id).unwrap_or([]) {
        guard group.uri == sparkline_uri && group.name == "sparklineGroup" else {
          @failure.reject("protected-content", "Unknown sparkline group")
        }
        filter_attributes(group, [
          "type", "lineWeight", "displayEmptyCellsAs", "negative", "displayHidden",
        ])
        let native = group.attribute("type").unwrap_or("line")
        guard ["line", "column", "stacked"].contains(native) &&
          group.attribute("lineWeight").unwrap_or("0.75") == "0.75" &&
          group.attribute("displayEmptyCellsAs").unwrap_or("zero") == "gap" &&
          group.attribute("negative").unwrap_or("0") == "1" &&
          group.attribute("displayHidden").unwrap_or("0") == "0" else {
          @failure.reject(
            "protected-content", "Unsupported sparkline display settings",
          )
        }
        let children = tree.children.get(group.id).unwrap_or([])
        guard children is [series, negative, lines] &&
          [series, negative, lines].all(n => n.uri == sparkline_uri) &&
          series.name == "colorSeries" &&
          negative.name == "colorNegative" &&
          lines.name == "sparklines" &&
          series.attribute("rgb") == Some("FF4472C4") &&
          negative.attribute("rgb") == Some("FFED7D31") else {
          @failure.reject(
            "protected-content", "Unsupported sparkline colors or metadata",
          )
        }
        for color in [series, negative] {
          filter_attributes(color, ["rgb"])
          guard tree.children.get(color.id).unwrap_or([]).is_empty() else {
            @failure.reject(
              "protected-content", "Unknown sparkline color content",
            )
          }
        }
        filter_attributes(lines, [])
        for line in tree.children.get(lines.id).unwrap_or([]) {
          guard items.length() < 256 &&
            line.uri == sparkline_uri &&
            line.name == "sparkline" else {
            @failure.reject("limit-exceeded", "Unknown or excessive sparklines")
          }
          filter_attributes(line, [])
          let parts = tree.children.get(line.id).unwrap_or([])
          guard parts is [formula, location] &&
            formula.uri == sparkline_formula_uri &&
            location.uri == sparkline_formula_uri &&
            formula.name == "f" &&
            location.name == "sqref" &&
            [formula, location].all(n => {
              n.attributes.is_empty() &&
              tree.children.get(n.id).unwrap_or([]).is_empty()
            }) else {
            @failure.reject(
              "protected-content", "Unknown sparkline reference content",
            )
          }
          let cell = Address::parse(location.text)
          guard !items.any(item => item.cell == cell) &&
            !merges.any(range => range.contains(cell)) else {
            @failure.reject(
              "protected-content", "Overlapping sparkline locations",
            )
          }
          items.push({
            cell,
            source: sparkline_source(formula.text, sheet),
            kind: if native == "stacked" {
              "winLoss"
            } else {
              native
            },
          })
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
  { items: if reason.is_empty() { items } else { [] }, reason, }
}

///|
fn sparkline_extension(tree : Tree, node : @xml.Node) -> Bool {
  node.uri == spreadsheet_uri &&
  node.name == "extLst" &&
  !tree.children.get(node.id).unwrap_or([]).is_empty() &&
  tree.children
  .get(node.id)
  .unwrap_or([])
  .all(n => {
    n.uri == spreadsheet_uri &&
    n.name == "ext" &&
    n.attribute("uri") == Some(sparkline_extension_uri)
  })
}

///|
fn Session::sparkline_query(
  self : Session,
  sheet : Sheet,
) -> Json raise @failure.Failure {
  let reason = if !self.read_only.is_empty() {
    self.read_only
  } else if sheet.locked {
    "Worksheet is protected"
  } else {
    sheet.sparklines.reason
  }
  {
    "items": sheet.sparklines.items.map(item => {
      let value : Json = {
        "cell": item.cell.name(),
        "source": item.source.map(Range::name).unwrap_or("#REF!"),
        "kind": item.kind,
      }
      value
    }),
    "readOnlyReason": reason,
  }
}
