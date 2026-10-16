///|
pub struct Session {
  priv opc : @opc.Package
  priv mut main : Tree
  priv cache : Map[String, Tree]
  priv budget : @archive.Budget
  priv width : Double
  priv height : Double
  priv mut slides : Array[Slide]
  priv mut selection : Selection
  priv mut revision : Int
  priv history : Array[History]
  priv redo : Array[History]
  priv mut history_bytes : Int
  priv mut candidate : Candidate?
  priv mut view : View?
  priv mut sequence : Int
  priv mut object_sequence : Int64
  priv mut closed : Bool
}

///|
fn read_slide(
  opc : @opc.Package,
  main : Tree,
  cache : Map[String, Tree],
  tree : Tree,
) -> Slide raise @failure.Failure {
  let root = tree.root("sld")
  let layout_part = relation(opc, tree.part, "slideLayout").unwrap_or_error(
    @failure.Failure(
      code="malformed-pptx",
      part=tree.part,
      offset=-1,
      message="Missing slide layout",
    ),
  )
  let layout = load_tree(opc, cache, layout_part)
  ignore(layout.root("sldLayout"))
  let master_part = relation(opc, layout.part, "slideMaster").unwrap_or_error(
    @failure.Failure(
      code="malformed-pptx",
      part=layout.part,
      offset=-1,
      message="Missing slide master",
    ),
  )
  let master = load_tree(opc, cache, master_part)
  ignore(master.root("sldMaster"))
  let theme_part = relation(opc, master.part, "theme").unwrap_or_error(
    @failure.Failure(
      code="malformed-pptx",
      part=master.part,
      offset=-1,
      message="Missing master theme",
    ),
  )
  guard tree.part != layout.part &&
    layout.part != master.part &&
    master.part != theme_part &&
    tree.part != master.part &&
    tree.part != theme_part &&
    layout.part != theme_part else {
    @failure.reject("malformed-pptx", "Cyclic slide inheritance")
  }
  let theme = read_theme(load_tree(opc, cache, theme_part), [
    tree, layout, master,
  ])
  let defaults = main
    .one(main.document.nodes()[0].id, "defaultTextStyle", uri=presentation_uri)
    .map(node => { tree: main, node, })
  let objects : Array[Object] = []
  let diagnostics : Array[String] = []
  let ids : Map[String, Bool] = Map([])
  let identity = @layout.Matrix::identity()
  if flag(root, "showMasterSp", default=true) &&
    flag(layout.document.nodes()[0], "showMasterSp", default=true) {
    read_objects(
      opc,
      master,
      shape_tree(master).id,
      theme,
      None,
      master,
      defaults,
      identity,
      "Master objects are read-only",
      0,
      objects,
      ids,
    )
  }
  if flag(root, "showMasterSp", default=true) {
    read_objects(
      opc,
      layout,
      shape_tree(layout).id,
      theme,
      None,
      master,
      defaults,
      identity,
      "Layout objects are read-only",
      0,
      objects,
      ids,
    )
  }
  read_objects(
    opc,
    tree,
    shape_tree(tree).id,
    theme,
    Some(layout),
    master,
    defaults,
    identity,
    "",
    0,
    objects,
    ids,
  )
  let mut background = "ffffff"
  for layer in [tree, layout, master] {
    let container = layer.required(
      layer.document.nodes()[0].id,
      "cSld",
      uri=presentation_uri,
    )
    if layer.one(container.id, "bg", uri=presentation_uri) is Some(bg) {
      if layer.one(bg.id, "bgPr", uri=presentation_uri) is Some(properties) {
        background = fill(theme, [{ tree: layer, node: properties, }]) catch {
          @failure.Failure(code="unsupported-style", message~, ..) => {
            diagnostics.push(layer.part + ":" + message)
            "ffffff"
          }
          error => raise error
        }
      } else if layer.one(bg.id, "bgRef", uri=presentation_uri)
        is Some(reference) {
        background = (fn() raise @failure.Failure {
          let resolved = theme_reference(
            theme,
            { tree: layer, node: reference, },
            "fill",
          )
          guard resolved is Some((item, ph)) && item.node.name == "solidFill" else {
            @failure.reject("unsupported-style", "Unsupported theme background")
          }
          color(theme, item, placeholder=ph)
        })() catch {
          @failure.Failure(code="unsupported-style", message~, ..) => {
            diagnostics.push(layer.part + ":" + message)
            "ffffff"
          }
          error => raise error
        }
      } else {
        diagnostics.push(layer.part + ":Unsupported background reference")
      }
      break
    }
  }
  let mut read_only = ""
  for object in objects {
    if !object.diagnostic.is_empty() {
      diagnostics.push(object.id + ":" + object.diagnostic)
    }
    if !object.text_reason.is_empty() && object.read_only.is_empty() {
      diagnostics.push(object.id + ":" + object.text_reason)
    }
    if object.geometry is None {
      read_only = "Unresolved object bounds prevent direct canvas editing"
    }
  }
  {
    tree,
    hidden: !flag(root, "show", default=true),
    objects,
    background,
    diagnostics,
    read_only,
  }
}

///|
pub fn Session::open(
  bytes : Bytes,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  Session::from_package(@opc.Package::open(bytes, budget), budget)
}

///|
fn Session::from_package(
  opc : @opc.Package,
  budget : @archive.Budget,
) -> Session raise @failure.Failure {
  errdefer opc.close()
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
  let size = main.required(root.id, "sldSz", uri=presentation_uri)
  let width = number(size.attribute("cx").unwrap_or("0"), 12700, 182880000) /
    12700
  let height = number(size.attribute("cy").unwrap_or("0"), 12700, 182880000) /
    12700
  let slides : Array[Slide] = []
  let ids : Map[String, Bool] = Map([])
  let paths : Map[String, Bool] = Map([])
  let mut count = 0
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
    guard slides.length() < 256 else {
      @failure.reject("limit-exceeded", "Slides exceed 256")
    }
    let slide = read_slide(opc, main, cache, load_tree(opc, cache, rel.target))
    count += slide.objects.length()
    guard count <= 16384 else {
      @failure.reject("limit-exceeded", "Presentation objects exceed 16384")
    }
    slides.push(slide)
    paths[rel.target] = true
    ids[id] = true
  }
  guard !slides.is_empty() else {
    @failure.reject("malformed-pptx", "Presentation has no slides")
  }
  let session : Session = {
    opc,
    main,
    cache,
    budget,
    width,
    height,
    slides,
    selection: {
      slide: slides[0].tree.part,
      object: "",
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
    object_sequence: 1,
    closed: false,
  }
  session.validate(slides[0])
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
  revision : Int,
) -> Unit raise @failure.Failure {
  self.check()
  guard revision == self.revision else {
    @failure.reject("revision-conflict", "Presentation revision changed")
  }
}

///|
fn Session::index(self : Session, slide : String) -> Int raise @failure.Failure {
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
  .unwrap_or(self.slides[self.index(self.selection.slide)])
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
pub fn Session::query(self : Session) -> Json raise @failure.Failure {
  let current = self.current()
  let fonts : Array[String] = []
  for stored in self.slides {
    let slide = if stored.tree.part == current.tree.part {
      current
    } else {
      stored
    }
    for object in slide.objects {
      for paragraph in object.paragraphs {
        if !paragraph.bullet.is_empty() &&
          !fonts.contains(paragraph.bullet_style.font) {
          fonts.push(paragraph.bullet_style.font)
        }
        for run in paragraph.runs {
          for (style, _) in run.parts {
            if !fonts.contains(style.font) {
              fonts.push(style.font)
            }
          }
        }
      }
    }
  }
  guard fonts.length() <= 256 else {
    @failure.reject("limit-exceeded", "Font keys exceed 256")
  }
  {
    "revision": self.revision,
    "slideOrderReason": self.slide_order_reason(),
    "slideVisibilityReason": self.slide_visibility_reason(),
    "width": self.width,
    "height": self.height,
    "slide": self.selection.slide,
    "slides": self.slides.map(slide => {
      let value : Json = {
        "id": slide.tree.part,
        "hidden": slide.hidden,
        "title": slide.objects
        .iter()
        .find_first(object => !object.text().is_empty())
        .map(object => object.text())
        .unwrap_or(""),
      }
      value
    }),
    "objects": current.objects.map(object => {
      let value : Json = {
        "id": object.id,
        "name": object.name,
        "kind": object.kind,
        "text": object.text(),
        "readOnlyReason": object.read_only,
        "textReadOnlyReason": object.text_reason,
        "deleteReason": self.object_edit_reason(object, "delete"),
        "duplicateReason": self.object_edit_reason(object, "duplicate"),
        "rotateReason": self.object_edit_reason(object, "rotate"),
        "arrangeReason": self.object_edit_reason(object, "arrange"),
        "geometry": object.geometry
        .map(value => {
          let json : Json = {
            "x": value.x,
            "y": value.y,
            "width": value.width,
            "height": value.height,
            "rotation": value.rotation,
            "flipX": value.flip_x,
            "flipY": value.flip_y,
            "matrix": value.matrix,
          }
          json
        })
        .unwrap_or(Json::null()),
      }
      value
    }),
    "fontKeys": fonts,
    "imageKeys": self.image_keys(false, false),
    "selection": self.candidate
    .map(item => item.selection)
    .unwrap_or(self.selection),
    "canUndo": !self.history.is_empty(),
    "canRedo": !self.redo.is_empty(),
    "historyBytes": self.history_bytes,
    "candidateId": self.candidate
    .map(item => Json(item.id))
    .unwrap_or(Json::null()),
    "readOnlyReason": current.read_only,
    "diagnostics": current.diagnostics,
  }
}

///|
pub fn Session::select(
  self : Session,
  revision : Int,
  slide : String,
  object : String,
  mode : String,
  anchor : Int,
  focus : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let current = self.slides[self.index(slide)]
  guard ["object", "text"].contains(mode) else {
    @failure.reject("invalid-operation", "Unknown selection mode")
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
  self.selection = { slide, object, mode, anchor, focus, }
  if self.view.map(view => view.slide != slide).unwrap_or(false) {
    self.view = None
  }
  self.query()
}

///|
pub fn Session::image_bytes(
  self : Session,
  key : String,
) -> Bytes raise @failure.Failure {
  self.check()
  guard self.slides.any(slide => {
    slide.objects.any(object => object.image == Some(key))
  }) else {
    @failure.reject("invalid-image", "Unknown presentation image")
  }
  self.opc.read(key)
}

///|
pub fn Session::invalidate_geometry(self : Session) -> Unit {
  self.view = None
}

///|
pub fn Session::close(self : Session) -> Unit {
  self.closed = true
  self.slides.clear()
  self.history.clear()
  self.redo.clear()
  self.cache.clear()
  self.candidate = None
  self.view = None
  self.history_bytes = 0
  self.opc.close()
}
