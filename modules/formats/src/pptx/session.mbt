///|
pub const SlideCountLimit : Int32 = 256

///|
pub struct Session {
  priv opc : @opc.Package
  priv mut main : Tree
  priv mut parts : Map[String, @xml.Document]
  priv mut media : Map[String, Bytes]
  priv mut removed : Array[String]
  priv mut slide_sequence : Int64
  priv mut layout_sequence : Int64
  priv mut master_sequence : Int64
  priv cache : Map[String, Tree]
  priv budget : @archive.Budget
  priv mut width : Double
  priv mut height : Double
  priv mut slides : Array[Slide]
  priv mut last_slide : String
  priv mut source_view : Slide?
  priv mut selection : Selection
  priv mut revision : Int32
  priv history : Array[History]
  priv redo : Array[History]
  priv mut history_bytes : Int32
  priv mut candidate : Candidate?
  priv mut view : View?
  priv mut sequence : Int32
  priv mut media_sequence : Int32
  priv mut object_sequence : Int64
  priv mut closed : Bool
  priv mut date_time : DateTime?
  priv mut showing : ShowState?
  priv mut show_drawing : ShowDrawing?
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
  date_time? : String,
) -> Session raise @failure.Failure {
  Session::from_package(@opc.Package::open(bytes, budget), budget, date_time~)
}

///|
/// Opens a presentation from a stable byte source that supports exact ranges.
pub fn Session::open_reader(
  size : Int32,
  read_at : (Int32, Int32) -> BytesView raise @failure.Failure,
  budget : @archive.Budget,
  date_time? : String,
) -> Session raise @failure.Failure {
  Session::from_package(
    @opc.Package::open_reader(size, read_at, budget),
    budget,
    date_time~,
  )
}

///|
fn Session::from_package(
  opc : @opc.Package,
  budget : @archive.Budget,
  date_time~ : String? = None,
) -> Session raise @failure.Failure {
  errdefer opc.close()
  PresentationReader::open(opc, budget, date_time?).finish()
}

///|
pub struct PresentationReader {
  priv opc : @opc.Package
  priv budget : @archive.Budget
  priv date_time : DateTime?
  priv main : Tree
  priv cache : Map[String, Tree]
  priv width : Double
  priv height : Double
  priv targets : Array[String]
  priv slides : Array[Slide]
  priv mut object_count : Int32
  priv mut finished : Bool
}

///|
/// Reads the presentation manifest before loading individual slides.
pub fn PresentationReader::open(
  opc : @opc.Package,
  budget : @archive.Budget,
  date_time? : String,
) -> PresentationReader raise @failure.Failure {
  let date_time = date_time.map(read_date_time)
  guard !opc.signed else {
    @failure.reject("unsupported-pptx", "Signed presentations are unsupported")
  }
  for rel in opc.relationships() {
    guard !rel.kind.has_prefix("http://purl.oclc.org/ooxml/") else {
      @failure.reject("unsupported-pptx", "Strict OOXML is unsupported")
    }
  }
  let main_part = relation(opc, "", "officeDocument").unwrap_or_error(
    @failure.Failure(
      code="malformed-pptx",
      part="",
      offset=-1,
      message="Missing presentation relationship",
    ),
  )
  guard opc.content_type(main_part) ==
    Some(
      "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml",
    ) else {
    @failure.reject("unsupported-pptx", "Only Transitional PPTX is supported")
  }
  let cache = Map([])
  let main = load_tree(opc, cache, main_part)
  let root = main.root("presentation")
  let (width, height) = presentation_size(main)
  let targets : Array[String] = []
  let ids : Map[String, Bool] = Map([])
  let paths : Map[String, Bool] = Map([])
  let list = main.required(root.id, "sldIdLst", uri=presentation_uri)
  for node in main.all(list.id, "sldId", uri=presentation_uri) {
    let id = source_identity(node.attribute("id").unwrap_or(""))
    ignore(number(id, 256, 2147483647))
    let link = node.attribute("id", uri=relationship_uri).unwrap_or("")
    let rel = opc
      .relationships()
      .iter()
      .find_first(rel => rel.owner == main_part && rel.id == link)
    guard !ids.contains(id) &&
      rel is Some(rel) &&
      !rel.external &&
      rel.kind == relationship_uri + "/slide" &&
      !paths.contains(rel.target) &&
      opc.content_type(rel.target) ==
      Some(
        "application/vnd.openxmlformats-officedocument.presentationml.slide+xml",
      ) else {
      @failure.reject(
        "malformed-pptx", "Invalid slide identity or relationship",
      )
    }
    guard targets.length() < SlideCountLimit else {
      @failure.reject("limit-exceeded", "Slides exceed \{SlideCountLimit}")
    }
    targets.push(rel.target)
    paths[rel.target] = true
    ids[id] = true
  }
  guard !targets.is_empty() else {
    @failure.reject("malformed-pptx", "Presentation has no slides")
  }
  {
    opc,
    budget,
    date_time,
    main,
    cache,
    width,
    height,
    targets,
    slides: [],
    object_count: 0,
    finished: false,
  }
}

///|
/// Loads slides from the current cursor. A failed source read leaves earlier
/// slides intact. The checkpoint runs before each loaded slide is retained.
pub fn PresentationReader::finish(
  self : PresentationReader,
  checkpoint~ : () -> Unit raise @failure.Failure = () => (),
) -> Session raise @failure.Failure {
  guard !self.finished else {
    @failure.reject("invalid-operation", "Presentation reader already finished")
  }
  let {
    opc,
    budget,
    date_time,
    main,
    cache,
    width,
    height,
    targets,
    slides,
    ..
  } = self
  for index in slides.length()..<targets.length() {
    let target = targets[index]
    let slide = read_slide(
      opc,
      main,
      cache,
      load_tree(opc, cache, target),
      index~,
      date_time~,
      media=Map([]),
    ) catch {
      @failure.Failure(code~, part="", offset~, message~) =>
        @failure.reject(code, message, part=target, offset~)
      @failure.Failure(..) as error => raise error
    }
    checkpoint()
    guard slide.objects.length() <= 16384 - self.object_count else {
      @failure.reject("limit-exceeded", "Presentation objects exceed 16384")
    }
    self.object_count += slide.objects.length()
    slides.push(slide)
  }
  let session : Session = {
    opc,
    main,
    parts: Map([]),
    media: Map([]),
    removed: [],
    slide_sequence: 256L,
    layout_sequence: 2147483648L,
    master_sequence: 2147483648L,
    cache,
    budget,
    width,
    height,
    slides,
    last_slide: slides[0].tree.part,
    source_view: None,
    selection: {
      slide: slides[0].tree.part,
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    revision: 0,
    history: [],
    redo: [],
    history_bytes: 0,
    candidate: None,
    view: None,
    sequence: 0,
    media_sequence: 0,
    object_sequence: 1,
    closed: false,
    date_time,
    showing: None,
    show_drawing: None,
  }
  session.validate(slides[0])
  checkpoint()
  self.finished = true
  session
}

///|
fn Session::check(self : Session) -> Unit raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "PPTX session is closed")
  }
}

///|
pub fn Session::check_idle(self : Session) -> Unit raise @failure.Failure {
  self.check_candidate_idle()
  guard self.showing is None else {
    @failure.reject("active-show", "End the slideshow before editing")
  }
}

///|
fn Session::check_candidate_idle(self : Session) -> Unit raise @failure.Failure {
  self.check()
  guard self.candidate is None else {
    @failure.reject(
      "active-gesture", "Complete or cancel composition or drag first",
    )
  }
}

///|
fn Session::check_revision(
  self : Session,
  revision : Int32,
) -> Unit raise @failure.Failure {
  self.check()
  guard revision == self.revision else {
    @failure.reject("revision-conflict", "Presentation revision changed")
  }
}

///|
fn Session::index(
  self : Session,
  slide : String,
) -> Int32 raise @failure.Failure {
  self.check()
  for index, item in self.slides {
    if item.tree.part == slide {
      return index
    }
  }
  @failure.reject("invalid-slide", "Unknown slide identity")
}

///|
fn Session::current(self : Session) -> Slide raise @failure.Failure {
  self.check()
  self.candidate
  .map(item => item.slide)
  .unwrap_or_else(() => self.source_slide(self.selection.slide))
}

///|
fn Slide::object(self : Slide, id : String) -> Object raise @failure.Failure {
  self.objects
  .iter()
  .find_first(object => object.id == id)
  .unwrap_or_error(
    @failure.Failure(
      code="invalid-object",
      part=self.tree.part,
      offset=-1,
      message="Unknown object identity",
    ),
  )
}

///|
#derive(ToJson)
priv struct QueryBackground {
  value : Json
  explicit : Bool
  reason : String
}

///|
#derive(ToJson)
priv struct QuerySlide {
  id : String
  hidden : Bool
  title : String
}

///|
#derive(ToJson)
priv struct QueryState {
  revision : Int32
  editView : EditViewQuery
  guides : Json
  snapping : SnappingQuery
  formatting : Json
  paragraph : Json
  table : Json
  groupReason : String
  ungroupReason : String
  slideOrderReason : String
  slideSizeReason : String
  slideVisibilityReason : String
  sections : SlideCollectionQuery[QuerySection]
  notes : NotesQuery
  transition : QueryTransition
  animations : SlideCollectionQuery[SlideAnimation]
  customShows : SlideCollectionQuery[CustomShow]
  showSettings : ShowSettingsQuery
  footer : QueryFooter
  firstSlideNumber : Double
  comments : Json
  textHyperlink : Json
  slideLayout : SlideLayoutQuery
  themeColors : Json
  themeFonts : Json
  background : QueryBackground
  width : Double
  height : Double
  slide : String
  slides : Array[QuerySlide]
  objects : Array[QueryObject]
  mediaPlayback : MediaPlaybackQuery
  fontKeys : Array[String]
  imageKeys : Array[String]
  selection : Selection
  canUndo : Bool
  canRedo : Bool
  historyBytes : Int32
  candidateId : Json
  readOnlyReason : String
  diagnostics : Array[String]
}

///|
pub fn Session::query(self : Session) -> Json raise @failure.Failure {
  let current = self.current()
  let links = self.relationships()
  let deletion_reason = self.deletion_group_reason()
  let font_slides = self.slides.map(slide => {
    if slide.tree.part == current.tree.part {
      current
    } else {
      slide
    }
  })
  if !self.slides.any(slide => slide.tree.part == current.tree.part) {
    font_slides.push(current)
  }
  let fonts = slide_font_keys(font_slides)
  let result : QueryState = {
    revision: self.revision,
    editView: self.edit_view_query(current),
    guides: self.guides_query(),
    snapping: self.snapping_query(),
    formatting: self.formatting_query(),
    paragraph: self.paragraph_query(),
    table: nullable_json(self.table_query()),
    groupReason: self.group_edit_reason(false),
    ungroupReason: self.group_edit_reason(true),
    slideOrderReason: self.slide_order_reason(),
    slideSizeReason: self.slide_size_reason(),
    slideVisibilityReason: self.slide_visibility_reason(),
    sections: self.section_query(),
    notes: self.notes_query(current.tree.part),
    transition: self.transition_query(current),
    animations: self.animation_query(current),
    customShows: self.custom_show_query(),
    showSettings: self.show_settings_query(),
    footer: self.footer_query(current),
    firstSlideNumber: presentation_first_number(self.main),
    comments: self.comments_query(current.tree.part, links),
    textHyperlink: self.text_hyperlink_query(links),
    slideLayout: self.layout_query(current),
    themeColors: self.theme_colors(),
    themeFonts: self.theme_fonts(),
    background: {
      value: current.background.to_json(),
      explicit: current.tree.one(
        current.tree.required(
          current.tree.document.nodes()[0].id,
          "cSld",
          uri=presentation_uri,
        ).id,
        "bg",
        uri=presentation_uri,
      )
      is Some(_),
      reason: self.background_reason(current),
    },
    width: self.width,
    height: self.height,
    slide: self.selection.slide,
    slides: self.slides.map(slide => {
      id: slide.tree.part,
      hidden: slide.hidden,
      title: slide.objects
      .iter()
      .find_first(object => !object.text().is_empty())
      .map(object => object.text())
      .unwrap_or(""),
    }),
    objects: current.objects.map(object => {
      self.query_object(object, links, deletion_reason)
    }),
    mediaPlayback: self.media_playback_query(),
    fontKeys: fonts,
    imageKeys: self.image_keys(false, false),
    selection: self.candidate
    .map(item => item.selection)
    .unwrap_or(self.selection),
    canUndo: !self.history.is_empty(),
    canRedo: !self.redo.is_empty(),
    historyBytes: self.history_bytes +
    [..self.history, ..self.redo].fold(init=0, (sum, entry) => {
      sum + entry.media_bytes
    }),
    candidateId: self.candidate
    .map(item => Json(item.id))
    .unwrap_or(Json::null()),
    readOnlyReason: current.read_only,
    diagnostics: current.diagnostics,
  }
  ToJson::to_json(result)
}

///|
pub const ObjectSelectionCount : Int32 = 256

///|
pub fn Session::select(
  self : Session,
  revision : Int32,
  slide : String,
  object : String,
  mode : String,
  anchor : Int32,
  focus : Int32,
  objects~ : Array[String]? = None,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let current = self.source_slide(slide)
  if slide != self.selection.slide &&
    !self.slides.any(item => item.tree.part == slide) {
    guard current.objects.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Source view objects exceed 4096")
    }
    self.validate(current)
  }
  guard ["object", "text"].contains(mode) else {
    @failure.reject("invalid-operation", "Unknown selection mode")
  }
  let objects = objects.unwrap_or(if object.is_empty() { [] } else { [object] })
  guard objects.length() <= ObjectSelectionCount else {
    @failure.reject("limit-exceeded", "Selection exceeds 256 objects")
  }
  let seen : Map[String, Bool] = Map([])
  for id in objects {
    guard !id.is_empty() && !seen.contains(id) else {
      @failure.reject(
        "invalid-object", "Selection contains duplicate or empty identities",
      )
    }
    ignore(current.object(id))
    seen[id] = true
  }
  guard (objects.is_empty() && object.is_empty()) || seen.contains(object) else {
    @failure.reject(
      "invalid-object", "Active object must belong to the selection",
    )
  }
  guard mode != "text" || objects.length() == 1 else {
    @failure.reject("invalid-object", "Text mode requires exactly one object")
  }
  if !object.is_empty() {
    let target = current.object(object)
    if mode == "text" {
      guard target.text_reason.is_empty() && !target.paragraphs.is_empty() else {
        @failure.reject(
          "protected-content",
          if target.text_reason.is_empty() {
            "Object has no text frame"
          } else {
            target.text_reason
          },
        )
      }
      let boundaries = @layout.grapheme_boundaries(target.text())
      guard boundaries.contains(anchor) && boundaries.contains(focus) else {
        @failure.reject(
          "invalid-position", "Selection must use grapheme boundaries",
        )
      }
    }
  } else {
    guard mode == "object" else {
      @failure.reject("invalid-object", "Text mode requires an object")
    }
  }
  if self.slides.any(item => item.tree.part == slide) {
    if self.last_slide != slide {
      self.source_view = None
    }
    self.last_slide = slide
  }
  self.selection = {
    slide,
    object,
    objects: objects.copy(),
    mode,
    anchor,
    focus,
  }
  if self.view.map(view => view.slide != slide).unwrap_or(false) {
    self.view = None
  }
  self.query()
}

///|
pub fn Session::image_bytes(
  self : Session,
  key : String,
  preview? : String,
) -> Bytes raise @failure.Failure {
  self.check()
  if preview is Some(part) {
    let slide = self.source_slide(part)
    guard slide.image_keys().contains(key) else {
      @failure.reject("invalid-image", "Unknown slide preview image")
    }
    if slide.shadow(key) is Some(shadow) {
      return shadow.png()
    }
    return self.image_content(key)
  }
  guard self.slides.any(slide => slide.image_keys().contains(key)) ||
    self.current().image_keys().contains(key) else {
    @failure.reject("invalid-image", "Unknown presentation image")
  }
  self.image_content(key)
}

///|
/// Prepare an embedded raster or return its source for the host decoder.
pub fn Session::prepare_image(
  self : Session,
  key : String,
  images : @layout.Images,
  preview? : String,
) -> (Bytes, @layout.ImageResource?) raise @failure.Failure {
  let source = self.image_bytes(key, preview?)
  guard @image.decode_plain_raster(source, exif_orientation=true)
    is Some((width, height, pixels)) else {
    return (source, None)
  }
  images.add(key, width, height, pixels)
  if preview is None {
    self.invalidate_geometry()
  }
  (source, Some(images.get(key)))
}

///|
pub fn Session::invalidate_geometry(self : Session) -> Unit {
  self.view = None
  self.show_drawing = None
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.closed = true
  self.slides.clear()
  self.history.clear()
  self.redo.clear()
  self.cache.clear()
  self.parts.clear()
  self.media.clear()
  self.removed.clear()
  self.candidate = None
  self.source_view = None
  self.showing = None
  self.show_drawing = None
  self.view = None
  self.history_bytes = 0
  self.opc.close()
}
