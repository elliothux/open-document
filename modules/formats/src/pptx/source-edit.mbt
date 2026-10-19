///|
fn Session::source_choice(
  self : Session,
  part : String,
) -> SourceChoice raise @failure.Failure {
  self
  .source_choices()
  .iter()
  .find_first(choice => choice.tree.part == part)
  .unwrap_or_error(
    @failure.Failure(
      code="invalid-slide",
      part~,
      offset=-1,
      message="Select a listed master or layout source",
    ),
  )
}

///|
fn Session::layout_choice(
  self : Session,
  part : String,
) -> LayoutChoice raise @failure.Failure {
  self
  .layout_choices()
  .iter()
  .find_first(choice => choice.tree.part == part)
  .unwrap_or_error(
    @failure.Failure(
      code="invalid-slide",
      part~,
      offset=-1,
      message="Select a listed layout source",
    ),
  )
}

///|
fn Session::check_layout_copy(
  self : Session,
  tree : Tree,
) -> Unit raise @failure.Failure {
  guard tree.document.source().length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Copied layout exceeds history budget")
  }
  check_slide_copy_markup(tree)
  for link in self.relationships() {
    if link.owner != tree.part {
      continue
    }
    guard ["slideMaster", "image", "hyperlink", "slide"].any(kind => {
        link.kind == relationship_uri + "/" + kind
      }) &&
      (!link.external || link.kind == relationship_uri + "/hyperlink") else {
      @failure.reject(
        "protected-content", "Layout resource ownership requires copying support",
      )
    }
  }
}

///|
fn Session::layout_deletion(
  self : Session,
  choice : LayoutChoice,
) -> (@xml.Node, String) raise @failure.Failure {
  let links = self
    .relationships()
    .filter(link => !link.external && link.target == choice.tree.part)
  guard links is [link] &&
    link.owner == choice.master.part &&
    link.kind == relationship_uri + "/slideLayout" else {
    @failure.reject(
      "protected-content", "Layout is referenced by a page or another part",
    )
  }
  let tree = choice.master
  let list = tree.required(
    tree.root("sldMaster").id,
    "sldLayoutIdLst",
    uri=presentation_uri,
  )
  let nodes = tree.document
    .nodes()
    .filter(node => {
      node.attributes.any(a => a.uri == relationship_uri && a.value == link.id)
    })
  guard nodes is [node] &&
    node.parent == list.id &&
    node.uri == presentation_uri &&
    node.name == "sldLayoutId" else {
    @failure.reject(
      "protected-content", "Unknown reference to the layout relationship",
    )
  }
  (node, link.id)
}

///|
fn Session::source_operations(self : Session, current : Slide) -> Json {
  let base = self.modification_reason()
  let root = current.tree.document.nodes()[0].name
  let owner = ["sldMaster", "sldLayout"].contains(root)
  let rename = if !base.is_empty() {
    base
  } else if owner {
    ""
  } else {
    "Select a master or layout source"
  }
  let add = try {
    if !rename.is_empty() {
      rename
    } else if self.layout_choices().length() >= 256 {
      "Slide layout catalog exceeds budget"
    } else {
      ""
    }
  } catch {
    @failure.Failure(message~, ..) => message
  }
  let copy = try {
    if !add.is_empty() {
      add
    } else if root != "sldLayout" {
      "Select a layout source"
    } else {
      self.check_layout_copy(current.tree)
      ""
    }
  } catch {
    @failure.Failure(message~, ..) => message
  }
  let remove = try {
    if !base.is_empty() {
      base
    } else if root != "sldLayout" {
      "Select a layout source"
    } else {
      ignore(self.layout_deletion(self.layout_choice(current.tree.part)))
      ""
    }
  } catch {
    @failure.Failure(message~, ..) => message
  }
  {
    "rename": rename,
    "addLayout": add,
    "copyLayout": copy,
    "deleteLayout": remove,
  }
}

///|
fn Session::rename_source(
  self : Session,
  part : String,
  name : String,
) -> Json raise @failure.Failure {
  guard name.length() <= 1024 && @xml.valid_text(name) else {
    @failure.reject("invalid-operation", "Source name is invalid or excessive")
  }
  let choice = self.source_choice(part)
  if choice.name == name {
    return self.query()
  }
  let original = self.source_slide(part)
  let tree = original.tree
  let node = tree.required(
    tree.document.nodes()[0].id,
    "cSld",
    uri=presentation_uri,
  )
  let (candidate, edit) = self.prepare(original, [
    attribute_change({ tree, node, }, "name", xml_attribute(name)),
  ])
  self.commit(candidate, edit, self.selection)
  self.query()
}

///|
fn Session::validate_source_target(
  self : Session,
  part : String,
  parts : Map[String, @xml.Document],
  removed~ : Array[String] = self.removed,
) -> Unit raise @failure.Failure {
  let staged = { ..self, parts, removed, source_view: None, }
  ignore(staged.source_choices())
  staged.validate(staged.source_slide(part))
}

///|
fn Session::edit_source(
  self : Session,
  part : String,
  change : SlideEdit,
) -> Json raise @failure.Failure {
  ignore(self.source_slide(part))
  let reason = self.modification_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  match change {
    AddLayout => self.add_layout(part)
    CopyLayout => self.add_layout(part, copy=true)
    DeleteLayout => self.delete_layout(part)
    SourceName(name) => self.rename_source(part, name)
    Background(value) => self.set_background(part, value)
    BackgroundImage(bytes, mode) =>
      self.write_image(bytes, None, background=Some(part), mode~)
    BackgroundImageFormat(mode, crop, opacity) =>
      self.set_background_image_format(part, mode, crop, opacity)
    BackgroundImageInsets(insets) =>
      self.set_background_image_insets(part, insets)
    _ =>
      @failure.reject("invalid-slide", "This operation requires a real slide")
  }
}
