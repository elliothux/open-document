///|
fn line_cap_code(value : String) -> Int32 raise @failure.Failure {
  match value {
    "flat" => 0
    "rnd" => 1
    "sq" => 2
    _ => @failure.reject("unsupported-style", "Unknown DrawingML border cap")
  }
}

///|
fn pen_miter(value : String) -> Double raise @failure.Failure {
  let amount = number(value, 0, 2147483647) / 100000
  guard amount >= 1 && amount <= 1000 else {
    @failure.reject(
      "unsupported-style", "Border miter limit is outside the supported range",
    )
  }
  amount
}

///|
fn join_override(line : Ref) -> Ref? raise @failure.Failure {
  let joins = line.tree.children
    .get(line.node.id)
    .unwrap_or([])
    .filter(n => {
      n.uri == drawing_uri && ["round", "bevel", "miter"].contains(n.name)
    })
  guard joins.length() <= 1 else {
    @failure.reject(
      "unsupported-style", "Duplicate border joins are unsupported",
    )
  }
  guard joins.get(0) is Some(node) else { return None }
  guard node.text.trim().is_empty() &&
    line.tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.attributes.all(a => {
      a.uri.is_empty() && node.name == "miter" && a.name == "lim"
    }) else {
    @failure.reject("unsupported-style", "Unknown border join markup")
  }
  if node.attribute("lim") is Some(limit) {
    ignore(pen_miter(limit))
  }
  Some({ tree: line.tree, node, })
}

///|
fn line_join(lines : Array[Ref]) -> (String, Double) raise @failure.Failure {
  let mut kind = ""
  for line in lines {
    if join_override(line) is Some(join) {
      if kind.is_empty() {
        kind = join.node.name
      }
      if kind != join.node.name {
        break
      }
      if kind != "miter" {
        return (kind, 8)
      }
      if join.node.attribute("lim") is Some(limit) {
        return (kind, pen_miter(limit))
      }
    }
  }
  (if kind.is_empty() { "round" } else { kind }, 8)
}

///|
fn Session::pen_reason(self : Session, object : Object) -> String {
  let reason = self.dash_reason(object)
  if !reason.is_empty() {
    return reason
  }
  try {
    if object.source
      .child("spPr", uri=presentation_uri)
      .bind(p => p.child("ln"))
      is Some(line) {
      if line.node.attribute("cap") is Some(cap) {
        ignore(line_cap_code(cap))
      }
      if join_override(line) is Some(join) {
        let xml = source_xml(join)
        if xml.contains("<!--") || xml.contains("<?") {
          return "Retained border join markup is protected"
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn pen_remove_cap(line : Ref) -> @xml.SourceChange raise @failure.Failure {
  let attr = line.node.attributes
    .iter()
    .find_first(a => a.uri.is_empty() && a.name == "cap")
    .unwrap()
  let xml = line.tree.document.source()
  let mut name_end = attr.start - 1
  while name_end > line.node.start &&
        [9, 10, 13, 32].contains(xml[name_end - 1].to_int()) {
    name_end -= 1
  }
  guard xml[name_end - 1] == 61 else {
    @failure.reject("protected-content", "Cannot locate border cap attribute")
  }
  name_end -= 1
  while name_end > line.node.start &&
        [9, 10, 13, 32].contains(xml[name_end - 1].to_int()) {
    name_end -= 1
  }
  let start = name_end - 3
  guard start > line.node.start && xml[start:name_end] == "cap" else {
    @failure.reject("protected-content", "Cannot locate border cap name")
  }
  let start = if xml[start - 1] == 32 { start - 1 } else { start }
  {
    node: line.node.id,
    offset: start - line.node.start,
    length: attr.end + 1 - start,
    xml: "",
  }
}

///|
fn Session::pen_objects(
  self : Session,
  change : ObjectEdit,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let (cap, value, limit) = match change {
    StrokeCap(value) => {
      if value is Some(value) {
        ignore(line_cap_code(value)) catch {
          _ => @failure.reject("invalid-operation", "Unknown border cap")
        }
      }
      (true, value, "")
    }
    StrokeJoin(value, limit) => {
      guard value
        .map(v => ["round", "bevel", "miter"].contains(v))
        .unwrap_or(true) &&
        limit >= 1 &&
        limit <= 1000 else {
        @failure.reject(
          "invalid-operation", "Invalid border join or miter limit",
        )
      }
      (false, value, (limit * 100000).round().to_int64().to_string())
    }
    _ => @failure.reject("invalid-operation", "Unknown border pen edit")
  }
  guard self.selection.mode == "object" && !self.selection.objects.is_empty() else {
    @failure.reject(
      "invalid-operation", "Border pen editing requires selected objects",
    )
  }
  let changes = []
  for id in self.selection.objects {
    let object = self.current().object(id)
    let reason = self.pen_reason(object)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let properties = object.source.child("spPr", uri=presentation_uri).unwrap()
    let markup = value
      .map(v => {
        if cap {
          "cap=\"\{v}\""
        } else if v == "miter" {
          "<a:miter xmlns:a=\"\{drawing_uri}\" lim=\"\{limit}\"/>"
        } else {
          "<a:\{v} xmlns:a=\"\{drawing_uri}\"/>"
        }
      })
      .unwrap_or("")
    if properties.child("ln") is Some(line) {
      if cap {
        if value == line.node.attribute("cap") {
          continue
        }
        changes.push(
          if value is Some(value) {
            attribute_change(line, "cap", value)
          } else {
            pen_remove_cap(line)
          },
        )
      } else {
        let old = join_override(line)
        if value == old.map(j => j.node.name) &&
          (
            value != Some("miter") ||
            old.unwrap().node.attribute("lim") == Some(limit)
          ) {
          continue
        }
        changes.push(
          paint_child_change(line, old.map(j => j.node), markup, [
            "headEnd", "tailEnd", "extLst",
          ]),
        )
      }
    } else if value is Some(_) {
      changes.push(
        paint_child_change(
          properties,
          None,
          if cap {
            "<a:ln xmlns:a=\"\{drawing_uri}\" \{markup}/>"
          } else {
            "<a:ln xmlns:a=\"\{drawing_uri}\">\{markup}</a:ln>"
          },
          ["effectLst", "effectDag", "scene3d", "sp3d", "extLst"],
        ),
      )
    }
  }
  changes
}
