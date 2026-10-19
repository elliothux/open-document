///|
pub(all) enum ObjectEdit {
  Insert(String, Double, Double, Double, Double, String)
  InsertImage(Bytes, Double, Double, Double, Double)
  InsertTable(Int, Int, Double, Double, Double, Double)
  TableStructure(String)
  SplitTableCell(Int, Int)
  TableRowHeight(Double)
  TableColumnWidth(Double)
  TableStyle(TableStyleSettings)
  ReplaceImage(String, Bytes)
  ImageFill(Array[String], Bytes, String)
  ImageFillMode(String)
  ImageMode(String)
  ImageInsets(Array[Double])
  ImageCrop(Double, Double, Double, Double)
  ImageOpacity(Double)
  Hyperlink(String, String)
  Remove
  Duplicate(Double, Double)
  Rotate(Double)
  Flip(Bool)
  Layer(String)
  Align(String, String)
  Distribute(String, String)
  Group
  Ungroup
  Fill(String?)
  GradientFill(Array[@layout.GradientStop], Double, Bool)
  FillOpacity(Double)
  StrokeOpacity(Double)
  Stroke(String?, Double)
  StrokeDash(String?)
  StrokeCap(String?)
  StrokeJoin(String?, Double)
  StrokeEnd(Bool, LineEnd?)
  ShapeAdjustment(String, Double?)
  TextInsets(Double, Double, Double, Double)
  TextAnchor(String)
  TextWrap(Bool)
  TextFit(String)
  TextFormat(TextFormat)
  TextAlign(String)
  TextParagraph(ParagraphFormat)
  ClearTextFormat
  ClearParagraphFormat
}

///|
fn reserve_drawing_identities(
  document : @xml.Document,
  reserved : Map[String, Bool],
) -> Unit raise @failure.Failure {
  for node in document.nodes() {
    if node.uri == presentation_uri && node.name == "cNvPr" {
      reserved[source_identity(node.attribute("id").unwrap_or(""))] = true
    } else if node.uri == creation_uri && node.name == "creationId" {
      reserved[number(node.attribute("val").unwrap_or(""), 0, 4294967295)
      .to_int64()
      .to_string()] = true
    } else if node.uri == drawing_uri && node.name == "fld" {
      reserved[node.attribute("id").unwrap_or("").to_upper()] = true
    }
  }
}

///|
fn Session::reserved_object_identities(
  self : Session,
) -> Map[String, Bool] raise @failure.Failure {
  let reserved : Map[String, Bool] = Map([])
  // Original cached trees also reserve identities of deleted imported objects.
  for
    tree in [
      ..self.cache.values().to_array(),
      ..self.slides.map(slide => slide.tree),
    ] {
    reserve_drawing_identities(tree.document, reserved)
  }
  reserved
}

///|
fn Session::next_object_identity(
  self : Session,
) -> String raise @failure.Failure {
  let reserved = self.reserved_object_identities()
  let mut next = self.object_sequence
  while reserved.contains(next.to_string()) {
    next += 1
  }
  guard next <= 4294967295L else {
    @failure.reject("limit-exceeded", "Object identities exhausted")
  }
  next.to_string()
}

///|
fn Session::object_edit_reason(
  self : Session,
  object : Object,
  action : String,
) -> String {
  let duplicate = action == "duplicate"
  try {
    let table = object.table is Some(_)
    let grouped = !object.parent.is_empty() &&
      [
        "transform", "rotate", "flip", "arrange", "duplicate", "delete", "group",
        "ungroup",
      ].contains(action)
    if !object.read_only.is_empty() &&
      !(grouped && object.read_only == "Group members are read-only") {
      return object.read_only
    }
    if grouped {
      if !object.diagnostic.is_empty() {
        return object.diagnostic
      }
      let reason = object.member_transform_reason(action)
      if !reason.is_empty() {
        return reason
      }
    }
    if table &&
      !["delete", "duplicate", "arrange", "transform", "group", "ungroup"].contains(
        action,
      ) {
      return "Native table frames do not support rotation or flipping"
    }
    let slide = self.source_slide(object.source.tree.part)
    if !slide.read_only.is_empty() {
      return slide.read_only
    }
    if grouped {
      let mut root = slide.object(object.parent)
      while !root.parent.is_empty() {
        root = slide.object(root.parent)
      }
      if !root.read_only.is_empty() &&
        slide.objects.any(child => {
          child.source.tree.part == root.source.tree.part &&
          child.source.node.start > root.source.node.start &&
          child.source.node.end < root.source.node.end &&
          !child.diagnostic.is_empty()
        }) {
        return "Unknown group members prevent bounds normalization"
      }
    }
    guard (["sp", "pic", "grpSp"].contains(object.source.node.name) || table) &&
      (grouped || object.source.node.parent == shape_tree(slide.tree).id) else {
      return "This operation requires local top-level shapes and pictures"
    }
    if !table &&
      ["rotate", "flip", "arrange", "transform"].contains(action) &&
      object.source.child(
        if object.kind == "group" {
          "grpSpPr"
        } else {
          "spPr"
        },
        uri=presentation_uri,
      )
      is None {
      return "Missing editable shape properties"
    }
    if duplicate && placeholder(object.source) is Some(_) {
      return "Duplicating inherited placeholders is not supported yet"
    }
    let target = object.source.node
    let tree = object.source.tree
    let identities : Map[String, Bool] = Map([])
    let pending = [target]
    while pending.pop() is Some(node) {
      pending.append(tree.children.get(node.id).unwrap_or([]))
      if node.uri == presentation_uri && node.name == "cNvPr" {
        identities[source_identity(node.attribute("id").unwrap_or(""))] = true
      }
      if node.name.has_suffix("Locks") &&
        flag(
          node,
          match action {
            "duplicate" => "noCopy"
            "delete" => "noDelete"
            "rotate" => "noRot"
            _ => ""
          },
        ) {
        return "Object operation is locked: " + action
      }
      if duplicate &&
        (
          node.name == "extLst" ||
          ![presentation_uri, drawing_uri].contains(node.uri)
        ) {
        return "Unknown object extensions prevent duplication"
      }
    }
    if action == "delete" {
      for rel in self.relationships() {
        if rel.owner == tree.part &&
          ![
            relationship_uri + "/slideLayout",
            relationship_uri + "/notesSlide",
            relationship_uri + "/image",
            relationship_uri + "/hyperlink",
            relationship_uri + "/slide",
          ].contains(rel.kind) {
          return "Slide relationship references require object deletion support"
        }
      }
      for node in tree.document.nodes() {
        if node.start >= target.start && node.end <= target.end {
          continue
        }
        for attribute in node.attributes {
          if ["spid", "spId", "shapeId", "shapeIdRef"].contains(attribute.name) ||
            (["stCxn", "endCxn"].contains(node.name) && attribute.name == "id") {
            if identities.contains(source_identity(attribute.value)) {
              return "Referenced objects require connector or timing updates before deletion"
            }
          }
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn object_insertion(
  tree : Tree,
  markup : String,
  parent~ : @xml.Node? = None,
) -> @xml.SourceChange raise @failure.Failure {
  let parent = parent.unwrap_or_else(() => shape_tree(tree))
  if tree.one(parent.id, "extLst", uri=presentation_uri) is Some(node) {
    {
      node: parent.id,
      offset: node.start - parent.start,
      length: 0,
      xml: markup,
    }
  } else {
    insertion(parent, markup)
  }
}

///|
fn validate_object_box(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  line : Bool,
) -> Unit raise @failure.Failure {
  guard [x, y, width, height].all(v => {
      !v.is_nan() && !v.is_inf() && v.abs() <= 14400
    }) &&
    (
      (width >= 0.1 && height >= 0.1) ||
      (line && width >= 0 && height >= 0 && width + height >= 0.1)
    ) else {
    @failure.reject("invalid-transform", "Invalid object position or size")
  }
}

///|
fn object_text_markup(text : String) -> String raise @failure.Failure {
  let style = "<a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:latin typeface=\"Arial\"/>"
  let out = StringBuilder()
  out.write_string(
    "<p:txBody><a:bodyPr wrap=\"square\" anchor=\"t\"><a:noAutofit/></a:bodyPr><a:lstStyle/>",
  )
  for paragraph in text.split("\n") {
    out.write_string("<a:p><a:pPr><a:buNone/></a:pPr>")
    for index, segment in paragraph.split("\u2028").to_array() {
      if index > 0 {
        out.write_string("<a:br/>")
      }
      if !segment.is_empty() {
        out.write_string(
          "<a:r><a:rPr sz=\"1800\">\{style}</a:rPr><a:t xml:space=\"preserve\">\{@xml.escape_text(segment.to_owned())}</a:t></a:r>",
        )
      }
    }
    out.write_string("<a:endParaRPr sz=\"1800\">\{style}</a:endParaRPr></a:p>")
  }
  out.write_string("</p:txBody>")
  out.to_string()
}

///|
pub fn Session::edit_objects(
  self : Session,
  revision : Int,
  change : ObjectEdit,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let original = self.current()
  guard original.read_only.is_empty() else {
    @failure.reject("protected-content", original.read_only)
  }
  if self.selection.objects.length() == 1 &&
    original.object(self.selection.object).table is Some(_) &&
    (
      change is Fill(_) ||
      change is Stroke(_, _) ||
      change is TextInsets(_, _, _, _) ||
      change is TextAnchor(_)
    ) {
    return self.format_table_cells(change, probe, profile)
  }
  if change is TextFormat(_) ||
    change is TextAlign(_) ||
    change is TextParagraph(_) ||
    change is ClearTextFormat ||
    change is ClearParagraphFormat {
    return self.format_objects(change, probe, profile)
  }
  if change is InsertImage(bytes, x, y, width, height) {
    return self.write_image(bytes, Some((x, y, width, height)))
  }
  if change is InsertTable(rows, columns, x, y, width, height) {
    return self.insert_table(rows, columns, x, y, width, height, probe, profile)
  }
  if change is TableStructure(operation) {
    return self.edit_table_structure(operation, probe, profile)
  }
  if change is SplitTableCell(rows, columns) {
    return self.split_table_cell(rows, columns, probe, profile)
  }
  if change is TableRowHeight(value) {
    return self.resize_table_axis(true, value, probe, profile)
  }
  if change is TableColumnWidth(value) {
    return self.resize_table_axis(false, value, probe, profile)
  }
  if change is TableStyle(settings) {
    return self.set_table_style(settings, probe, profile)
  }
  if change is ImageFillMode(mode) {
    return self.set_image_fill_mode(mode)
  }
  if change is ImageMode(mode) {
    return self.set_image_mode(mode)
  }
  if change is ImageInsets(insets) {
    return self.set_image_insets(insets)
  }
  if change is ImageFill(objects, bytes, mode) {
    check_image_fill_mode(mode)
    guard objects == self.selection.objects else {
      @failure.reject(
        "invalid-operation", "Shape selection changed before setting the image fill",
      )
    }
    return self.write_image(bytes, None, fill=true, mode~)
  }
  if change is ReplaceImage(object, bytes) {
    guard self.selection.object == object else {
      @failure.reject(
        "invalid-operation", "Picture selection changed before replacement",
      )
    }
    return self.write_image(bytes, None)
  }
  if change is ImageCrop(left, top, right, bottom) {
    return self.crop_image([left, top, right, bottom])
  }
  if change is ImageOpacity(value) {
    return self.set_image_opacity(value)
  }
  if change is Hyperlink(kind, target) {
    return if self.selection.mode == "text" {
      self.set_text_hyperlink(kind, target)
    } else {
      self.set_object_hyperlink(kind, target)
    }
  }
  if change is ShapeAdjustment(name, value) {
    let changes = self.adjust_shape(name, value)
    if changes.is_empty() {
      return self.query()
    }
    let (candidate, edit) = self.prepare_fitted(
      original,
      changes,
      self.selection.objects,
      probe,
      profile,
    )
    self.commit(candidate, edit, self.selection, probe~, profile~)
    return self.query()
  }
  let mut issued : String? = None
  let (changes, after) = match change {
    InsertImage(_, _, _, _, _)
    | InsertTable(_, _, _, _, _, _)
    | TableStructure(_)
    | SplitTableCell(_, _)
    | TableRowHeight(_)
    | TableColumnWidth(_)
    | TableStyle(_)
    | ReplaceImage(_, _)
    | ImageFill(_, _, _)
    | ImageFillMode(_)
    | ImageMode(_)
    | ImageInsets(_)
    | ImageCrop(_, _, _, _)
    | ImageOpacity(_)
    | Hyperlink(_, _)
    | ShapeAdjustment(_, _)
    | TextFormat(_)
    | TextAlign(_)
    | TextParagraph(_)
    | ClearTextFormat
    | ClearParagraphFormat => abort("Text formatting was dispatched")
    TextInsets(_, _, _, _) | TextAnchor(_) | TextWrap(_) | TextFit(_) =>
      (self.frame_objects(change, probe, profile), self.selection)
    Fill(_) | Stroke(_, _) => (self.paint_objects(change), self.selection)
    GradientFill(stops, angle, scaled) =>
      (self.gradient_objects(Linear(stops, angle, scaled)), self.selection)
    FillOpacity(value) | StrokeOpacity(value) =>
      (self.opacity_objects(value, change is StrokeOpacity(_)), self.selection)
    StrokeDash(value) => (self.dash_objects(value), self.selection)
    StrokeCap(_) | StrokeJoin(_, _) =>
      (self.pen_objects(change), self.selection)
    StrokeEnd(head, value) =>
      (self.line_end_changes(head, value), self.selection)
    Group => {
      let id = self.next_object_identity()
      let result = self.group_changes(id)
      issued = Some(id)
      result
    }
    Ungroup => self.ungroup_changes()
    Insert(kind, x, y, width, height, text) => {
      guard (kind == "text" || supported_shape(kind)) &&
        @xml.valid_text(text) &&
        !text.contains("\r") &&
        text.length() <= 32767 &&
        text.split("\n").count() <= 256 &&
        text.split("\n").all(p => p.length() <= 4096) &&
        (kind != "line" || text.is_empty()) else {
        @failure.reject("invalid-operation", "Invalid object kind or text")
      }
      validate_object_box(x, y, width, height, kind == "line")
      let id = self.next_object_identity()
      issued = Some(id)
      let text_box = kind == "text"
      let preset = if text_box { "rect" } else { kind }
      let fill = if text_box || kind == "line" {
        "<a:noFill/>"
      } else {
        "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>"
      }
      let stroke = if text_box {
        "<a:noFill/>"
      } else {
        "<a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill>"
      }
      let body = if kind == "line" { "" } else { object_text_markup(text) }
      let markup = "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"\{kind} \{id}\"/><p:cNvSpPr txBox=\"\{if text_box { 1 } else { 0 }}\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{(x * 12700).round().to_int64()}\" y=\"\{(y * 12700).round().to_int64()}\"/><a:ext cx=\"\{(width * 12700).round().to_int64()}\" cy=\"\{(height * 12700).round().to_int64()}\"/></a:xfrm><a:prstGeom prst=\"\{preset}\"><a:avLst/></a:prstGeom>\{fill}<a:ln w=\"12700\">\{stroke}</a:ln></p:spPr>\{body}</p:sp>"
      (
        [object_insertion(original.tree, markup)],
        {
          ..self.selection,
          object: original.tree.part + "#" + id,
          objects: [original.tree.part + "#" + id],
          mode: "object",
          anchor: 0,
          focus: 0,
        },
      )
    }
    Remove => {
      if self.selection.object.is_empty() {
        return self.query()
      }
      guard self.selection.mode == "object" else {
        @failure.reject(
          "invalid-operation", "Object deletion requires object selection",
        )
      }
      let changes = self.remove_objects()
      (
        changes,
        {
          ..self.selection,
          object: "",
          objects: [],
          mode: "object",
          anchor: 0,
          focus: 0,
        },
      )
    }
    Duplicate(dx, dy) => {
      guard [dx, dy].all(v => !v.is_nan() && !v.is_inf() && v.abs() <= 14400) else {
        @failure.reject("invalid-transform", "Invalid duplication offset")
      }
      if self.selection.object.is_empty() {
        return self.query()
      }
      let (changes, selection, next) = self.copy_objects(dx, dy)
      issued = Some((next - 1L).to_string())
      (changes, selection)
    }
    Align(_, _) | Distribute(_, _) =>
      (self.position_objects(change), self.selection)
    Layer(direction) => {
      if self.selection.object.is_empty() {
        return self.query()
      }
      (self.layer_objects(direction), self.selection)
    }
    Rotate(_) | Flip(_) => {
      if self.selection.object.is_empty() {
        return self.query()
      }
      let changes : Array[@xml.SourceChange] = []
      for
        object in self.transform_objects(
          action=if change is Rotate(_) { "rotate" } else { "flip" },
        ) {
        changes.append(self.arrange_object(object, change))
      }
      (changes, self.selection)
    }
  }
  if changes.is_empty() {
    return self.query()
  }
  let (candidate, edit) = self.prepare(original, changes)
  if issued is Some(_) {
    for id in after.objects {
      let object = candidate.object(id)
      if object.table is Some(_) {
        let (_, _, warnings, _) = object.paint_table(probe, profile)
        guard warnings.is_empty() else {
          @failure.reject("layout-overflow", warnings.join("; "))
        }
        continue
      }
      let (_, _, diagnostic) = fit_text(
        object,
        object.geometry.unwrap(),
        probe,
        profile,
      )
      guard diagnostic.is_empty() else {
        @failure.reject("layout-overflow", diagnostic)
      }
    }
  }
  self.commit(candidate, edit, after, probe~, profile~)
  if issued is Some(id) {
    self.object_sequence = number(id, 1, 4294967295).to_int64() + 1
  }
  self.query()
}
