///|
pub(all) enum SlideEdit {
  AddSlide
  CopySlide
  DeleteSlide
  MoveSlide(Int)
  HideSlide(Bool)
  Transition(SlideTransition?)
  Advance(SlideAdvance)
  Animations(Array[SlideAnimation])
  CustomShows(Array[CustomShow])
  Background(BackgroundFill?)
  BackgroundImage(Bytes, String)
  BackgroundImageFormat(String, Array[Double], Double)
  BackgroundImageInsets(Array[Double])
  ThemeColor(String, String)
  ThemeFont(String, String, String)
  ApplyLayout(String)
  ResetLayout
  Notes(String)
  Footer(FooterContent, Bool)
  FirstSlideNumber(Double)
  AddComment(String, String, String, String, String?)
  UpdateComment(String, String)
  RemoveComment(String)
  Size(Double, Double)
  AddSection(String)
  RenameSection(String, String)
  RemoveSection(String)
  RemoveSections
  DeleteSection(String)
  MoveSection(String, Int)
}

///|
fn Session::ordered_slides(
  self : Session,
  main : Tree,
  available : Array[Slide],
  parts~ : Map[String, @xml.Document] = self.parts,
  media~ : Map[String, Bytes] = self.media,
  removed~ : Array[String] = self.removed,
) -> Array[Slide] raise @failure.Failure {
  let list = main.required(
    main.root("presentation").id,
    "sldIdLst",
    uri=presentation_uri,
  )
  let paths : Map[String, String] = Map([])
  for
    relation in self.opc.relationships(
      replacements=self.replacements(main, available, parts, media~),
      removed~,
    ) {
    if relation.owner == main.part &&
      relation.kind == relationship_uri + "/slide" {
      paths[relation.id] = relation.target
    }
  }
  let slides : Map[String, Slide] = Map([])
  for slide in available {
    slides[slide.tree.part] = slide
  }
  let result : Array[Slide] = []
  for node in main.all(list.id, "sldId", uri=presentation_uri) {
    let relation = node.attribute("id", uri=relationship_uri).unwrap_or("")
    guard paths.get(relation) is Some(part) && slides.get(part) is Some(slide) else {
      @failure.reject("malformed-pptx", "Slide identity changed")
    }
    result.push(slide)
    slides.remove(part) |> ignore
  }
  guard slides.is_empty() && !result.is_empty() else {
    @failure.reject("malformed-pptx", "Slide list changed unexpectedly")
  }
  result.mapi((index, slide) => {
    let slide = if slide.date_time == self.date_time.map(time => time.value) {
      slide
    } else {
      read_slide(
        self.opc,
        main,
        self.cache,
        slide.tree,
        index~,
        parts~,
        date_time=self.date_time,
      )
    }
    numbered_slide(slide, presentation_number(main, index))
  })
}

///|
fn Session::slide_visibility_reason(self : Session) -> String {
  try {
    if self.main.one(
        self.main.root("presentation").id,
        "modifyVerifier",
        uri=presentation_uri,
      )
      is Some(_) {
      "Presentation modification is protected"
    } else {
      ""
    }
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn preserved_slide_extensions(
  tree : Tree,
  list : @xml.Node,
  properties~ : Bool,
) -> Bool {
  let p14 = "http://schemas.microsoft.com/office/powerpoint/2010/main"
  let p15 = "http://schemas.microsoft.com/office/powerpoint/2012/main"
  tree.children
  .get(list.id)
  .unwrap_or([])
  .all(extension => {
    if extension.uri != presentation_uri || extension.name != "ext" {
      return false
    }
    let children = tree.children.get(extension.id).unwrap_or([])
    guard children is [item] else { return false }
    if !properties && item.uri == creation_uri && item.name == "sectionLst" {
      return extension.attribute("uri").map(v => v.to_upper()) ==
        Some(section_extension)
    }
    let known = if properties {
      (
        item.uri == p14 &&
        ["discardImageEditData", "defaultImageDpi"].contains(item.name)
      ) ||
      (item.uri == p15 && item.name == "chartTrackingRefBased")
    } else {
      item.uri == p15 && ["sldGuideLst", "notesGuideLst"].contains(item.name)
    }
    // shortcut: Nonempty guide content stays protected until its schema is supported.
    known && tree.children.get(item.id).unwrap_or([]).is_empty()
  })
}

///|
fn Session::slide_order_reason(self : Session) -> String {
  try {
    let reason = self.slide_visibility_reason()
    if !reason.is_empty() {
      return reason
    }
    ignore(read_sections(self.main))
    let root = self.main.root("presentation")
    for node in self.main.children.get(root.id).unwrap_or([]) {
      if node.uri != presentation_uri ||
        ![
          "sldMasterIdLst", "notesMasterIdLst", "handoutMasterIdLst", "sldIdLst",
          "sldSz", "notesSz", "defaultTextStyle", "embeddedFontLst", "photoAlbum",
          "custShowLst", "kinsoku", "modifyVerifier", "extLst",
        ].contains(node.name) ||
        (
          node.name == "extLst" &&
          !preserved_slide_extensions(self.main, node, properties=false)
        ) {
        return "Presentation extensions or sections require slide ordering support"
      }
    }
    let list = self.main.required(root.id, "sldIdLst", uri=presentation_uri)
    if self.main.children
      .get(list.id)
      .unwrap_or([])
      .any(node => node.uri != presentation_uri || node.name != "sldId") {
      return "Slide list extensions require ordering support"
    }
    for relation in self.relationships() {
      if relation.owner == self.main.part &&
        relation.kind == relationship_uri + "/presProps" {
        guard !relation.external else {
          return "External presentation properties are protected"
        }
        let properties = load_tree(self.opc, self.cache, relation.target)
        ignore(properties.root("presentationPr"))
        if properties.children
          .get(properties.document.nodes()[0].id)
          .unwrap_or([])
          .any(node => {
            node.uri != presentation_uri ||
            !["htmlPubPr", "webPr", "prnPr", "showPr", "clrMru", "extLst"].contains(
              node.name,
            ) ||
            (
              node.name == "extLst" &&
              !preserved_slide_extensions(properties, node, properties=true)
            )
          }) {
          return "Presentation properties extensions require slide ordering support"
        }
        if properties.document
          .nodes()
          .iter()
          .any(node => node.uri == presentation_uri && node.name == "sldRg") {
          return "Slide-index show ranges require ordering support"
        }
      }
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
/// Edits slide structure through the same bounded source history.
pub fn Session::edit_slides(
  self : Session,
  revision : Int,
  slide : String,
  change : SlideEdit,
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let index = self.index(slide)
  let reason = if change is MoveSlide(_) ||
    change is AddSlide ||
    change is CopySlide ||
    change is DeleteSlide {
    self.slide_order_reason()
  } else {
    self.slide_visibility_reason()
  }
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  match change {
    Transition(value) => return self.set_transition(index, value)
    Advance(value) => return self.set_advance(index, value)
    Animations(value) => return self.set_animations(index, value)
    CustomShows(value) => return self.set_custom_shows(value)
    AddComment(_, _, _, _, _) | UpdateComment(_, _) | RemoveComment(_) =>
      return self.edit_comments(index, change)
    AddSection(_)
    | RenameSection(_, _)
    | RemoveSection(_)
    | RemoveSections
    | DeleteSection(_)
    | MoveSection(_, _) => return self.edit_sections(index, change)
    Size(width, height) => return self.set_slide_size(width, height)
    Background(value) => return self.set_background(index, value)
    BackgroundImage(bytes, mode) =>
      return self.write_image(bytes, None, background=Some(index), mode~)
    BackgroundImageFormat(mode, crop, opacity) =>
      return self.set_background_image_format(index, mode, crop, opacity)
    BackgroundImageInsets(insets) =>
      return self.set_background_image_insets(index, insets)
    ThemeColor(slot, value) => return self.set_theme_color(slot, value)
    ThemeFont(kind, script, font) => {
      guard probe is Some(probe) else {
        @failure.reject(
          "missing-font", "Theme font editing requires a font probe and profile",
        )
      }
      return self.set_theme_font(kind, script, font, probe, profile)
    }
    ApplyLayout(id) => return self.apply_layout(index, id)
    ResetLayout =>
      return self.apply_layout(
        index,
        slide_layout(self.opc, self.slides[index].tree.part, self.parts).unwrap_or(
          "",
        ),
        reset=true,
      )
    Notes(text) => return self.set_notes(index, text)
    FirstSlideNumber(number) => {
      guard probe is Some(probe) else {
        @failure.reject(
          "missing-font", "Slide numbering requires a font probe and profile",
        )
      }
      return self.set_first_slide_number(number, probe, profile)
    }
    Footer(content, all) => {
      guard probe is Some(probe) else {
        @failure.reject(
          "missing-font", "Footer editing requires a font probe and profile",
        )
      }
      return self.set_footer(index, content, all, probe, profile)
    }
    AddSlide => return self.add_slide(index)
    CopySlide => return self.add_slide(index, copy=true)
    DeleteSlide => return self.delete_slides([self.slides[index].tree.part])
    MoveSlide(target) => {
      guard target >= 0 && target < self.slides.length() else {
        @failure.reject(
          "invalid-slide", "Slide position is outside the presentation",
        )
      }
      if target == index {
        return self.query()
      }
      let list = self.main.required(
        self.main.root("presentation").id,
        "sldIdLst",
        uri=presentation_uri,
      )
      let nodes = self.main.all(list.id, "sldId", uri=presentation_uri)
      let node = nodes[index]
      let offset = if target < index {
        nodes[target].start
      } else {
        nodes[target].end
      }
      let (document, edit) = self.main.document.edit_source([
        {
          node: list.id,
          offset: node.start - list.start,
          length: node.end - node.start,
          xml: "",
        },
        {
          node: list.id,
          offset: offset - list.start,
          length: 0,
          xml: self.main.document.source()[node.start:node.end].to_owned(),
        },
      ])
      let edits = [(self.main.part, edit)]
      let main = sync_slide_sections(
        self.main,
        Tree::new(self.main.part, document),
        edits,
        change,
        index,
      )
      let slides = self.ordered_slides(main, self.slides)
      self.commit_slides(main, slides, edits, self.selection)
    }
    HideSlide(hidden) => {
      let original = self.slides[index]
      if hidden == original.hidden {
        return self.query()
      }
      let changes = [
        attribute_change(
          { tree: original.tree, node: original.tree.root("sld"), },
          "show",
          if hidden {
            "0"
          } else {
            "1"
          },
        ),
      ]
      let (candidate, edit) = self.prepare(original, changes)
      self.commit(candidate, edit, self.selection)
    }
  }
  self.query()
}
