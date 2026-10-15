///|
fn Session::prepare(
  self : Session,
  slide : Slide,
  changes : Array[@xml.SourceChange],
) -> (Slide, @xml.Edit) raise @failure.Failure {
  let (document, edit) = slide.tree.document.edit_source(changes)
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(slide.tree.part, document),
  )
  self.validate(candidate)
  (candidate, edit)
}

///|
fn Session::validate(
  self : Session,
  candidate : Slide,
) -> Unit raise @failure.Failure {
  let replacements : Map[String, Bytes] = Map([])
  let mut count = 0
  let mut units = 0
  for original in self.slides {
    let slide = if original.tree.part == candidate.tree.part {
      candidate
    } else {
      original
    }
    count += slide.objects.length()
    for object in slide.objects {
      units += object.text().length()
    }
    if !slide.tree.document.is_original() {
      replacements[slide.tree.part] = slide.tree.document.bytes()
    }
  }
  guard count <= 16384 && units <= 1048576 else {
    @failure.reject(
      "limit-exceeded", "Presentation objects or text exceed budget",
    )
  }
  self.opc.validate_changes(replacements)
}

///|
fn Session::commit(
  self : Session,
  slide : Slide,
  edit : @xml.Edit,
  after : Selection,
) -> Unit raise @failure.Failure {
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Presentation revision exhausted")
  }
  let payload = edit.payload_bytes()
  guard payload <= 4194304 else {
    @failure.reject("limit-exceeded", "Edit exceeds history budget")
  }
  self.validate(slide)
  let index = self.index(slide.tree.part)
  for entry in self.redo {
    self.history_bytes -= entry.bytes
  }
  self.redo.clear()
  while self.history.length() >= 100 ||
        payload.to_int() > 4194304 - self.history_bytes {
    self.history_bytes -= self.history.remove(0).bytes
  }
  self.history.push({
    slide: index,
    edit,
    before: self.selection,
    after,
    bytes: payload.to_int(),
  })
  self.history_bytes += payload.to_int()
  self.slides[index] = slide
  self.selection = after
  self.revision += 1
  self.view = None
}

///|
pub fn Session::undo(
  self : Session,
  revision : Int,
  redo~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let source = if redo { self.redo } else { self.history }
  let target = if redo { self.history } else { self.redo }
  if source.last() is Some(entry) {
    guard self.revision < 2147483647 else {
      @failure.reject("limit-exceeded", "Presentation revision exhausted")
    }
    let original = self.slides[entry.slide]
    let document = original.tree.document.apply(entry.edit, forward=redo)
    let candidate = read_slide(
      self.opc,
      self.main,
      self.cache,
      Tree::new(original.tree.part, document),
    )
    self.validate(candidate)
    self.slides[entry.slide] = candidate
    self.selection = if redo { entry.after } else { entry.before }
    ignore(source.pop())
    target.push(entry)
    self.revision += 1
    self.view = None
  }
  self.query()
}

///|
pub fn Session::save(
  self : Session,
  revision : Int,
) -> Bytes raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let replacements : Map[String, Bytes] = Map([])
  for slide in self.slides {
    if !slide.tree.document.is_original() {
      replacements[slide.tree.part] = slide.tree.document.bytes()
    }
  }
  let bytes = self.opc.save(replacements)
  let checked = @opc.Package::open(bytes, self.budget)
  checked.close()
  bytes
}

///|
fn Session::editable(
  self : Session,
  text : Bool,
) -> Object raise @failure.Failure {
  let slide = self.slides[self.index(self.selection.slide)]
  let object = slide.object(self.selection.object)
  let reason = if !slide.read_only.is_empty() {
    slide.read_only
  } else if text {
    object.text_reason
  } else {
    object.read_only
  }
  guard reason.is_empty() && object.source.tree.part == slide.tree.part else {
    @failure.reject(
      "protected-content",
      if reason.is_empty() {
        "Inherited objects are read-only"
      } else {
        reason
      },
    )
  }
  guard self.selection.mode == (if text { "text" } else { "object" }) else {
    @failure.reject(
      "invalid-operation", "Selection mode does not permit this edit",
    )
  }
  object
}

///|
pub fn Session::begin(
  self : Session,
  revision : Int,
  kind : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard ["text", "transform"].contains(kind) else {
    @failure.reject("invalid-operation", "Unknown gesture kind")
  }
  ignore(self.editable(kind == "text"))
  guard self.sequence < 2147483647 else {
    @failure.reject("limit-exceeded", "Gesture identity exhausted")
  }
  self.sequence += 1
  self.candidate = Some({
    id: self.sequence,
    revision,
    selection: self.selection,
    slide: self.current(),
    edit: None,
    kind,
  })
  self.query()
}

///|
fn Session::gesture(
  self : Session,
  revision : Int,
  id : Int,
) -> Candidate raise @failure.Failure {
  self.check_revision(revision)
  guard self.candidate is Some(candidate) &&
    candidate.id == id &&
    candidate.revision == revision else {
    @failure.reject("stale-gesture", "Gesture identity changed")
  }
  candidate
}

///|
pub fn Session::cancel(
  self : Session,
  revision : Int,
  id : Int,
) -> Json raise @failure.Failure {
  ignore(self.gesture(revision, id))
  self.candidate = None
  self.view = None
  self.query()
}

///|
pub fn Session::finish(
  self : Session,
  revision : Int,
  id : Int,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let candidate = self.gesture(revision, id)
  let original = self.slides[self.index(self.selection.slide)]
  let prepared = if candidate.kind == "transform" {
    let object = original.object(self.selection.object)
    let target = candidate.slide.object(self.selection.object).geometry.unwrap()
    let initial = object.geometry.unwrap()
    if target.x == initial.x &&
      target.y == initial.y &&
      target.width == initial.width &&
      target.height == initial.height {
      None
    } else {
      Some(
        self.prepare_fitted(
          original,
          transform_changes(object, target),
          object.id,
          probe,
          profile,
        ),
      )
    }
  } else {
    candidate.edit.map(edit => (candidate.slide, edit))
  }
  if prepared is Some((slide, edit)) {
    self.commit(slide, edit, candidate.selection)
  }
  self.candidate = None
  self.view = None
  self.query()
}

///|
pub fn Session::transform(
  self : Session,
  revision : Int,
  id : Int,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  let candidate = self.gesture(revision, id)
  guard candidate.kind == "transform" else {
    @failure.reject("invalid-operation", "Not a transform gesture")
  }
  for value in [x, y, width, height] {
    guard !value.is_nan() && !value.is_inf() && value.abs() <= 14400 else {
      @failure.reject("invalid-transform", "Object transform exceeds budget")
    }
  }
  let original = self.slides[self.index(self.selection.slide)]
  let line = original.object(self.selection.object).preset == "line"
  guard (width >= 0.1 && height >= 0.1) ||
    (line && width >= 0 && height >= 0 && width + height >= 0.1) else {
    @failure.reject("invalid-transform", "Object size must be positive")
  }
  let objects = original.objects.copy()
  for index, object in objects {
    if object.id == self.selection.object && object.geometry is Some(geometry) {
      let geometry = {
        ..geometry,
        x,
        y,
        width,
        height,
        matrix: object_matrix(
          x,
          y,
          width,
          height,
          geometry.rotation,
          geometry.flip_x,
          geometry.flip_y,
        ),
      }
      objects[index] = { ..object, geometry: Some(geometry), }
    }
  }
  self.candidate = Some({ ..candidate, slide: { ..original, objects, }, })
  self.view = None
  self.query()
}

///|
fn transform_changes(
  object : Object,
  geometry : Geometry,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let properties = object.source
    .child("spPr", uri=presentation_uri)
    .unwrap_or_error(
      @failure.Failure(
        code="protected-content",
        part=object.source.tree.part,
        offset=-1,
        message="Missing editable shape properties",
      ),
    )
  let transform = properties.child("xfrm")
  let changes : Array[@xml.SourceChange] = []
  let off = "<a:off xmlns:a=\"\{drawing_uri}\" x=\"\{(geometry.x * 12700).round().to_int64()}\" y=\"\{(geometry.y * 12700).round().to_int64()}\"/>"
  let ext = "<a:ext xmlns:a=\"\{drawing_uri}\" cx=\"\{(geometry.width * 12700).round().to_int64()}\" cy=\"\{(geometry.height * 12700).round().to_int64()}\"/>"
  if transform is Some(transform) {
    let missing = StringBuilder()
    for (name, xml) in [("off", off), ("ext", ext)] {
      if transform.child(name) is Some(item) {
        for
          (key, value) in (if name == "off" {
            [("x", geometry.x), ("y", geometry.y)]
          } else {
            [("cx", geometry.width), ("cy", geometry.height)]
          }) {
          let attr = item.node.attributes
            .iter()
            .find_first(attr => attr.uri.is_empty() && attr.name == key)
          guard attr is Some(attr) else {
            @failure.reject("malformed-pptx", "Incomplete transform attribute")
          }
          changes.push({
            node: item.node.id,
            offset: attr.start - item.node.start,
            length: attr.end - attr.start,
            xml: (value * 12700).round().to_int64().to_string(),
          })
        }
      } else {
        missing.write_string(xml)
      }
    }
    if !missing.to_string().is_empty() {
      changes.push(insertion(transform.node, missing.to_string()))
    }
  } else {
    let xml = "<a:xfrm xmlns:a=\"\{drawing_uri}\" rot=\"\{(geometry.rotation * 60000).round().to_int64()}\" flipH=\"\{if geometry.flip_x { 1 } else { 0 }}\" flipV=\"\{if geometry.flip_y { 1 } else { 0 }}\">\{off}\{ext}</a:xfrm>"
    // xfrm is the first spPr child, before geometry and paint declarations.
    if properties.node.empty {
      changes.push(insertion(properties.node, xml))
    } else {
      changes.push({
        node: properties.node.id,
        offset: properties.node.opening_end - properties.node.start,
        length: 0,
        xml,
      })
    }
  }
  changes
}

///|
pub fn Session::drag(
  self : Session,
  revision : Int,
  id : Int,
  dx : Double,
  dy : Double,
  handle : Int,
) -> Json raise @failure.Failure {
  ignore(self.gesture(revision, id))
  guard !dx.is_nan() &&
    !dx.is_inf() &&
    !dy.is_nan() &&
    !dy.is_inf() &&
    dx.abs() <= 14400 &&
    dy.abs() <= 14400 &&
    handle >= 0 &&
    handle <= 4 else {
    @failure.reject("invalid-transform", "Invalid drag delta or handle")
  }
  let object = self.slides[self.index(self.selection.slide)].object(
    self.selection.object,
  )
  let initial = object.geometry.unwrap()
  if handle == 0 {
    return self.transform(
      revision,
      id,
      initial.x + dx,
      initial.y + dy,
      initial.width,
      initial.height,
    )
  }
  let inverse = initial.matrix.inverse()
  let local_x = inverse.a * dx + inverse.c * dy
  let local_y = inverse.b * dx + inverse.d * dy
  let left = handle == 1 || handle == 4
  let top = handle == 1 || handle == 2
  let width = (initial.width + (if left { -local_x } else { local_x })).max(0.1)
  let height = (initial.height + (if top { -local_y } else { local_y })).max(
    0.1,
  )
  let (fixed_x, fixed_y) = initial.matrix.point(
    if left {
      initial.width
    } else {
      0
    },
    if top {
      initial.height
    } else {
      0
    },
  )
  let matrix = object_matrix(
    0,
    0,
    width,
    height,
    initial.rotation,
    initial.flip_x,
    initial.flip_y,
  )
  let (offset_x, offset_y) = matrix.point(
    if left {
      width
    } else {
      0
    },
    if top {
      height
    } else {
      0
    },
  )
  self.transform(
    revision,
    id,
    fixed_x - offset_x,
    fixed_y - offset_y,
    width,
    height,
  )
}
