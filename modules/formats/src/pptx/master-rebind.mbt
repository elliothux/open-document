///|
fn layout_match_name(tree : Tree) -> String raise @failure.Failure {
  let root = tree.root("sldLayout")
  let matching_name = root.attribute("matchingName").unwrap_or("")
  let name = if matching_name.is_empty() {
    tree
    .required(root.id, "cSld", uri=presentation_uri)
    .attribute("name")
    .unwrap_or("")
  } else {
    matching_name
  }
  guard name.length() <= 1024 else {
    @failure.reject("limit-exceeded", "Layout matching name exceeds budget")
  }
  name
}

///|
fn replacement_master_layout(
  original : Tree,
  choices : Array[LayoutChoice],
) -> LayoutChoice raise @failure.Failure {
  guard !choices.is_empty() else {
    @failure.reject("invalid-layout", "Replacement master has no layouts")
  }
  if original.root("sldLayout").attribute("type") is Some(kind) &&
    choices
    .iter()
    .find_first(choice => {
      choice.tree.root("sldLayout").attribute("type") == Some(kind)
    })
    is Some(choice) {
    return choice
  }
  let name = layout_match_name(original)
  if !name.is_empty() &&
    choices.iter().find_first(choice => layout_match_name(choice.tree) == name)
    is Some(choice) {
    return choice
  }
  choices
  .iter()
  .find_first(choice => {
    choice.tree.root("sldLayout").attribute("type") != Some("title")
  })
  .unwrap_or(choices[0])
}

///|
fn Session::orphan_placeholder_changes(
  self : Session,
  slide : Slide,
  choice : LayoutChoice,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  for object in slide.objects {
    if object.source.tree.part != slide.tree.part || !object.parent.is_empty() {
      continue
    }
    if placeholder(object.source) is Some(ph) &&
      matching(choice.tree, ph, false) is None &&
      matching(choice.master, ph, true) is None {
      let updates = placeholder_geometry_changes(object)
      if updates.is_empty() {
        continue
      }
      let reason = self.object_edit_reason(object, "transform")
      guard reason.is_empty() else {
        @failure.reject("protected-content", reason)
      }
      changes.append(updates)
    }
  }
  changes
}

///|
fn Session::rebind_master_slides(
  self : Session,
  part : String,
  paths : Array[String],
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  probe : @layout.TextProbe?,
  profile : Map[String, String],
) -> Array[Slide] raise @failure.Failure {
  let replacement = self
    .master_choices()
    .iter()
    .find_first(pair => pair.0.part != part)
    .unwrap().0.part
  let choices = self
    .layout_choices()
    .filter(choice => choice.master.part == replacement)
  let slides = self.slides.mapi((index, slide) => {
    let owner = slide.tree.part
    let original_layout = slide_layout(self.opc, owner, self.parts).unwrap()
    if !paths.contains(original_layout) {
      return slide
    }
    let choice = replacement_master_layout(
      load_tree(self.opc, self.cache, original_layout, parts=self.parts),
      choices,
    )
    self.change_layout_relationship(owner, choice.tree.part, parts, edits)
    let changes = self.orphan_placeholder_changes(slide, choice)
    let tree = if changes.is_empty() {
      slide.tree
    } else {
      let (document, edit) = slide.tree.document.edit_source(changes)
      edits.push((owner, edit))
      Tree::new(owner, document)
    }
    let candidate = read_slide(
      self.opc,
      self.main,
      self.cache,
      tree,
      index~,
      parts~,
      date_time=self.date_time,
    )
    let previous = slide_font_keys([slide])
    for key in slide_font_keys([candidate]) {
      if previous.contains(key) {
        continue
      }
      guard probe is Some(probe) &&
        @layout.font_profile_identity(profile, key) is Some(identity) else {
        @failure.reject(
          "missing-font",
          "Missing replacement master font profile: " + key,
        )
      }
      ignore(probe.font_index(identity))
    }
    candidate
  })
  self.reflow_source(slides, parts, edits, probe, profile)
}
