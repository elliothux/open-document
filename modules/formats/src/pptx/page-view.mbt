///|
fn Session::master_choices(
  self : Session,
) -> Array[(Tree, String)] raise @failure.Failure {
  let links = self.relationships()
  let list = self.main.required(
    self.main.root("presentation").id,
    "sldMasterIdLst",
    uri=presentation_uri,
  )
  let items = self.main.all(list.id, "sldMasterId", uri=presentation_uri)
  guard items.length() <= 256 else {
    @failure.reject("limit-exceeded", "Slide master catalog exceeds budget")
  }
  let seen : Map[String, Bool] = Map([])
  items.map(item => {
    let id = item.attribute("id", uri=relationship_uri).unwrap_or("")
    let link = links
      .iter()
      .find_first(link => link.owner == self.main.part && link.id == id)
    guard link is Some(link) &&
      !link.external &&
      link.kind == relationship_uri + "/slideMaster" &&
      !seen.contains(link.target) else {
      @failure.reject(
        "malformed-pptx", "Invalid or repeated listed slide master",
      )
    }
    seen[link.target] = true
    let tree = load_tree(self.opc, self.cache, link.target, parts=self.parts)
    let name = tree
      .required(tree.root("sldMaster").id, "cSld", uri=presentation_uri)
      .attribute("name")
      .unwrap_or("")
    guard name.length() <= 1024 else {
      @failure.reject("limit-exceeded", "Slide master name exceeds budget")
    }
    (tree, name)
  })
}

///|
priv struct SourceChoice {
  tree : Tree
  name : String
  kind : String
  master : String
}

///|
fn Session::source_choices(
  self : Session,
) -> Array[SourceChoice] raise @failure.Failure {
  let choices : Array[SourceChoice] = []
  for (tree, name) in self.master_choices() {
    choices.push({ tree, name, kind: "master", master: tree.part, })
  }
  for item in self.layout_choices() {
    choices.push({
      tree: item.tree,
      name: item.name,
      kind: "layout",
      master: item.master.part,
    })
  }
  let units = choices
    .iter()
    .fold(init=0, (sum, item) => {
      sum + item.tree.part.length() + item.name.length() + item.master.length()
    })
  guard units <= 1048576 else {
    @failure.reject("limit-exceeded", "Source catalog exceeds budget")
  }
  choices
}

///|
fn Session::source_index(
  self : Session,
  part : String,
) -> Int raise @failure.Failure {
  self.slides
  .search_by(slide => slide.tree.part == part)
  .unwrap_or_else(() => self.index(self.last_slide))
}

///|
fn Session::source_slide(
  self : Session,
  part : String,
) -> Slide raise @failure.Failure {
  self.check()
  if self.slides.iter().find_first(slide => slide.tree.part == part)
    is Some(slide) {
    return slide
  }
  if self.source_view is Some(slide) &&
    slide.tree.part == part &&
    slide.date_time == self.date_time.map(time => time.value) {
    return slide
  }
  let tree = self
    .source_choices()
    .iter()
    .find_first(item => item.tree.part == part)
    .map(item => item.tree)
    .unwrap_or_error(
      @failure.Failure(
        code="invalid-slide",
        part~,
        offset=-1,
        message="Unknown presentation source identity",
      ),
    )
  let slide = read_slide(
    self.opc,
    self.main,
    self.cache,
    tree,
    index=self.source_index(part),
    parts=self.parts,
    date_time=self.date_time,
  )
  self.source_view = Some(slide)
  slide
}

///|
fn Session::edit_view_query(self : Session, current : Slide) -> Json {
  let kind = match current.tree.document.nodes()[0].name {
    "sldMaster" => "master"
    "sldLayout" => "layout"
    _ => "slide"
  }
  try {
    let choices = self
      .source_choices()
      .map(item => {
        let choice : Json = {
          "id": item.tree.part,
          "name": item.name,
          "kind": item.kind,
          "master": item.master,
        }
        choice
      })
    {
      "kind": kind,
      "slide": self.last_slide,
      "choices": choices,
      "reason": "",
      "operations": self.source_operations(current),
      "textStyles": self.master_text_styles(current),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "kind": kind,
        "slide": self.last_slide,
        "choices": [],
        "textStyles": { "items": [], "reason": message },
        "reason": message,
        "operations": {
          "rename": message,
          "addLayout": message,
          "copyLayout": message,
          "deleteLayout": message,
          "deleteMaster": message,
          "addMaster": message,
          "copyMaster": message,
        },
      }
  }
}

///|
fn Session::source_inheritance_changed(
  self : Session,
  edits : Array[(String, @xml.Edit)],
  parts : Map[String, @xml.Document],
) -> Bool raise @failure.Failure {
  edits.any(entry => {
    parts
    .get(entry.0)
    .map(document => {
      let root = document.nodes()[0]
      (root.uri == drawing_uri && root.name == "theme") ||
      (
        root.uri == presentation_uri &&
        ["sldMaster", "sldLayout"].contains(root.name)
      )
    })
    .unwrap_or(false)
  }) ||
  self.slides.any(slide => {
    edits.any(entry => entry.0 == relationship_part(slide.tree.part)) &&
    slide_layout(self.opc, slide.tree.part, self.parts) !=
    slide_layout(self.opc, slide.tree.part, parts)
  })
}

///|
fn Session::commit_page(
  self : Session,
  slide : Slide,
  edits : Array[(String, @xml.Edit)],
  after : Selection,
  parts~ : Map[String, @xml.Document] = self.parts,
  media~ : Map[String, Bytes] = self.media,
  created_parts~ : Map[String, @xml.Document] = Map([]),
  created_media~ : Map[String, Bytes] = Map([]),
  probe? : @layout.TextProbe,
  profile~ : Map[String, String] = Map([]),
) -> Unit raise @failure.Failure {
  let mut slides = self.slides.copy()
  let parts = parts.copy()
  let edits = edits.copy()
  if slides.search_by(item => item.tree.part == slide.tree.part) is Some(index) {
    slides[index] = slide
  } else {
    let (slide, normalized) = self.normalize_groups(
      slide,
      self.main,
      self.source_index(slide.tree.part),
      parts,
    )
    if normalized is Some(edit) {
      edits.push((slide.tree.part, edit))
    }
    let (slide, normalized) = self.normalize_connectors(
      slide,
      self.main,
      self.source_index(slide.tree.part),
      parts,
    )
    if normalized is Some(edit) {
      edits.push((slide.tree.part, edit))
    }
    parts[slide.tree.part] = slide.tree.document
    if slide.tree.document.nodes()[0].name == "sldMaster" {
      self.reflow_master_layouts(
        slide.tree.part,
        parts,
        edits,
        probe,
        profile,
        media,
      )
    }
    slides = self.reflow_source(slides, parts, edits, probe, profile)
    // The edited source can be unused, so it must also pass object and resource limits.
    let owner = read_slide(
      self.opc,
      self.main,
      self.cache,
      Tree::new(slide.tree.part, parts[slide.tree.part]),
      index=self.source_index(slide.tree.part),
      parts~,
      date_time=self.date_time,
    )
    let visible = slides.copy()
    guard owner.objects.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Source view objects exceed 4096")
    }
    visible.push(owner)
    self.validate_slides(self.main, visible, parts~, media~)
  }
  self.commit_slides(
    self.main,
    slides,
    edits,
    after,
    parts~,
    media~,
    created_parts~,
    created_media~,
  )
}
