///|
fn worksheet_cache_points(
  cache : Ref,
  values : Array[String],
  numeric : Bool,
  changes : Array[@xml.SourceChange],
) -> Unit raise @failure.Failure {
  let count = chart_child(cache, "ptCount")
  let attribute = count.node.attributes
    .iter()
    .find_first(a => a.uri.is_empty() && a.name == "val")
    .unwrap()
  if number(attribute.value, 0, 256) != values.length().to_double() {
    changes.push({
      node: count.node.id,
      offset: attribute.start - count.node.start,
      length: attribute.end - attribute.start,
      xml: values.length().to_string(),
    })
  }
  let seen : Set[Int32] = Set([])
  let source = cache.tree.document.source()
  for node in cache.tree.all(cache.node.id, "pt", uri=chart_uri) {
    let index = number(node.attribute("idx").unwrap_or(""), 0, 255)
    guard index == index.floor() && !seen.contains(index.to_int()) else {
      @failure.reject("unsupported-chart", "Invalid chart cache point identity")
    }
    let index = index.to_int()
    seen.add(index)
    let point : Ref = { tree: cache.tree, node, }
    let value = chart_child(point, "v").node
    let next = values.get(index)
    if next is None || (numeric && next == Some("") && !value.text.is_empty()) {
      let fragment = source[node.start:node.end].to_owned()
      guard !fragment.contains("<!--") && !fragment.contains("<?") else {
        @failure.reject(
          "protected-content", "Annotated chart cache points cannot be removed",
        )
      }
      changes.push({
        node: cache.node.id,
        offset: node.start - cache.node.start,
        length: node.end - node.start,
        xml: "",
      })
      continue
    }
    let next = next.unwrap()
    if value.text == next ||
      (
        numeric &&
        !value.text.is_empty() &&
        !next.is_empty() &&
        line_real(value.text, -1.0e300, 1.0e300) ==
        line_real(next, -1.0e300, 1.0e300)
      ) {
      continue
    }
    let escaped = @xml.escape_text(next)
    if value.empty {
      changes.push({
        node: value.id,
        offset: value.opening_end - value.start - 2,
        length: 2,
        xml: ">" + escaped + "</" + value.qualified + ">",
      })
    } else {
      guard !source[value.opening_end:value.closing_start].contains("<") else {
        @failure.reject(
          "protected-content", "Annotated chart cache text requires preservation",
        )
      }
      changes.push({
        node: value.id,
        offset: value.opening_end - value.start,
        length: value.closing_start - value.opening_end,
        xml: escaped,
      })
    }
  }
  let prefix = cache.node.qualified[:cache.node.qualified.length() -
  cache.node.name.length()].to_owned()
  let inserted = StringBuilder()
  for i, value in values {
    if seen.contains(i) || (numeric && value.is_empty()) {
      continue
    }
    inserted.write_string(
      "<" +
      prefix +
      "pt idx=\"" +
      i.to_string() +
      "\"><" +
      prefix +
      "v>" +
      @xml.escape_text(value) +
      "</" +
      prefix +
      "v></" +
      prefix +
      "pt>",
    )
  }
  if !inserted.to_string().is_empty() {
    changes.push({
      node: cache.node.id,
      offset: cache.node.closing_start - cache.node.start,
      length: 0,
      xml: inserted.to_string(),
    })
  }
}

///|
fn worksheet_reference_cache(
  source : Ref,
  values : Array[String],
  changes : Array[@xml.SourceChange],
) -> Unit raise @failure.Failure {
  let numeric = source.child("numRef", uri=chart_uri) is Some(_)
  let reference = chart_child(source, if numeric { "numRef" } else { "strRef" })
  worksheet_cache_points(
    chart_child(reference, if numeric { "numCache" } else { "strCache" }),
    values,
    numeric,
    changes,
  )
}

///|
/// Updates bound data without rewriting chart layout, styles, formulas or cache formats.
pub fn WorksheetChart::update_caches(
  self : WorksheetChart,
  part : String,
  document : @xml.Document,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  self.data.validate_sources()
  let before = read_worksheet(part, document)
  guard before.data.kind == self.data.kind &&
    before.categories == self.categories &&
    before.names == self.names &&
    before.values == self.values &&
    before.data.series.length() == self.data.series.length() &&
    before.native_bubble.map(b => b.size_sources) ==
    self.native_bubble.map(b => b.size_sources) else {
    @failure.reject(
      "protected-content", "Chart cache updates cannot change source bindings or chart groups",
    )
  }
  let tree = Tree::new(part, document)
  let root : Ref = { tree, node: tree.root("chartSpace", uri=chart_uri), }
  let plot = chart_child(chart_child(root, "chart"), "plotArea")
  let series = tree.children
    .get(plot.node.id)
    .unwrap_or([])
    .filter(n => n.uri == chart_uri && n.name.has_suffix("Chart"))
    .map(n => tree.all(n.id, "ser", uri=chart_uri))
    .flatten()
  guard series.length() == self.data.series.length() else {
    @failure.reject(
      "unsupported-chart", "Chart cache series do not match source groups",
    )
  }
  let changes : Array[@xml.SourceChange] = []
  for i, node in series {
    let source : Ref = { tree, node, }
    if source.child("tx", uri=chart_uri) is Some(title) {
      worksheet_reference_cache(title, [self.data.series[i].name], changes)
    } else {
      guard self.data.series[i].name == before.data.series[i].name else {
        @failure.reject(
          "protected-content", "Default chart series names cannot be rewritten",
        )
      }
    }
    if source.child(
        if self.data.kind == "scatter" {
          "xVal"
        } else {
          "cat"
        },
        uri=chart_uri,
      )
      is Some(categories) {
      worksheet_reference_cache(categories, self.data.categories, changes)
    } else {
      guard self.data.categories == before.data.categories else {
        @failure.reject(
          "protected-content", "Default chart categories cannot be rewritten",
        )
      }
    }
    worksheet_reference_cache(
      chart_child(
        source,
        if self.data.kind == "scatter" {
          "yVal"
        } else {
          "val"
        },
      ),
      self.data.series[i].values.map(value => {
        value.map(v => v.to_string()).unwrap_or("")
      }),
      changes,
    )
    if self.native_bubble is Some(bubble) && bubble.size_sources[i] is Some(_) {
      worksheet_reference_cache(
        chart_child(source, "bubbleSize"),
        bubble.sizes[i].map(value => value.map(v => v.to_string()).unwrap_or("")),
        changes,
      )
    }
  }
  let result = document.edit_source(changes)
  ignore(read_worksheet(part, result.0))
  result
}
