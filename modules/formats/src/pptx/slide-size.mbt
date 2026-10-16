///|
fn presentation_size(main : Tree) -> (Double, Double) raise @failure.Failure {
  let size = main.required(
    main.root("presentation").id,
    "sldSz",
    uri=presentation_uri,
  )
  (
    number(size.attribute("cx").unwrap_or("0"), 12700, 182880000) / 12700,
    number(size.attribute("cy").unwrap_or("0"), 12700, 182880000) / 12700,
  )
}

///|
fn Session::size_trees(self : Session) -> Array[Tree] raise @failure.Failure {
  check_size_guides(self.main)
  let trees = self.slides.map(slide => slide.tree)
  let seen : Map[String, Bool] = Map([])
  for tree in trees {
    seen[tree.part] = true
  }
  for rel in self.relationships() {
    if rel.owner == self.main.part &&
      rel.kind == relationship_uri + "/presProps" {
      guard !rel.external else {
        @failure.reject(
          "protected-content", "External presentation properties are protected",
        )
      }
      check_size_guides(
        load_tree(self.opc, self.cache, rel.target, parts=self.parts),
      )
    }
    if [relationship_uri + "/slideMaster", relationship_uri + "/slideLayout"].contains(
        rel.kind,
      ) {
      guard !rel.external else {
        @failure.reject(
          "protected-content", "External slide design is protected",
        )
      }
      if !seen.contains(rel.target) {
        let tree = load_tree(self.opc, self.cache, rel.target, parts=self.parts)
        ignore(
          tree.root(
            if rel.kind == relationship_uri + "/slideMaster" {
              "sldMaster"
            } else {
              "sldLayout"
            },
          ),
        )
        trees.push(tree)
        seen[rel.target] = true
      }
    }
  }
  trees
}

///|
fn check_size_guides(tree : Tree) -> Unit raise @failure.Failure {
  for node in tree.document.nodes() {
    if ["sldGuideLst", "guideLst"].contains(node.name) &&
      !tree.children.get(node.id).unwrap_or([]).is_empty() {
      @failure.reject(
        "protected-content",
        "Slide guides require size support",
        part=tree.part,
      )
    }
  }
}

///|
fn size_changes(
  tree : Tree,
  sx : Double,
  sy : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  check_size_guides(tree)
  let shapes = shape_tree(tree)
  for node in tree.document.nodes() {
    if node.parent == shapes.id ||
      (
        tree.nodes.get(node.parent) is Some(parent) &&
        parent.uri == presentation_uri &&
        parent.name == "grpSp"
      ) {
      guard node.uri == presentation_uri &&
        ["nvGrpSpPr", "grpSpPr", "sp", "pic", "cxnSp", "grpSp"].contains(
          node.name,
        ) else {
        @failure.reject(
          "protected-content",
          "This slide object requires size support",
          part=tree.part,
        )
      }
    }
    if node.uri != drawing_uri || node.name != "xfrm" {
      continue
    }
    let parent = tree.nodes[node.parent]
    if parent.uri != presentation_uri ||
      !["spPr", "grpSpPr"].contains(parent.name) {
      continue
    }
    for child in tree.children.get(node.id).unwrap_or([]) {
      guard child.uri == drawing_uri &&
        ["off", "ext", "chOff", "chExt"].contains(child.name) &&
        tree.children.get(child.id).unwrap_or([]).is_empty() else {
        @failure.reject(
          "protected-content",
          "Unknown transform coordinates are protected",
          part=tree.part,
        )
      }
      let offset = ["off", "chOff"].contains(child.name)
      for
        (key, scale) in [
          (if offset { "x" } else { "cx" }, sx),
          (if offset { "y" } else { "cy" }, sy),
        ] {
        let original = number(
          child.attribute(key).unwrap_or("0"),
          if offset {
            -182880000
          } else {
            0
          },
          182880000,
        )
        let value = (original * scale).round()
        guard value >= (if offset { -182880000 } else { 0 }) &&
          value <= 182880000 else {
          @failure.reject(
            "invalid-size",
            "Resized object coordinates exceed bounds",
            part=tree.part,
          )
        }
        if value != original {
          changes.push(
            attribute_change(
              { tree, node: child, },
              key,
              value.to_int64().to_string(),
            ),
          )
        }
      }
    }
  }
  changes
}

///|
fn Session::slide_size_reason(self : Session) -> String {
  let reason = self.slide_visibility_reason()
  if !reason.is_empty() {
    return reason
  }
  try {
    for tree in self.size_trees() {
      ignore(size_changes(tree, 1, 1))
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::set_slide_size(
  self : Session,
  width : Double,
  height : Double,
) -> Json raise @failure.Failure {
  for value in [width, height] {
    guard !value.is_nan() && !value.is_inf() && value >= 1 && value <= 14400 else {
      @failure.reject(
        "invalid-size", "Slide dimensions must be between 1 and 14400 points",
      )
    }
  }
  let width = (width * 12700).round() / 12700
  let height = (height * 12700).round() / 12700
  if width == self.width && height == self.height {
    return self.query()
  }
  let size = self.main.required(
    self.main.root("presentation").id,
    "sldSz",
    uri=presentation_uri,
  )
  let size_ref : Ref = { tree: self.main, node: size, }
  let (document, edit) = self.main.document.edit_source([
    attribute_change(
      size_ref,
      "cx",
      (width * 12700).round().to_int64().to_string(),
    ),
    attribute_change(
      size_ref,
      "cy",
      (height * 12700).round().to_int64().to_string(),
    ),
    attribute_change(size_ref, "type", "custom"),
  ])
  let main = Tree::new(self.main.part, document)
  let edits = [(main.part, edit)]
  let parts = self.parts.copy()
  let documents : Map[String, @xml.Document] = Map([])
  // ONLYOFFICE scales group child coordinates as well as each local transform.
  for tree in self.size_trees() {
    let changes = size_changes(tree, width / self.width, height / self.height)
    if changes.is_empty() {
      continue
    }
    let (document, edit) = tree.document.edit_source(changes)
    documents[tree.part] = document
    edits.push((tree.part, edit))
    if !self.slides.any(slide => slide.tree.part == tree.part) {
      parts[tree.part] = document
    }
  }
  let slides = self.slides.map(slide => {
    read_slide(
      self.opc,
      main,
      self.cache,
      Tree::new(
        slide.tree.part,
        documents.get(slide.tree.part).unwrap_or(slide.tree.document),
      ),
      parts~,
    )
  })
  self.commit_slides(main, slides, edits, self.selection, parts~)
  self.query()
}
