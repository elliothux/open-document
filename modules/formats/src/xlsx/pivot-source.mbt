///|
fn pivot_root_edit(
  document : @xml.Document,
  markup : String,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let root = document.nodes()[0]
  // Retain the opening '<' as the XML history node's identity anchor.
  document.edit_source([
    {
      node: root.id,
      offset: 1,
      length: root.end - root.start - 1,
      xml: markup[1:].to_owned(),
    },
  ])
}

///|
fn pivot_item_markup(value : Value) -> String raise @failure.Failure {
  match value {
    Blank => "<m/>"
    Number(number) => "<n v=\"\{number}\"/>"
    Boolean(value) => "<b v=\"\{if value { 1 } else { 0 }}\"/>"
    Text(text) => "<s v=\"\{escaped_attribute(encoded_text(text))}\"/>"
    Error(text) => "<e v=\"\{escaped_attribute(text)}\"/>"
  }
}

///|
fn PivotCache::definition(
  self : PivotCache,
  sheet : String,
  range : String,
  records : String,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  out <+
    "<pivotCacheDefinition xmlns=\"\{spreadsheet_uri}\" xmlns:r=\"\{relationship_uri[:relationship_uri.length() - 1]}\" r:id=\"\{records}\" recordCount=\"\{self.records.length()}\" saveData=\"1\" refreshOnLoad=\"0\" enableRefresh=\"1\" invalid=\"0\" createdVersion=\"6\" refreshedVersion=\"6\" minRefreshableVersion=\"3\"><cacheSource type=\"worksheet\"><worksheetSource ref=\"\{range}\" sheet=\"\{escaped_attribute(sheet)}\"/></cacheSource><cacheFields count=\"\{self.headers.length()}\">"
  for index, name in self.headers {
    let items = self.items[index]
    let numeric = items.any(v => v is Number(_))
    let text = items.any(v => v is Text(_) || v is Boolean(_) || v is Error(_))
    let blank = items.contains(Blank)
    let integer = numeric &&
      !items.any(value => value is Number(number) && number.round() != number)
    let long_text = items.any(value => {
      value is Text(text) && text.length() > 255
    })
    out <+
      "<cacheField name=\"\{escaped_attribute(encoded_text(name))}\"><sharedItems count=\"\{items.length()}\" containsNumber=\"\{if numeric { 1 } else { 0 }}\" containsString=\"\{if text { 1 } else { 0 }}\" containsBlank=\"\{if blank { 1 } else { 0 }}\" containsNonDate=\"1\" containsSemiMixedTypes=\"\{if text || blank { 1 } else { 0 }}\" containsMixedTypes=\"\{if numeric && text { 1 } else { 0 }}\" containsInteger=\"\{if integer { 1 } else { 0 }}\" longText=\"\{if long_text { 1 } else { 0 }}\">"
    for value in items {
      out.write_string(pivot_item_markup(value))
    }
    out <+ "</sharedItems></cacheField>"
  }
  out <+ "</cacheFields></pivotCacheDefinition>"
  out.to_string()
}

///|
fn PivotCache::record_markup(self : PivotCache) -> String {
  let out = StringBuilder()
  out <+
    "<pivotCacheRecords xmlns=\"\{spreadsheet_uri}\" count=\"\{self.records.length()}\">"
  for record in self.records {
    out <+ "<r>"
    for item in record {
      out <+ "<x v=\"\{item}\"/>"
    }
    out <+ "</r>"
  }
  out <+ "</pivotCacheRecords>"
  out.to_string()
}

///|
fn PivotLayout::definition(
  self : PivotLayout,
  settings : PivotSettings,
  name : String,
  cache : Int,
  range : Range,
  data_caption~ : String = "",
) -> String raise @failure.Failure {
  let out = StringBuilder()
  let caption = self.caption(settings, data_caption)
  let range = settings.body(range)
  let ordinary_columns = !settings.columns.is_empty()
  let first_header = if ordinary_columns { 1 } else { 0 }
  out <+
    "<pivotTableDefinition xmlns=\"\{spreadsheet_uri}\" name=\"\{escaped_attribute(name)}\" cacheId=\"\{cache}\" dataCaption=\"\{escaped_attribute(caption)}\" rowGrandTotals=\"1\" colGrandTotals=\"\{if ordinary_columns {1} else {0}}\" compact=\"0\" compactData=\"0\" outline=\"0\" outlineData=\"0\" gridDropZones=\"1\" createdVersion=\"6\" updatedVersion=\"6\" minRefreshableVersion=\"3\"><location ref=\"\{range.name()}\" firstHeaderRow=\"\{first_header}\" firstDataRow=\"\{settings.header_rows()}\" firstDataCol=\"\{settings.rows.length()}\"/><pivotFields count=\"\{self.cache.headers.length()}\">"
  for field in 0..<self.cache.headers.length() {
    let row = settings.rows.contains(field)
    let value = settings.values.any(value => value.field == field)
    let column = settings.columns.contains(field)
    let filter = settings.filters
      .iter()
      .find_first(filter => filter.field == field)
    let axis = if row {
      " axis=\"axisRow\""
    } else if column {
      " axis=\"axisCol\""
    } else if filter is Some(_) {
      " axis=\"axisPage\""
    } else {
      ""
    }
    let multiple = filter
      .bind(filter => filter.values)
      .map(values => values.length() > 1)
      .unwrap_or(false)
    out <+
      "<pivotField\{axis} dataField=\"\{if value { 1 } else { 0 }}\" defaultSubtotal=\"0\" showAll=\"0\" compact=\"0\" outline=\"0\"\{if multiple {" multipleItemSelectionAllowed=\"1\""} else {""}}>"
    if row || column || filter is Some(_) {
      out <+ "<items count=\"\{self.cache.items[field].length()}\">"
      for item in 0..<self.cache.items[field].length() {
        let hidden = filter
          .bind(filter => filter.values)
          .map(values => {
            !values.any(value => {
              pivot_item_key(value) ==
              pivot_item_key(self.cache.items[field][item])
            })
          })
          .unwrap_or(false)
        out <+ "<item x=\"\{item}\"\{if hidden {" h=\"1\""} else {""}}/>"
      }
      out <+ "</items>"
    }
    out <+ "</pivotField>"
  }
  out <+ "</pivotFields><rowFields count=\"\{settings.rows.length()}\">"
  for field in settings.rows {
    out <+ "<field x=\"\{field}\"/>"
  }
  out <+ "</rowFields><rowItems count=\"\{self.members.length() + 1}\">"
  for members in self.members {
    out <+ "<i>"
    for item in members {
      out <+ "<x v=\"\{item}\"/>"
    }
    out <+ "</i>"
  }
  out <+ "<i t=\"grand\"><x/></i></rowItems>"
  if ordinary_columns || settings.values.length() > 1 {
    let multiple = settings.values.length() > 1
    out <+
      "<colFields count=\"\{settings.columns.length()+(if multiple {1} else {0})}\">"
    for field in settings.columns {
      out <+ "<field x=\"\{field}\"/>"
    }
    if multiple {
      out <+ "<field x=\"-2\"/>"
    }
    out <+
      "</colFields><colItems count=\"\{(self.columns.length()+(if ordinary_columns {1} else {0}))*settings.values.length()}\">"
    for members in self.columns {
      for index in 0..<settings.values.length() {
        out <+ "<i i=\"\{index}\">"
        for item in members {
          out <+ "<x v=\"\{item}\"/>"
        }
        if multiple {
          out <+ "<x v=\"\{index}\"/>"
        }
        out <+ "</i>"
      }
    }
    if ordinary_columns {
      for index in 0..<settings.values.length() {
        out <+ "<i t=\"grand\" i=\"\{index}\"><x/></i>"
      }
    }
    out <+ "</colItems>"
  } else {
    out <+ "<colItems count=\"1\"><i/></colItems>"
  }
  if !settings.filters.is_empty() {
    out <+ "<pageFields count=\"\{settings.filters.length()}\">"
    for filter in settings.filters {
      let item = match filter.values {
        Some([value]) => {
          let index = self.cache.items[filter.field]
            .search_by(item => pivot_item_key(item) == pivot_item_key(value))
            .unwrap()
          " item=\"\{index}\""
        }
        _ => ""
      }
      out <+ "<pageField fld=\"\{filter.field}\" hier=\"-1\"\{item}/>"
    }
    out <+ "</pageFields>"
  }
  out <+ "<dataFields count=\"\{settings.values.length()}\">"
  for value in settings.values {
    out <+
      "<dataField name=\"\{escaped_attribute(encoded_text(value.name))}\" fld=\"\{value.field}\" subtotal=\"\{value.aggregate}\"/>"
  }
  out <+ "</dataFields></pivotTableDefinition>"
  out.to_string()
}
