///|
fn cleared_table_cell(source : Ref) -> String? raise @failure.Failure {
  if source.node.attributes.all(a => a.name == "anchor") &&
    source.tree.children.get(source.node.id).unwrap_or([]).is_empty() {
    return None
  }
  let xml = source.tree.document.source()
  let content = StringBuilder()
  let mut cursor = source.node.opening_end
  for node in source.tree.children.get(source.node.id).unwrap_or([]) {
    content.write_view(xml[cursor:node.start])
    let removed = xml[node.start:node.end]
    guard !removed.contains("<!--") && !removed.contains("<?") else {
      @failure.reject(
        "protected-content", "Extended table cell formatting is protected",
      )
    }
    cursor = node.end
  }
  if !source.node.empty {
    content.write_view(xml[cursor:source.node.closing_start])
  }
  let anchor = source.node
    .attribute("anchor")
    .map(value => " anchor=\"\{value}\"")
    .unwrap_or("")
  Some("<a:tcPr xmlns:a=\"\{drawing_uri}\"\{anchor}>\{content}</a:tcPr>")
}

///|
fn table_style_query(table : DrawingTable, reason : String) -> Json {
  let style = table.style
  let ids = table.styles.styles.keys().to_array()
  ids.sort()
  {
    "settings": {
      "id": style.id,
      "firstRow": style.first_row,
      "lastRow": style.last_row,
      "firstColumn": style.first_column,
      "lastColumn": style.last_column,
      "bandRows": style.band_rows,
      "bandColumns": style.band_columns,
    },
    "choices": ids.map(id => {
      "id": id,
      "name": table.styles.styles[id].node.attribute("styleName").unwrap_or(id),
    }),
    "reason": reason,
  }
}

///|
fn Session::set_table_style(
  self : Session,
  settings : TableStyleSettings,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard self.selection.objects.length() == 1 else {
    @failure.reject("invalid-operation", "Select one table to apply a style")
  }
  let original = self.current()
  let object = original.object(self.selection.object)
  guard object.table is Some(table) else {
    @failure.reject("protected-content", "Select an editable table")
  }
  let (_, _, reason) = self.table_position(object, self.selection)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let settings = { ..settings, id: settings.id.to_upper(), }
  guard !settings.id.is_empty() &&
    settings.id.length() <= 80 &&
    table.styles.styles.contains(settings.id) else {
    @failure.reject("invalid-operation", "Unknown table style identity")
  }
  ignore(table_style_parts(table.styles, settings.id))
  let source = object.source
    .child("graphic")
    .unwrap()
    .child("graphicData")
    .unwrap()
    .child("tbl")
    .unwrap()
  let changes : Array[@xml.SourceChange] = []
  let flags = [
    ("firstRow", settings.first_row),
    ("lastRow", settings.last_row),
    ("firstCol", settings.first_column),
    ("lastCol", settings.last_column),
    ("bandRow", settings.band_rows),
    ("bandCol", settings.band_columns),
  ]
  let attrs = flags
    .map(pair => " \{pair.0}=\"\{if pair.1 {1}else{0}}\"")
    .join("")
  let properties = source.child("tblPr")
  let style_id = "<a:tableStyleId xmlns:a=\"\{drawing_uri}\">\{settings.id}</a:tableStyleId>"
  if properties is Some(properties) {
    for (name, enabled) in flags {
      if properties.node.attribute(name) !=
        Some(if enabled { "1" } else { "0" }) {
        changes.push(
          attribute_change(properties, name, if enabled { "1" } else { "0" }),
        )
      }
    }
    if properties.child("tableStyleId") is Some(id) {
      if id.node.text.trim() != settings.id {
        changes.push(table_source_change(id, style_id))
      }
    } else {
      changes.push(insertion(properties.node, style_id))
    }
  } else {
    let grid = source.child("tblGrid").unwrap()
    changes.push(
      table_source_change(
        grid,
        "<a:tblPr xmlns:a=\"\{drawing_uri}\"\{attrs}>\{style_id}</a:tblPr>",
        before=Some(true),
      ),
    )
  }
  for row in table.rows {
    for cell in row.cells {
      if cell.source.child("tcPr") is Some(properties) &&
        cleared_table_cell(properties) is Some(markup) {
        changes.push(table_source_change(properties, markup))
      }
    }
  }
  if changes.is_empty() {
    return self.query()
  }
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  self.table_style_resource(table.styles, settings.id, parts, created, edits)
  let staged = { ..self, parts, }
  let (candidate, edit) = staged.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  let slides = self.slides.copy()
  slides[self.index(original.tree.part)] = candidate
  edits.push((original.tree.part, edit))
  self.commit_slides(
    self.main,
    slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
