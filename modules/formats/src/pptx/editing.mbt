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
    index=self.source_index(slide.tree.part),
    date_time=self.date_time,
    parts=self.parts,
  )
  self.validate(candidate)
  (
    candidate
    .group_bounds(candidate.changed_group_members(slide))
    .connector_bounds(slide),
    edit,
  )
}

///|
fn Session::validate(
  self : Session,
  candidate : Slide,
) -> Unit raise @failure.Failure {
  let slides = self.slides.copy()
  let parts = self.parts.copy()
  if slides.search_by(slide => slide.tree.part == candidate.tree.part)
    is Some(index) {
    slides[index] = candidate
  } else {
    guard candidate.objects.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Source view objects exceed 4096")
    }
    parts[candidate.tree.part] = candidate.tree.document
    let updated = slides.mapi((index, slide) => {
      read_slide(
        self.opc,
        self.main,
        self.cache,
        slide.tree,
        index~,
        parts~,
        date_time=self.date_time,
      )
    })
    updated.push(candidate)
    self.validate_slides(self.main, updated, parts~)
    return
  }
  self.validate_slides(self.main, slides)
}

///|
fn Session::validate_slides(
  self : Session,
  main : Tree,
  slides : Array[Slide],
  parts~ : Map[String, @xml.Document] = self.parts,
  media~ : Map[String, Bytes] = self.media,
  removed~ : Array[String] = self.removed,
  check_package~ : Bool = true,
) -> Unit raise @failure.Failure {
  ignore(slide_font_keys(slides))
  let mut count = 0
  let mut units = 0
  let (width, height) = presentation_size(main)
  let images : Map[String, Bool] = Map([])
  for slide in slides {
    ignore(self.tile_sizes(slide, media~, width~, height~))
    for key in slide.image_keys() {
      images[key] = true
    }
    if slide.background is Picture(_, crop, _, None, insets) {
      check_image_crop_bounds(width, height, crop, insets~)
    }
    count += slide.objects.length()
    for object in slide.objects {
      units += object.text().length()
    }
  }
  guard images.length() <= 256 else {
    @failure.reject("limit-exceeded", "Presentation images exceed 256")
  }
  guard count <= 16384 && units <= 1048576 else {
    @failure.reject(
      "limit-exceeded", "Presentation objects or text exceed budget",
    )
  }
  if check_package {
    self.check_media_budget(main, slides, parts, media, removed~)
    self.opc.validate_changes(
      self.replacements(main, slides, parts, media~),
      removed~,
    )
  }
}

///|
fn Session::commit(
  self : Session,
  slide : Slide,
  edit : @xml.Edit,
  after : Selection,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
) -> Unit raise @failure.Failure {
  self.commit_page(slide, [(slide.tree.part, edit)], after, probe?, profile~)
}

///|
fn Session::commit_slides(
  self : Session,
  main : Tree,
  slides : Array[Slide],
  edits : Array[(String, @xml.Edit)],
  after : Selection,
  parts~ : Map[String, @xml.Document] = self.parts,
  created~ : Array[(Slide, @xml.Document)] = [],
  created_parts~ : Map[String, @xml.Document] = Map([]),
  media~ : Map[String, Bytes] = self.media,
  created_media~ : Map[String, Bytes] = Map([]),
  deleted~ : Array[Slide] = [],
  removed~ : Map[String, @xml.Document] = Map([]),
) -> Unit raise @failure.Failure {
  let parts = parts.copy()
  let edits = edits.copy()
  self.sync_show_range(slides.length(), parts, edits)
  let slides = if self.source_inheritance_changed(edits, parts) {
    slides.mapi((index, slide) => {
      read_slide(
        self.opc,
        main,
        self.cache,
        slide.tree,
        index~,
        parts~,
        date_time=self.date_time,
      )
    })
  } else {
    slides
  }
  let slides = slides.mapi((index, slide) => {
    let numbered = numbered_slide(slide, presentation_number(main, index))
    let (bounded, edit) = self.normalize_groups(numbered, main, index, parts)
    if edit is Some(edit) {
      edits.push((slide.tree.part, edit))
    }
    let (connected, edit) = self.normalize_connectors(
      bounded, main, index, parts,
    )
    if edit is Some(edit) {
      edits.push((slide.tree.part, edit))
    }
    connected
  })
  guard self.revision < 2147483647 else {
    @failure.reject("limit-exceeded", "Presentation revision exhausted")
  }
  let (width, height) = presentation_size(main)
  let media_payload = created_media
    .iter()
    .fold(init=0L, (sum, pair) => {
      let content_type = image_content_type(self.opc, pair.0, parts).unwrap_or(
        "",
      )
      sum +
      (if content_type.has_prefix("audio/") || content_type.has_prefix("video/") {
        pair.1.length().to_int64()
      } else {
        0L
      })
    })
  let payload = edits
    .iter()
    .fold(init=0L, (sum, entry) => sum + entry.1.payload_bytes()) +
    created.fold(init=0L, (sum, pair) => {
      sum +
      (
        pair.0.tree.document.source().length().to_int64() +
        pair.1.source().length().to_int64()
      ) *
      2
    }) +
    created_parts
    .values()
    .fold(init=0L, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    }) +
    removed
    .values()
    .fold(init=0L, (sum, document) => {
      sum + document.source().length().to_int64() * 2
    }) +
    created_media
    .values()
    .fold(init=0L, (sum, bytes) => sum + bytes.length().to_int64()) -
    media_payload
  guard payload <= 4194304 && media_payload <= 67108864 else {
    @failure.reject("limit-exceeded", "Edit exceeds history budget")
  }
  let removed_parts = self.removed.copy()
  for name in removed.keys() {
    if self.opc.names.contains(name.to_lower()) {
      removed_parts.push(name)
    }
  }
  self.validate_slides(main, slides, parts~, media~, removed=removed_parts)
  for entry in self.redo {
    self.history_bytes -= entry.bytes
  }
  self.redo.clear()
  let mut retained_media = self.history.fold(init=0, (sum, entry) => {
    sum + entry.media_bytes
  })
  while self.history.length() >= 100 ||
        payload.to_int() > 4194304 - self.history_bytes ||
        media_payload.to_int() > 67108864 - retained_media {
    let removed = self.history.remove(0)
    self.history_bytes -= removed.bytes
    retained_media -= removed.media_bytes
  }
  self.history.push({
    edits,
    created,
    created_parts,
    created_media,
    deleted,
    removed,
    before: self.selection,
    after,
    bytes: payload.to_int(),
    media_bytes: media_payload.to_int(),
  })
  self.history_bytes += payload.to_int()
  self.main = main
  self.width = width
  self.height = height
  self.parts = parts
  self.source_view = None
  self.media = media
  self.removed = removed_parts
  self.slides = slides
  self.selection = after
  if self.slides.any(slide => slide.tree.part == after.slide) {
    self.last_slide = after.slide
  }
  self.revision += 1
  self.view = None
}

///|
pub fn Session::undo(
  self : Session,
  revision : Int32,
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
    let slides = self.slides.copy()
    let parts = self.parts.copy()
    let media = self.media.copy()
    let removed_parts = self.removed.copy()
    let deleted_documents : Map[String, @xml.Document] = Map([])
    let deleted_slides : Array[Slide] = []
    let removed : Array[(Slide, @xml.Document)] = []
    let removed_created_parts : Map[String, @xml.Document] = Map([])
    if redo {
      for (slide, relations) in entry.created {
        slides.push(slide)
        parts[relationship_part(slide.tree.part)] = relations
      }
    }
    if redo {
      for name, document in entry.created_parts {
        guard !parts.contains(name) else {
          @failure.reject(
            "invalid-operation", "Created slide part already exists",
          )
        }
        parts[name] = document
      }
      for name, bytes in entry.created_media {
        media[name] = bytes
      }
    }
    if !redo && (!entry.deleted.is_empty() || !entry.removed.is_empty()) {
      slides.append(entry.deleted)
      for name, document in entry.removed {
        if !entry.deleted.any(slide => slide.tree.part == name) {
          parts[name] = document
        }
        if removed_parts.search(name) is Some(index) {
          ignore(removed_parts.remove(index))
        }
      }
    }
    let mut main = self.main
    for (part, edit) in (if redo { entry.edits } else { entry.edits.rev() }) {
      if part == main.part {
        main = Tree::new(part, main.document.apply(edit, forward=redo))
      } else {
        guard slides.search_by(slide => slide.tree.part == part) is Some(index) else {
          let document = parts
            .get(part)
            .unwrap_or_else(() => self.opc.xml(part))
          parts[part] = document.apply(edit, forward=redo)
          continue
        }
        let original = slides[index]
        let document = original.tree.document.apply(edit, forward=redo)
        slides[index] = read_slide(
          self.opc,
          main,
          self.cache,
          Tree::new(part, document),
          index~,
          date_time=self.date_time,
          parts~,
        )
      }
    }
    if !redo {
      for (created, _) in entry.created {
        let slide = slides.remove(
          slides
          .search_by(slide => slide.tree.part == created.tree.part)
          .unwrap(),
        )
        guard slide.tree.document.source() == created.tree.document.source() else {
          @failure.reject(
            "invalid-operation", "Created slide history has changed",
          )
        }
        let relation_path = relationship_part(slide.tree.part)
        let relations = parts[relation_path]
        parts.remove(relation_path)
        removed.push((slide, relations))
      }
    }
    if !redo {
      for name, snapshot in entry.created_parts {
        guard parts.get(name) is Some(document) &&
          document.source() == snapshot.source() else {
          @failure.reject(
            "invalid-operation", "Created slide part history has changed",
          )
        }
        removed_created_parts[name] = document
        parts.remove(name)
      }
      for name, bytes in entry.created_media {
        guard media.get(name) == Some(bytes) else {
          @failure.reject(
            "invalid-operation", "Created image history has changed",
          )
        }
        media.remove(name)
      }
    }
    if redo && (!entry.deleted.is_empty() || !entry.removed.is_empty()) {
      for deleted in entry.deleted {
        guard slides.search_by(slide => slide.tree.part == deleted.tree.part)
          is Some(index) else {
          @failure.reject(
            "invalid-operation", "Deleted slide history has changed",
          )
        }
        deleted_slides.push(slides.remove(index))
      }
      for name, _ in entry.removed {
        deleted_documents[name] = if deleted_slides
          .iter()
          .find_first(slide => slide.tree.part == name)
          is Some(slide) {
          slide.tree.document
        } else {
          parts.get(name).unwrap_or_else(() => self.opc.xml(name))
        }
        parts.remove(name)
        if self.opc.names.contains(name.to_lower()) {
          removed_parts.push(name)
        }
      }
    }
    let slides = self.ordered_slides(
      main,
      slides,
      parts~,
      media~,
      removed=removed_parts,
    )
    let (width, height) = presentation_size(main)
    let theme_changed = self.source_inheritance_changed(entry.edits, parts)
    let slides = if width != self.width ||
      height != self.height ||
      theme_changed {
      slides.mapi((index, slide) => {
        read_slide(
          self.opc,
          main,
          self.cache,
          slide.tree,
          index~,
          parts~,
          date_time=self.date_time,
        )
      })
    } else {
      slides
    }
    self.validate_slides(main, slides, parts~, media~, removed=removed_parts)
    // Preserve identity allocation after later edits were undone, for their next redo.
    if !removed.is_empty() {
      entry.created = removed
    }
    for name, document in removed_created_parts {
      entry.created_parts[name] = document
    }
    if !deleted_slides.is_empty() {
      entry.deleted = deleted_slides
      for name, document in deleted_documents {
        entry.removed[name] = document
      }
    }
    self.main = main
    self.width = width
    self.height = height
    self.parts = parts
    self.source_view = None
    self.media = media
    self.removed = removed_parts
    self.slides = slides
    self.selection = if redo { entry.after } else { entry.before }
    if self.slides.any(slide => slide.tree.part == self.selection.slide) {
      self.last_slide = self.selection.slide
    }
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
  revision : Int32,
) -> Bytes raise @failure.Failure {
  self.check_revision(revision)
  self.check_candidate_idle()
  let replacements = self.replacements(self.main, self.slides, self.parts)
  let bytes = self.opc.save(replacements, removed=self.removed)
  let checked = @opc.Package::open(bytes, self.budget)
  checked.close()
  bytes
}

///|
fn Session::editable(
  self : Session,
  text : Bool,
) -> Object raise @failure.Failure {
  guard self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "This operation requires one selected object",
    )
  }
  let slide = self.source_slide(self.selection.slide)
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
  revision : Int32,
  kind : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard ["text", "transform", "connector", "adjustment"].contains(kind) else {
    @failure.reject("invalid-operation", "Unknown gesture kind")
  }
  if kind == "adjustment" {
    ignore(self.adjustment_object())
  } else if kind == "connector" {
    ignore(self.connector_for_gesture())
  } else if kind == "transform" {
    ignore(self.transform_objects(action="transform"))
  } else {
    ignore(self.editable(true))
  }
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
    guide: None,
    snap_lines: [],
    snap_spacing: (false, false),
    snap_size: (false, false),
  })
  self.query()
}

///|
fn Session::gesture(
  self : Session,
  revision : Int32,
  id : Int32,
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
  revision : Int32,
  id : Int32,
) -> Json raise @failure.Failure {
  ignore(self.gesture(revision, id))
  self.candidate = None
  self.view = None
  self.query()
}

///|
pub fn Session::finish(
  self : Session,
  revision : Int32,
  id : Int32,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let candidate = self.gesture(revision, id)
  if candidate.guide is Some(guide) {
    ignore(self.commit_guide(guide))
    self.candidate = None
    self.view = None
    return self.query()
  }
  let original = self.source_slide(self.selection.slide)
  let prepared = if candidate.kind == "transform" {
    let changes : Array[@xml.SourceChange] = []
    for id in self.selection.objects {
      let object = original.object(id)
      let target = candidate.slide.object(id).geometry.unwrap()
      let initial = object.geometry.unwrap()
      if member_geometry_changed(initial, target) {
        changes.append(transform_changes(object, target))
      }
    }
    if changes.is_empty() {
      None
    } else {
      Some(
        self.prepare_fitted(
          original,
          changes,
          self.selection.objects,
          probe,
          profile,
        ),
      )
    }
  } else if candidate.kind == "adjustment" {
    self.finish_adjustment(candidate, probe, profile)
  } else {
    candidate.edit.map(edit => (candidate.slide, edit))
  }
  if prepared is Some((slide, edit)) {
    self.commit(slide, edit, candidate.selection, probe~, profile~)
  }
  self.candidate = None
  self.view = None
  self.query()
}

///|
pub fn Session::transform(
  self : Session,
  revision : Int32,
  id : Int32,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  let candidate = self.gesture(revision, id)
  guard candidate.kind == "transform" else {
    @failure.reject("invalid-operation", "Not a transform gesture")
  }
  if self.selection.objects.length() > 1 {
    return self.transform_collection(candidate, x, y, width, height)
  }
  let object = self
    .source_slide(self.selection.slide)
    .object(self.selection.object)
  self.preview_transform(candidate, {
    ..object.geometry.unwrap(),
    x,
    y,
    width,
    height,
  })
}

///|
fn Session::preview_transform(
  self : Session,
  candidate : Candidate,
  target : Geometry,
) -> Json raise @failure.Failure {
  let (x, y, width, height) = (target.x, target.y, target.width, target.height)
  for value in [x, y, width, height] {
    guard !value.is_nan() && !value.is_inf() && value.abs() <= 14400 else {
      @failure.reject("invalid-transform", "Object transform exceeds budget")
    }
  }
  let original = self.source_slide(self.selection.slide)
  let line = line_shape(original.object(self.selection.object).preset)
  guard (width >= 0.1 && height >= 0.1) ||
    (line && width >= 0 && height >= 0 && width + height >= 0.1) else {
    @failure.reject("invalid-transform", "Object size must be positive")
  }
  let objects = original.objects.copy()
  for index, object in objects {
    if object.id == self.selection.object && object.geometry is Some(geometry) {
      if geometry.flip_x != target.flip_x || geometry.flip_y != target.flip_y {
        let reason = self.object_edit_reason(object, "flip")
        guard reason.is_empty() else {
          @failure.reject("protected-content", reason)
        }
      }
      let geometry = object.placed_geometry(target)
      objects[index] = {
        ..object,
        geometry: Some(geometry),
        table: object.table.map(table => table.resized(width, height)),
      }
    }
  }
  let preview = original
    .group_preview(objects)
    .group_bounds(
      self.selection.objects.filter(id => {
        member_geometry_changed(
          original.object(id).geometry.unwrap(),
          objects.iter().find_first(o => o.id == id).unwrap().geometry.unwrap(),
        )
      }),
    )
    .connector_bounds(original)
  ignore(self.tile_sizes(preview))
  self.candidate = Some({
    ..candidate,
    slide: preview,
    snap_lines: [],
    snap_spacing: (false, false),
    snap_size: (false, false),
  })
  self.view = None
  self.query()
}
