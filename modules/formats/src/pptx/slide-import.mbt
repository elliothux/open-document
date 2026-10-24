///|
fn imported_slide_paths(
  source : Session,
  indices : Array[Int],
) -> Array[String] raise @failure.Failure {
  guard indices.length() <= 256 && Set(indices).length() == indices.length() else {
    @failure.reject(
      "invalid-slide", "Imported slide indices must be unique and bounded",
    )
  }
  indices.map(index => {
    guard index >= 0 && index < source.slides.length() else {
      @failure.reject("invalid-slide", "Imported slide index is out of range")
    }
    source.slides[index].tree.part
  })
}

///|
/// Inspects source pages and selected resources without retaining another presentation session.
pub fn Session::import_slide_info(
  self : Session,
  revision : Int,
  bytes : Bytes,
  indices : Array[Int],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard bytes.length() <= 33554432 else {
    @failure.reject("limit-exceeded", "Imported file exceeds32MiB")
  }
  let date_time = self.date_time.map(d => d.value)
  let source = Session::open(bytes, self.budget, date_time?)
  defer source.close()
  let paths = imported_slide_paths(source, indices)
  let resources = source.slide_import_parts(paths)
  let images : Array[String] = []
  let media : Array[Json] = []
  let names = resources.media.keys().to_array()
  names.sort()
  for name in names {
    let kind = resources.kinds[name]
    if kind == "image" {
      images.push(@base64.encode(resources.media[name]))
    } else if ["audio", "video", "media"].contains(kind) {
      let content_type = source.opc.content_type(name).unwrap_or("")
      media.push({
        "kind": if content_type.has_prefix("audio/") {
          "audio"
        } else {
          "video"
        },
        "contentType": content_type,
        "bytes": @base64.encode(resources.media[name]),
      })
    }
  }
  {
    "slides": source.slides.mapi((index, slide) => {
      let value : Json = {
        "index": index,
        "title": slide.objects
        .iter()
        .find_first(o => !o.text().is_empty())
        .map(o => o.text())
        .unwrap_or(""),
        "hidden": slide.hidden,
      }
      value
    }),
    "fonts": slide_font_keys(
      source.slides.filter(slide => paths.contains(slide.tree.part)),
    ),
    "images": images,
    "media": media,
  }
}

///|
/// Imports selected source pages after a listed page with their native design and owned resources.
pub fn Session::import_slides(
  self : Session,
  revision : Int,
  bytes : Bytes,
  indices : Array[Int],
  after : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  guard bytes.length() <= 33554432 else {
    @failure.reject("limit-exceeded", "Imported file exceeds32MiB")
  }
  let reason = self.slide_order_reason()
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let at = self.index(after)
  guard !indices.is_empty() && indices.length() <= 256 - self.slides.length() else {
    @failure.reject(
      "limit-exceeded", "Imported pages require space in the256-slide budget",
    )
  }
  let date_time = self.date_time.map(d => d.value)
  let source = Session::open(bytes, self.budget, date_time?)
  defer source.close()
  let paths = imported_slide_paths(source, indices)
  let resources = source.slide_import_parts(paths)
  let prefix = self.import_prefix()
  let remap : Map[String, String] = Map([])
  for name in resources.documents.keys() {
    guard prefix.length() + name.length() <= 256 else {
      @failure.reject("limit-exceeded", "Imported part path exceeds256 units")
    }
    remap[name] = prefix + name
  }
  for name in resources.media.keys() {
    guard prefix.length() + name.length() <= 256 else {
      @failure.reject("limit-exceeded", "Imported part path exceeds256 units")
    }
    remap[name] = prefix + name
  }
  let design_ids : Map[String, Int64] = Map([])
  let reserved_ids : Set[Int64] = Set([])
  for tree in [self.main, ..self.source_choices().map(choice => choice.tree)] {
    for node in tree.document.nodes() {
      if node.uri == presentation_uri &&
        ["sldMasterId", "sldLayoutId"].contains(node.name) {
        reserved_ids.add(
          number(node.attribute("id").unwrap_or("0"), 2147483648, 4294967295).to_int64(),
        )
      }
    }
  }
  let mut design_sequence = self.master_sequence.max(self.layout_sequence)
  let ordered = resources.kinds.keys().to_array()
  ordered.sort()
  for name in ordered {
    if ["slideMaster", "slideLayout"].contains(resources.kinds[name]) {
      while reserved_ids.contains(design_sequence) {
        design_sequence += 1L
      }
      guard design_sequence <= 4294967295L else {
        @failure.reject(
          "limit-exceeded", "Imported design identities exhausted",
        )
      }
      design_ids[name] = design_sequence
      reserved_ids.add(design_sequence)
      design_sequence += 1L
    }
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  let created : Map[String, @xml.Document] = Map([])
  let created_media : Map[String, Bytes] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let object_ids = self.reserved_object_identities()
  let mut next = self.object_sequence
  let styles : Map[String, String] = Map([])
  let links = source.relationships()
  let relation_remap = remap.copy()
  for link in links {
    if !link.external &&
      remap.get(
        source.opc.names.get(link.target.to_lower()).unwrap_or(link.target),
      )
      is Some(target) {
      relation_remap[link.target] = target
    }
  }
  for name in ordered {
    let kind = resources.kinds[name]
    let target = remap[name]
    if resources.media.get(name) is Some(bytes) {
      media[target] = bytes
      created_media[target] = bytes
      continue
    }
    let tree = Tree::new(name, resources.documents[name])
    let (document, issued) = if kind == "chart" {
      (tree.document, next)
    } else {
      copy_slide_objects(tree, target, object_ids, next, self.budget)
    }
    next = issued
    let (document, issued) = self.import_table_styles(
      source, document, styles, next, parts, created, edits,
    )
    next = issued
    let current = Tree::new(target, document)
    let changes : Array[@xml.SourceChange] = []
    if kind == "slideMaster" {
      for node in document.nodes() {
        if node.uri == presentation_uri && node.name == "sldLayoutId" {
          let id = node.attribute("id", uri=relationship_uri).unwrap_or("")
          let link = links
            .iter()
            .find_first(link => link.owner == name && link.id == id)
            .unwrap()
          let target = source.opc.names
            .get(link.target.to_lower())
            .unwrap_or(link.target)
          changes.push(
            attribute_change(
              { tree: current, node, },
              "id",
              design_ids[target].to_string(),
            ),
          )
        }
      }
    }
    let document = if changes.is_empty() {
      document
    } else {
      document.edit_source(changes).0
    }
    let document = if (
        source.width != self.width || source.height != self.height
      ) &&
      ["slide", "slideLayout", "slideMaster"].contains(kind) {
      let changes = size_changes(
        Tree::new(target, document),
        self.width / source.width,
        self.height / source.height,
      )
      if changes.is_empty() {
        document
      } else {
        document.edit_source(changes).0
      }
    } else {
      document
    }
    parts[target] = document
    if kind != "slide" {
      created[target] = document
    }
    if source.copy_slide_relationships(
        name,
        target,
        relation_remap,
        import_relationship_kinds(kind),
        links~,
      )
      is Some(document) {
      parts[relationship_part(target)] = document
      if kind != "slide" {
        created[relationship_part(target)] = document
      }
    }
  }
  let mut main = self.main
  let mut slide_sequence = self.slide_sequence
  let used = Set(
    self.main.document
    .nodes()
    .filter(n => n.uri == presentation_uri && n.name == "sldId")
    .map(n => source_identity(n.attribute("id").unwrap_or(""))),
  )
  let target_links = self.relationships()
  let reserved_links = Set(
    target_links
    .iter()
    .filter(link => link.owner == self.main.part)
    .map(link => link.id)
    .to_array(),
  )
  let presentation_links = StringBuilder()
  let masters = StringBuilder()
  let notes = StringBuilder()
  for name in ordered {
    let kind = resources.kinds[name]
    if kind != "slideMaster" && kind != "notesMaster" {
      continue
    }
    let link = for sequence in 0..<=self.budget.entries {
      let id = "odImportDesign\{sequence}"
      if !reserved_links.contains(id) {
        reserved_links.add(id)
        break id
      }
    } nobreak {
      @failure.reject(
        "limit-exceeded", "Imported design relationship identities exhausted",
      )
    }
    presentation_links.write_string(
      "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='\{link}' Type='\{relationship_uri}/\{kind}' Target='/\{xml_attribute(remap[name])}'/>",
    )
    if kind == "slideMaster" {
      masters.write_string(
        "<p:sldMasterId xmlns:p='\{presentation_uri}' xmlns:r='\{relationship_uri}' id='\{design_ids[name]}' r:id='\{link}'/>",
      )
    } else {
      notes.write_string(
        "<p:notesMasterId xmlns:p='\{presentation_uri}' xmlns:r='\{relationship_uri}' r:id='\{link}'/>",
      )
    }
  }
  for
    (name, markup) in [
      ("sldMasterIdLst", masters.to_string()),
      ("notesMasterIdLst", notes.to_string()),
    ] {
    if markup.is_empty() {
      continue
    }
    let (document, edit) = import_main_entries(main, name, markup)
    main = Tree::new(main.part, document)
    edits.push((main.part, edit))
  }
  let added : Array[(Slide, @xml.Document)] = []
  for offset, name in paths {
    while used.contains(slide_sequence.to_string()) ||
          target_links.any(link => {
            link.owner == self.main.part &&
            link.id == "odSlide\{slide_sequence}"
          }) {
      slide_sequence += 1L
    }
    guard slide_sequence < 2147483647L else {
      @failure.reject("limit-exceeded", "Imported slide identities exhausted")
    }
    let list = main.required(
      main.root("presentation").id,
      "sldIdLst",
      uri=presentation_uri,
    )
    let anchor = main.all(list.id, "sldId", uri=presentation_uri)[at + offset]
    let (document, edit) = main.document.edit_source([
      {
        node: list.id,
        offset: anchor.end - list.start,
        length: 0,
        xml: "<p:sldId xmlns:p='\{presentation_uri}' xmlns:r='\{relationship_uri}' id='\{slide_sequence}' r:id='odSlide\{slide_sequence}'/>",
      },
    ])
    edits.push((main.part, edit))
    main = sync_slide_sections(
      main,
      Tree::new(main.part, document),
      edits,
      AddSlide,
      at + offset,
    )
    presentation_links.write_string(
      "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='odSlide\{slide_sequence}' Type='\{relationship_uri}/slide' Target='/\{xml_attribute(remap[name])}'/>",
    )
    used.add(slide_sequence.to_string())
    slide_sequence += 1L
  }
  let overrides = StringBuilder()
  for name, target in remap {
    let content_type = source.opc
      .content_type(name)
      .unwrap_or_else(() => {
        @failure.reject(
          "protected-content",
          "Imported part has no content type",
          part=name,
        )
      })
    overrides.write_string(
      "<Override xmlns='http://schemas.openxmlformats.org/package/2006/content-types' PartName='/\{xml_attribute(target)}' ContentType='\{xml_attribute(content_type)}'/>",
    )
  }
  for
    (path, markup) in [
      (relationship_part(main.part), presentation_links.to_string()),
      ("[Content_Types].xml", overrides.to_string()),
    ] {
    let original = parts
      .get(path)
      .unwrap_or_else(() => self.part_document(path))
    let (document, edit) = original.edit_source([
      insertion(original.nodes()[0], markup),
    ])
    parts[path] = document
    edits.push((path, edit))
  }
  let slides = self.slides.copy()
  for offset, name in paths {
    let target = remap[name]
    let slide = read_slide(
      self.opc,
      main,
      self.cache,
      Tree::new(target, parts[target]),
      index=at + offset + 1,
      parts~,
      date_time=self.date_time,
    )
    guard slide.read_only.is_empty() &&
      slide.objects.all(o => o.diagnostic.is_empty()) else {
      @failure.reject(
        "protected-content",
        "Imported page requires supported layout",
        part=name,
      )
    }
    ignore(source.read_animations(source.slides[indices[offset]]))
    for key in slide_font_keys([slide]) {
      guard profile.get(key) is Some(font) else {
        @failure.reject("missing-font", "Missing imported font profile: " + key)
      }
      ignore(probe.font_index(font))
    }
    for object in slide.objects {
      if object.table is Some(_) {
        ignore(object.paint_table(probe, profile))
      } else if object.chart is Some(chart) {
        let geometry = object.geometry.unwrap()
        ignore(chart.paint(geometry.width, geometry.height, probe, profile))
      } else if object.kind != "group" && object.geometry is Some(geometry) {
        ignore(fit_text(object, geometry, probe, profile))
      }
    }
    added.push((slide, parts[relationship_part(target)]))
    parts.remove(target)
    slides.insert(at + offset + 1, slide)
  }
  let staged = { ..self, main, parts, media, slides, }
  guard staged.master_choices().length() <= 256 &&
    staged.layout_choices().length() <= 256 else {
    @failure.reject(
      "limit-exceeded", "Imported design catalog exceeds256 owners",
    )
  }
  staged.validate_created_sources(main, parts, created)
  self.commit_slides(
    main,
    slides,
    edits,
    {
      slide: remap[paths[0]],
      object: "",
      objects: [],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    parts~,
    created=added,
    created_parts=created,
    media~,
    created_media~,
  )
  self.slide_sequence = slide_sequence
  self.master_sequence = design_sequence
  self.layout_sequence = design_sequence
  self.object_sequence = next
  self.query()
}
