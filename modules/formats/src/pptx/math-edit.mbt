///|
pub(all) struct MathTarget {
  object : String
  revision : Int32
  node : Int32
}

///|
fn Object::check_math_locks(self : Object) -> Unit raise @failure.Failure {
  for node in self.source.tree.document.nodes() {
    if node.start >= self.source.node.start &&
      node.end <= self.source.node.end &&
      node.name.has_suffix("Locks") &&
      (
        flag(node, "noSelect") ||
        flag(node, "noTextEdit") ||
        flag(node, "noDrilldown")
      ) {
      @failure.reject(
        "protected-content", "Mathematical content editing is locked",
      )
    }
  }
}

///|
fn Ref::math_fallback_text(self : Ref) -> Ref? raise @failure.Failure {
  let compatibility = "http://schemas.openxmlformats.org/markup-compatibility/2006"
  if self.node.uri != compatibility {
    return None
  }
  guard self.child("Fallback", uri=compatibility) is Some(fallback) else {
    return None
  }
  let children = fallback.tree.children.get(fallback.node.id).unwrap_or([])
  guard fallback.node.attributes.is_empty() &&
    fallback.node.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unsupported mathematical fallback")
  }
  if children.is_empty() {
    return None
  }
  guard children is [run] &&
    run.uri == drawing_uri &&
    run.name == "r" &&
    run.attributes.is_empty() &&
    run.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unsupported mathematical fallback")
  }
  let run : Ref = { tree: self.tree, node: run, }
  let children = self.tree.children.get(run.node.id).unwrap_or([])
  let text = children.filter(node => node.uri == drawing_uri && node.name == "t")
  let properties = children.filter(node => {
    node.uri == drawing_uri && node.name == "rPr"
  })
  guard text is [text] &&
    properties.length() <= 1 &&
    children.length() == 1 + properties.length() &&
    self.tree.children.get(text.id).unwrap_or([]).is_empty() &&
    text.attributes.all(a => {
      a.uri == "http://www.w3.org/XML/1998/namespace" &&
      a.name == "space" &&
      a.value == "preserve"
    }) else {
    @failure.reject(
      "protected-content", "Unsupported mathematical fallback run",
    )
  }
  if properties is [properties] {
    guard properties.text.trim().is_empty() &&
      self.tree.children.get(properties.id).unwrap_or([]).is_empty() &&
      properties.attributes.all(a => {
        a.uri.is_empty() &&
        ["lang", "altLang", "dirty", "smtClean", "sz", "b", "i"].contains(
          a.name,
        )
      }) else {
      @failure.reject(
        "protected-content", "Extended mathematical fallback formatting",
      )
    }
  }
  Some({ tree: self.tree, node: text, })
}

///|
fn Session::math_reason(
  self : Session,
  object : Object,
  source : Ref,
) -> String {
  try {
    guard object.source.tree.part == self.current().tree.part &&
      (
        object.read_only.is_empty() ||
        object.read_only == "Group members are read-only"
      ) &&
      object.text_reason == math_text_reason else {
      @failure.reject(
        "protected-content",
        if !object.read_only.is_empty() {
          object.read_only
        } else {
          object.text_reason
        },
      )
    }
    let xml = source_xml(source)
    guard !xml.contains("<!--") && !xml.contains("<?") else {
      @failure.reject(
        "protected-content", "Mathematical source contains opaque content",
      )
    }
    ignore(source.math_fallback_text())
    object.check_math_locks()
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::math_items(self : Session, object : Object) -> Array[Json] {
  let result : Array[Json] = []
  for paragraph in object.paragraphs {
    for run in paragraph.runs {
      if run.math is Some(formula) && run.source is Some(source) {
        result.push({
          "node": source.node.id,
          "latex": @omml.latex(formula.expression),
          "format": {
            "family": formula.style.font,
            "size": formula.style.size,
            "color": formula.style.color,
          },
          "reason": self.math_reason(object, source),
        })
      }
    }
  }
  result
}

///|
fn math_value(
  latex : String,
  style : @layout.TextStyle,
) -> @layout.MathFormula raise @failure.Failure {
  guard !style.font.trim().is_empty() &&
    style.font.length() <= 255 &&
    @xml.valid_text(style.font) &&
    style.font
    .iter()
    .all(c => c.to_int() >= 32 && c != '\u2028' && c != '\u2029') &&
    ((style.size * 100).round() - style.size * 100).abs() < 0.000001 else {
    @failure.reject("invalid-operation", "Invalid mathematical appearance")
  }
  let formula = @layout.MathFormula::new(@omml.parse_latex(latex), {
    ..style,
    color: style.color.to_lower(),
  })
  ignore(@omml.markup(formula, drawing=true))
  formula
}

///|
fn equation_markup(
  formula : @layout.MathFormula,
) -> String raise @failure.Failure {
  "<mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice xmlns:a14=\"\{drawing_math_uri}\" Requires=\"a14\"><a14:m><m:oMathPara xmlns:m=\"\{math_uri}\"><m:oMathParaPr><m:jc m:val=\"centerGroup\"/></m:oMathParaPr>\{@omml.markup(formula,drawing=true)}</m:oMathPara></a14:m></mc:Choice><mc:Fallback><a:r xmlns:a=\"\{drawing_uri}\"><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t xml:space=\"preserve\">\{@xml.escape_text(formula.expression.linear_text())}</a:t></a:r></mc:Fallback></mc:AlternateContent>"
}

///|
fn Session::insert_math(
  self : Session,
  latex : String,
  style : @layout.TextStyle,
  box : (Double, Double, Double, Double),
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let formula = math_value(latex, style)
  validate_object_box(box.0, box.1, box.2, box.3, false)
  let original = self.current()
  let id = self.next_object_identity()
  let body = "<p:txBody><a:bodyPr wrap=\"none\" anchor=\"ctr\"><a:noAutofit/></a:bodyPr><a:lstStyle/><a:p>\{equation_markup(formula)}</a:p></p:txBody>"
  let markup = object_markup(id, "text", box.0, box.1, box.2, box.3, "").replace(
    old=object_text_markup(""),
    new=body,
  )
  let (candidate, edit) = self.prepare(original, [
    object_insertion(original.tree, markup),
  ])
  let identity = original.tree.part + "#" + id
  let target = candidate.object(identity)
  let (_, _, diagnostic, _) = fit_text(
    target,
    target.geometry.unwrap(),
    probe,
    profile,
  )
  guard target.diagnostic.is_empty() && diagnostic.is_empty() else {
    @failure.reject("layout-overflow", target.diagnostic + diagnostic)
  }
  self.commit(
    candidate,
    edit,
    {
      ..self.selection,
      object: identity,
      objects: [identity],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    probe~,
    profile~,
  )
  self.object_sequence = number(id, 1, 4294967295).to_int64() + 1
  self.query()
}

///|
fn Session::append_math(
  self : Session,
  latex : String,
  style : @layout.TextStyle,
  start : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard self.selection.objects is [id] else {
    @failure.reject("invalid-operation", "Select one text frame")
  }
  let original = self.current()
  let object = original.object(id)
  guard object.source.node.name == "sp" &&
    object.source.tree.part == original.tree.part &&
    object.read_only.is_empty() &&
    (object.text_reason.is_empty() || object.text_reason == math_text_reason) &&
    object.source.child("txBody", uri=presentation_uri) is Some(body) else {
    @failure.reject(
      "protected-content", "Equation insertion requires an editable local text frame",
    )
  }
  let formula = math_value(latex, style)
  let paragraphs = body.tree.all(body.node.id, "p")
  object.check_math_locks()
  guard !paragraphs.is_empty() else {
    @failure.reject("protected-content", "Missing native text paragraph")
  }
  let before = if start { paragraphs[0].start } else { body.node.closing_start }
  let change : @xml.SourceChange = {
    node: body.node.id,
    offset: before - body.node.start,
    length: 0,
    xml: "<a:p>\{equation_markup(formula)}</a:p>",
  }
  let (candidate, edit) = self.prepare_fitted(
    original,
    [change],
    [id],
    probe,
    profile,
  )
  let target = candidate.object(id)
  let (_, _, diagnostic, _) = fit_text(
    target,
    target.geometry.unwrap(),
    probe,
    profile,
  )
  guard target.diagnostic.is_empty() && diagnostic.is_empty() else {
    @failure.reject("layout-overflow", target.diagnostic + diagnostic)
  }
  self.commit(
    candidate,
    edit,
    { ..self.selection, mode: "object", anchor: 0, focus: 0, },
    probe~,
    profile~,
  )
  self.query()
}

///|
fn Session::change_math(
  self : Session,
  target : MathTarget,
  value : (String, @layout.TextStyle)?,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(target.revision)
  guard self.selection.objects == [target.object] else {
    @failure.reject("invalid-operation", "Mathematical target is not selected")
  }
  let original = self.current()
  let object = original.object(target.object)
  let runs = object.paragraphs
    .iter()
    .flat_map(paragraph => paragraph.runs.iter())
  guard runs.find_first(run => {
      run.math is Some(_) &&
      run.source.map(source => source.node.id == target.node).unwrap_or(false)
    })
    is Some(run) &&
    run.source is Some(source) &&
    run.math is Some(previous) else {
    @failure.reject("invalid-operation", "Unknown mathematical target")
  }
  let reason = self.math_reason(object, source)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let formula = value.map(pair => math_value(pair.0, pair.1))
  if formula is Some(formula) &&
    Json(formula.expression) == Json(previous.expression) &&
    Json(formula.style) == Json(previous.style) {
    return self.query()
  }
  let changes : Array[@xml.SourceChange] = []
  if formula is Some(formula) {
    let (root, _) = source.math_source().unwrap()
    changes.push({
      node: source.node.id,
      offset: root.node.start - source.node.start,
      length: root.node.end - root.node.start,
      xml: @omml.markup(formula, drawing=true),
    })
    if Json(formula.expression) != Json(previous.expression) &&
      source.math_fallback_text() is Some(text) {
      changes.push({
        node: text.node.id,
        offset: text.node.opening_end - text.node.start,
        length: text.node.closing_start - text.node.opening_end,
        xml: @xml.escape_text(formula.expression.linear_text()),
      })
    }
  } else {
    let parent = source.tree.nodes[source.node.parent]
    changes.push({
      node: parent.id,
      offset: source.node.start - parent.start,
      length: source.node.end - source.node.start,
      xml: "",
    })
  }
  let (candidate, edit) = self.prepare_fitted(
    original,
    changes,
    [object.id],
    probe,
    profile,
  )
  let updated = candidate.object(object.id)
  if updated.table is Some(_) {
    let (_, _, warnings, _) = updated.paint_table(probe, profile)
    guard warnings.is_empty() else {
      @failure.reject("layout-overflow", warnings.join("; "))
    }
  } else {
    let (_, _, diagnostic, _) = fit_text(
      updated,
      updated.geometry.unwrap(),
      probe,
      profile,
    )
    guard diagnostic.is_empty() else {
      @failure.reject("layout-overflow", diagnostic)
    }
  }
  guard updated.diagnostic.is_empty() else {
    @failure.reject("protected-content", updated.diagnostic)
  }
  self.commit(
    candidate,
    edit,
    { ..self.selection, mode: "object", anchor: 0, focus: 0, },
    probe~,
    profile~,
  )
  self.query()
}
