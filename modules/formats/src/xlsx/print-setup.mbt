///|
pub(all) struct PrintSetup {
  paper : String
  orientation : String
  left : Double
  top : Double
  right : Double
  bottom : Double
  scale : Int32
  fitWidth : Int32
  fitHeight : Int32
} derive(ToJson, Eq)

///|
pub extend PrintSetup with ToJson::{to_json}

///|
pub extend PrintSetup with Eq::{equal, not_equal}

///|
pub fn PrintSetup::default() -> PrintSetup {
  {
    paper: "A4",
    orientation: "portrait",
    left: 36,
    top: 36,
    right: 36,
    bottom: 36,
    scale: 100,
    fitWidth: 0,
    fitHeight: 0,
  }
}

///|
fn PrintSetup::page(self : PrintSetup) -> @layout.PageSetup {
  let (width, height) = if self.paper == "Letter" {
    (612.0, 792.0)
  } else {
    (595.28, 841.89)
  }
  {
    width: if self.orientation == "landscape" {
      height
    } else {
      width
    },
    height: if self.orientation == "landscape" {
      width
    } else {
      height
    },
    left: self.left,
    top: self.top,
    right: self.right,
    bottom: self.bottom,
  }
}

///|
fn PrintSetup::validate(self : PrintSetup) -> Unit raise @failure.Failure {
  let page = self.page()
  guard ["A4", "Letter"].contains(self.paper) &&
    ["portrait", "landscape"].contains(self.orientation) &&
    [self.left, self.top, self.right, self.bottom].all(v => {
      !v.is_nan() && !v.is_inf() && v >= 0 && v <= 14400
    }) &&
    page.width - self.left - self.right >= 12 &&
    page.height - self.top - self.bottom >= 12 &&
    self.scale >= 10 &&
    self.scale <= 400 &&
    self.fitWidth >= 0 &&
    self.fitWidth <= 1024 &&
    self.fitHeight >= 0 &&
    self.fitHeight <= 1024 else {
    @failure.reject("invalid-page", "Invalid print paper, margins or scaling")
  }
}

///|
fn print_integer(
  node : @xml.Node?,
  name : String,
  fallback : Int32,
) -> Int32 raise @failure.Failure {
  guard node.bind(node => node.attribute(name)) is Some(value) else {
    return fallback
  }
  let parsed = @string.parse_int(value) catch {
    _ => @failure.reject("unsupported-print", "Invalid print integer")
  }
  parsed
}

///|
fn read_print_setup(sheet : Sheet) -> PrintSetup raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let page = tree.one(root.id, "pageSetup")
  let margins = tree.one(root.id, "pageMargins")
  let properties = tree.one(root.id, "sheetPr")
  if properties is Some(properties) {
    guard tree.children
      .get(properties.id)
      .unwrap_or([])
      .all(n => {
        n.uri == spreadsheet_uri &&
        ["tabColor", "outlinePr", "pageSetUpPr"].contains(n.name)
      }) else {
      @failure.reject(
        "unsupported-print", "Unknown worksheet print properties are protected",
      )
    }
  }
  let fit = properties.bind(p => tree.one(p.id, "pageSetUpPr"))
  for node in [page, margins, fit].filter_map(v => v) {
    guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
      node.text.trim().is_empty() else {
      @failure.reject(
        "unsupported-print", "Unknown print setting content is protected",
      )
    }
  }
  if page is Some(page) {
    guard page.attributes.all(a => {
        a.uri.is_empty() &&
        [
          "paperSize", "orientation", "scale", "fitToWidth", "fitToHeight", "pageOrder",
          "usePrinterDefaults", "horizontalDpi", "verticalDpi", "copies", "firstPageNumber",
          "useFirstPageNumber",
        ].contains(a.name)
      }) &&
      page.attribute("pageOrder").unwrap_or("downThenOver") == "downThenOver" else {
      @failure.reject(
        "unsupported-print", "Unsupported print settings are protected",
      )
    }
  }
  if margins is Some(margins) {
    guard margins.attributes.all(a => {
      a.uri.is_empty() &&
      ["left", "top", "right", "bottom", "header", "footer"].contains(a.name)
    }) else {
      @failure.reject("unsupported-print", "Unknown page margins are protected")
    }
  }
  if fit is Some(fit) {
    guard fit.attributes.all(a => {
      a.uri.is_empty() && ["fitToPage", "autoPageBreaks"].contains(a.name)
    }) else {
      @failure.reject("unsupported-print", "Unknown page fitting is protected")
    }
  }
  let paper = match print_integer(page, "paperSize", 9) {
    9 => "A4"
    1 => "Letter"
    _ =>
      @failure.reject(
        "unsupported-print", "Only A4 and Letter paper are supported",
      )
  }
  let margin = fn(name : String) -> Double raise @failure.Failure {
    let value = margins.bind(n => n.attribute(name)).unwrap_or("0.5")
    let value = @string.parse_double(value) catch {
      _ => @failure.reject("invalid-page", "Invalid page margin")
    }
    value * 72
  }
  let enabled = fit.map(n => flag(n, "fitToPage")).unwrap_or(false)
  let setup : PrintSetup = {
    paper,
    orientation: page
    .bind(n => n.attribute("orientation"))
    .unwrap_or("portrait"),
    left: margin("left"),
    top: margin("top"),
    right: margin("right"),
    bottom: margin("bottom"),
    scale: print_integer(page, "scale", 100),
    fitWidth: if enabled {
      print_integer(page, "fitToWidth", 1)
    } else {
      0
    },
    fitHeight: if enabled {
      print_integer(page, "fitToHeight", 1)
    } else {
      0
    },
  }
  setup.validate()
  setup
}

///|
fn Session::print_setup_query(self : Session, sheet : Sheet) -> Json {
  let (setup, reason) = (read_print_setup(sheet), self.dimension_reason(sheet)) catch {
    @failure.Failure(message~, ..) => (PrintSetup::default(), message)
  }
  let json = setup.to_json()
  if json is Object(fields) {
    fields["readOnlyReason"] = Json(reason)
  }
  json
}

///|
fn print_node_change(
  tree : Tree,
  parent : @xml.Node,
  node : @xml.Node?,
  name : String,
  values : Array[(String, String)],
  after : Array[String],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  if node is Some(node) {
    return metadata_changes(node, values)
  }
  let attributes = values.map(pair => " \{pair.0}=\"\{pair.1}\"").join("")
  let markup = "<od:\{name} xmlns:od=\"\{spreadsheet_uri}\"\{attributes}/>"
  if tree.children
    .get(parent.id)
    .unwrap_or([])
    .iter()
    .find_first(n => after.contains(n.name))
    is Some(next) {
    [
      {
        node: parent.id,
        offset: next.start - parent.start,
        length: 0,
        xml: markup,
      },
    ]
  } else {
    [insertion(parent, markup)]
  }
}

///|
fn Session::set_print_setup(
  self : Session,
  id : String,
  setup : PrintSetup,
) -> Json raise @failure.Failure {
  setup.validate()
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let reason = self.dimension_reason(sheet)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let original = read_print_setup(sheet)
  if original.paper == setup.paper &&
    original.orientation == setup.orientation &&
    original.scale == setup.scale &&
    original.fitWidth == setup.fitWidth &&
    original.fitHeight == setup.fitHeight &&
    [
      original.left - setup.left,
      original.top - setup.top,
      original.right - setup.right,
      original.bottom - setup.bottom,
    ].all(v => v.abs() < 0.000001) {
    return self.query()
  }
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let changes : Array[@xml.SourceChange] = []
  let values = [
    ("paperSize", if setup.paper == "A4" { "9" } else { "1" }),
    ("orientation", setup.orientation),
    ("scale", setup.scale.to_string()),
    ("fitToWidth", setup.fitWidth.to_string()),
    ("fitToHeight", setup.fitHeight.to_string()),
  ]
  let setup_changes = print_node_change(
    tree,
    root,
    tree.one(root.id, "pageSetup"),
    "pageSetup",
    values,
    [
      "headerFooter", "rowBreaks", "colBreaks", "customProperties", "cellWatches",
      "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "extLst",
    ],
  )
  let margin_node = tree.one(root.id, "pageMargins")
  let margin_values = [
    ("left", (setup.left / 72).to_string()),
    ("top", (setup.top / 72).to_string()),
    ("right", (setup.right / 72).to_string()),
    ("bottom", (setup.bottom / 72).to_string()),
  ]
  if margin_node is None {
    margin_values.append([("header", "0.3"), ("footer", "0.3")])
  }
  changes.append(
    print_node_change(tree, root, margin_node, "pageMargins", margin_values, [
      "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "customProperties",
      "cellWatches", "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "extLst",
    ]),
  )
  changes.append(setup_changes)
  let enabled = if setup.fitWidth != 0 || setup.fitHeight != 0 {
    "1"
  } else {
    "0"
  }
  if tree.one(root.id, "sheetPr") is Some(properties) {
    changes.append(
      print_node_change(
        tree,
        properties,
        tree.one(properties.id, "pageSetUpPr"),
        "pageSetUpPr",
        [("fitToPage", enabled)],
        ["extLst"],
      ),
    )
  } else {
    let first = tree.children[root.id][0]
    changes.push({
      node: root.id,
      offset: first.start - root.start,
      length: 0,
      xml: "<od:sheetPr xmlns:od=\"\{spreadsheet_uri}\"><od:pageSetUpPr fitToPage=\"\{enabled}\"/></od:sheetPr>",
    })
  }
  let joined = join_insertions(changes)
  if joined.is_empty() {
    return self.query()
  }
  let (document, edit) = sheet.document.edit_source(joined)
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    sheet.id,
    sheet.name,
    sheet.state,
    document,
    self.strings,
    self.styles.length(),
  )
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    [(id, edit)],
    self.selection,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}
