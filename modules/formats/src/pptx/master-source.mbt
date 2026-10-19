///|
fn Session::master_identity(
  self : Session,
) -> (String, String, String, Int64) raise @failure.Failure {
  let segments = self.main.part.split("/").map(v => v.to_owned()).to_array()
  ignore(segments.pop())
  let prefix = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  let ids : Map[String, Bool] = Map([])
  for node in self.main.document.nodes() {
    if node.uri == presentation_uri && node.name == "sldMasterId" {
      ids[number(node.attribute("id").unwrap_or(""), 2147483648, 4294967295)
      .to_int64()
      .to_string()] = true
    }
  }
  let links = self.relationships()
  let mut next = self.master_sequence
  while next <= 4294967295L {
    let master = prefix + "slideMasters/master\{next}.xml"
    let theme = prefix + "theme/master\{next}.xml"
    let paths = [
      master,
      theme,
      relationship_part(master),
      relationship_part(theme),
    ]
    let id = "odMaster\{next}"
    if !ids.contains(next.to_string()) &&
      !paths.any(path => {
        self.opc.names.contains(path.to_lower()) ||
        self.parts.keys().any(name => name.to_lower() == path.to_lower())
      }) &&
      !links.any(link => link.id == id) {
      return (master, theme, id, next)
    }
    next += 1
  }
  @failure.reject("limit-exceeded", "Master identities exhausted")
}

///|
fn Session::master_creation_sources(
  self : Session,
  source : String,
  copy : Bool,
) -> Array[Tree] raise @failure.Failure {
  let choice = self.source_choice(source)
  guard !copy || choice.kind == "master" else {
    @failure.reject("invalid-slide", "Select a master source to copy")
  }
  guard self.master_choices().length() < 256 else {
    @failure.reject("limit-exceeded", "Slide master catalog exceeds budget")
  }
  let layouts = self.layout_choices()
  let owned = layouts.filter(layout => layout.master.part == choice.master)
  guard layouts.length() + (if copy { owned.length() } else { 1 }) <= 256 else {
    @failure.reject("limit-exceeded", "Slide layout catalog exceeds budget")
  }
  if !copy {
    return []
  }
  let master = choice.tree
  guard master.document
    .nodes()
    .filter(node => node.uri == presentation_uri && node.name == "sldLayoutId")
    .length() ==
    owned.length() else {
    @failure.reject("protected-content", "Unknown layout catalog identity")
  }
  let theme = relation(self.opc, master.part, "theme", parts=self.parts).unwrap()
  let sources = [
    master,
    ..owned.map(layout => layout.tree),
    load_tree(self.opc, self.cache, theme, parts=self.parts),
  ]
  let links = self.relationships()
  let mut units = 0
  for tree in sources {
    check_source_copy(tree, links)
    units += tree.document.source().length()
    let path = relationship_part(tree.part)
    if self.parts.contains(path) || self.opc.names.contains(path.to_lower()) {
      units += self.part_document(path).source().length()
    }
    guard units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Copied master sources exceed history budget",
      )
    }
  }
  for link in links {
    if link.owner == master.part &&
      link.kind == relationship_uri + "/slideLayout" {
      guard !link.external &&
        owned.any(layout => layout.tree.part == link.target) else {
        @failure.reject(
          "protected-content", "Unlisted layout ownership requires copying support",
        )
      }
    }
  }
  sources
}

///|
fn Session::validate_created_sources(
  self : Session,
  main : Tree,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
) -> Unit raise @failure.Failure {
  let staged = { ..self, main, parts, source_view: None, }
  ignore(staged.source_choices())
  for part, document in created {
    if !["sldMaster", "sldLayout"].contains(document.nodes()[0].name) {
      continue
    }
    let owner = read_slide(
      self.opc,
      main,
      self.cache,
      Tree::new(part, document),
      index=self.index(self.last_slide),
      parts~,
      date_time=self.date_time,
    )
    guard owner.objects.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Source view objects exceed 4096")
    }
    // The final commit validates the shared OPC graph once after checking every new owner.
    staged.validate_slides(
      main,
      [..self.slides, owner],
      parts~,
      check_package=false,
    )
  }
}
