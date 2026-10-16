///|
pub(all) struct HeaderFooter {
  oddHeader : String
  oddFooter : String
  evenHeader : String
  evenFooter : String
  firstHeader : String
  firstFooter : String
  differentFirst : Bool
  differentOddEven : Bool
  scaleWithDoc : Bool
  alignWithMargins : Bool
  headerMargin : Double
  footerMargin : Double
} derive(Eq, ToJson)

///|
pub extend HeaderFooter with Eq::{equal, not_equal}

///|
pub extend HeaderFooter with ToJson::{to_json}

///|
pub fn HeaderFooter::default() -> HeaderFooter {
  {
    oddHeader: "",
    oddFooter: "",
    evenHeader: "",
    evenFooter: "",
    firstHeader: "",
    firstFooter: "",
    differentFirst: false,
    differentOddEven: false,
    scaleWithDoc: true,
    alignWithMargins: true,
    headerMargin: 21.6,
    footerMargin: 21.6,
  }
}

///|
fn HeaderFooter::strings(self : HeaderFooter) -> Array[(String, String)] {
  [
    ("oddHeader", self.oddHeader),
    ("oddFooter", self.oddFooter),
    ("evenHeader", self.evenHeader),
    ("evenFooter", self.evenFooter),
    ("firstHeader", self.firstHeader),
    ("firstFooter", self.firstFooter),
  ]
}

///|
fn HeaderFooter::normalized(
  self : HeaderFooter,
) -> HeaderFooter raise @failure.Failure {
  let values = self
    .strings()
    .map(pair => {
      let text = pair.1
        .replace_all(old="\r\n", new="\n")
        .replace_all(old="\r", new="\n")
      ignore(header_sections(text, 1, 1, "Sheet1"))
      text
    })
  guard [self.headerMargin, self.footerMargin].all(v => {
    !v.is_nan() && !v.is_inf() && v >= 0 && v <= 14400
  }) else {
    @failure.reject("invalid-page", "Invalid header or footer distance")
  }
  {
    ..self,
    oddHeader: values[0],
    oddFooter: values[1],
    evenHeader: values[2],
    evenFooter: values[3],
    firstHeader: values[4],
    firstFooter: values[5],
  }
}

///|
fn same_header_footer(a : HeaderFooter, b : HeaderFooter) -> Bool {
  { ..a, headerMargin: b.headerMargin, footerMargin: b.footerMargin, } == b &&
  (a.headerMargin - b.headerMargin).abs() < 0.000001 &&
  (a.footerMargin - b.footerMargin).abs() < 0.000001
}

///|
fn read_header_footer(sheet : Sheet) -> HeaderFooter raise @failure.Failure {
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let node = tree.one(root.id, "headerFooter")
  let keys = HeaderFooter::default().strings().map(pair => pair.0)
  if node is Some(node) {
    guard node.text.trim().is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() &&
        [
          "differentFirst", "differentOddEven", "scaleWithDoc", "alignWithMargins",
        ].contains(a.name)
      }) &&
      tree.children
      .get(node.id)
      .unwrap_or([])
      .all(child => child.uri == spreadsheet_uri && keys.contains(child.name)) else {
      @failure.reject(
        "unsupported-print", "Unknown header/footer source is protected",
      )
    }
  }
  let values = keys.map(key => {
    guard node.bind(n => tree.one(n.id, key)) is Some(child) else { return "" }
    guard tree.children.get(child.id).unwrap_or([]).is_empty() &&
      child.attributes.all(a => {
        a.uri == "http://www.w3.org/XML/1998/namespace" && a.name == "space"
      }) &&
      (
        child.empty ||
        !sheet.document.source()[child.opening_end:child.closing_start].contains(
          "<",
        )
      ) else {
      @failure.reject(
        "unsupported-print", "Extended header/footer text is protected",
      )
    }
    child.text
  })
  let margins = tree.one(root.id, "pageMargins")
  let distance = fn(name : String) -> Double raise @failure.Failure {
    (@string.parse_double(margins.bind(n => n.attribute(name)).unwrap_or("0.3")) *
    72) catch {
      _ => @failure.reject("invalid-page", "Invalid header/footer distance")
    }
  }
  let enabled = fn(
    name : String,
    fallback : Bool,
  ) -> Bool raise @failure.Failure {
    node.map(n => flag(n, name, fallback~)).unwrap_or(fallback)
  }
  (
    {
      oddHeader: values[0],
      oddFooter: values[1],
      evenHeader: values[2],
      evenFooter: values[3],
      firstHeader: values[4],
      firstFooter: values[5],
      differentFirst: enabled("differentFirst", false),
      differentOddEven: enabled("differentOddEven", false),
      scaleWithDoc: enabled("scaleWithDoc", true),
      alignWithMargins: enabled("alignWithMargins", true),
      headerMargin: distance("header"),
      footerMargin: distance("footer"),
    } : HeaderFooter).normalized()
}

///|
fn Session::header_footer_query(self : Session, sheet : Sheet) -> Json {
  let (settings, reason) = (
    read_header_footer(sheet),
    self.dimension_reason(sheet),
  ) catch {
    @failure.Failure(message~, ..) => (HeaderFooter::default(), message)
  }
  let json = settings.to_json()
  if json is Object(fields) {
    fields["readOnlyReason"] = Json(reason)
  }
  json
}

///|
fn header_text_xml(
  name : String,
  text : String,
) -> String raise @failure.Failure {
  "<od:\{name} xmlns:od=\"\{spreadsheet_uri}\" xml:space=\"preserve\">\{@xml.escape_text(text)}</od:\{name}>"
}

///|
fn Session::set_header_footer(
  self : Session,
  id : String,
  settings : HeaderFooter,
) -> Json raise @failure.Failure {
  let settings = settings.normalized()
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let reason = self.dimension_reason(sheet)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  if same_header_footer(read_header_footer(sheet), settings) {
    return self.query()
  }
  let tree = Tree::new(sheet.document)
  let root = tree.root("worksheet")
  let existing = tree.one(root.id, "headerFooter")
  let flags = [
    ("differentFirst", settings.differentFirst),
    ("differentOddEven", settings.differentOddEven),
    ("scaleWithDoc", settings.scaleWithDoc),
    ("alignWithMargins", settings.alignWithMargins),
  ].map(pair => (pair.0, if pair.1 { "1" } else { "0" }))
  let keys = settings.strings().map(pair => pair.0)
  let markup = if existing is Some(original) {
    let mut candidate = metadata_attributes(sheet.document, original, flags)
    for (key, value) in settings.strings() {
      let view = Tree::new(candidate)
      let parent = candidate.node(original.id)
      let changes : Array[@xml.SourceChange] = []
      if view.one(parent.id, key) is Some(child) {
        if child.text == value {
          continue
        }
        changes.push({
          node: parent.id,
          offset: child.start - parent.start,
          length: child.end - child.start,
          xml: header_text_xml(key, value),
        })
      } else if !value.is_empty() {
        let later = keys.search(key).unwrap()
        let next = view.children
          .get(parent.id)
          .unwrap_or([])
          .iter()
          .find_first(n => {
            keys.search(n.name).map(i => i > later).unwrap_or(false)
          })
        changes.push(
          if next is Some(next) {
            {
              node: parent.id,
              offset: next.start - parent.start,
              length: 0,
              xml: header_text_xml(key, value),
            }
          } else {
            insertion(parent, header_text_xml(key, value))
          },
        )
      }
      if !changes.is_empty() {
        candidate = candidate.edit_source(changes).0
      }
    }
    let updated = candidate.node(original.id)
    candidate.source()[updated.start:updated.end].to_owned()
  } else {
    let attributes = flags.map(pair => " \{pair.0}=\"\{pair.1}\"").join("")
    "<od:headerFooter xmlns:od=\"\{spreadsheet_uri}\"\{attributes}>" +
    settings
    .strings()
    .filter(pair => !pair.1.is_empty())
    .map(pair => header_text_xml(pair.0, pair.1))
    .join("") +
    "</od:headerFooter>"
  }
  let changes : Array[@xml.SourceChange] = []
  let margins = tree.one(root.id, "pageMargins")
  let values = [
    ("header", (settings.headerMargin / 72).to_string()),
    ("footer", (settings.footerMargin / 72).to_string()),
  ]
  if margins is None {
    values.append([
      ("left", "0.5"),
      ("right", "0.5"),
      ("top", "0.5"),
      ("bottom", "0.5"),
    ])
  }
  changes.append(
    print_node_change(tree, root, margins, "pageMargins", values, [
      "pageSetup", "headerFooter", "rowBreaks", "colBreaks", "customProperties",
      "cellWatches", "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "extLst",
    ]),
  )
  changes.push(
    if existing is Some(node) {
      {
        node: root.id,
        offset: node.start - root.start,
        length: node.end - node.start,
        xml: markup,
      }
    } else if tree.children
      .get(root.id)
      .unwrap_or([])
      .iter()
      .find_first(n => {
        [
          "rowBreaks", "colBreaks", "customProperties", "cellWatches", "ignoredErrors",
          "smartTags", "drawing", "legacyDrawing", "extLst",
        ].contains(n.name)
      })
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
  let (document, edit) = sheet.document.edit_source(join_insertions(changes))
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
