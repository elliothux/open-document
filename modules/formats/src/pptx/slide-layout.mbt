///|
priv struct LayoutChoice {
  tree : Tree
  master : Tree
  name : String
  master_name : String
}

///|
fn Session::layout_choices(
  self : Session,
) -> Array[LayoutChoice] raise @failure.Failure {
  let choices : Array[LayoutChoice] = []
  let links = self.relationships()
  let masters = self.main.required(
    self.main.root("presentation").id,
    "sldMasterIdLst",
    uri=presentation_uri,
  )
  let seen : Map[String, Bool] = Map([])
  let mut units = 0
  let listed = self.main.all(masters.id, "sldMasterId", uri=presentation_uri)
  guard listed.length() <= 256 else {
    @failure.reject("limit-exceeded", "Slide master catalog exceeds budget")
  }
  for item in listed {
    let id = item.attribute("id", uri=relationship_uri).unwrap_or("")
    let link = links
      .iter()
      .find_first(link => link.owner == self.main.part && link.id == id)
    guard link is Some(link) &&
      !link.external &&
      link.kind == relationship_uri + "/slideMaster" else {
      @failure.reject("malformed-pptx", "Invalid listed slide master")
    }
    let master = load_tree(self.opc, self.cache, link.target, parts=self.parts)
    let root = master.root("sldMaster")
    let master_name = master
      .required(root.id, "cSld", uri=presentation_uri)
      .attribute("name")
      .unwrap_or("")
    if master.one(root.id, "sldLayoutIdLst", uri=presentation_uri) is Some(list) {
      for item in master.all(list.id, "sldLayoutId", uri=presentation_uri) {
        let id = item.attribute("id", uri=relationship_uri).unwrap_or("")
        let link = links
          .iter()
          .find_first(link => link.owner == master.part && link.id == id)
        guard link is Some(link) &&
          !link.external &&
          link.kind == relationship_uri + "/slideLayout" &&
          !seen.contains(link.target) else {
          @failure.reject(
            "malformed-pptx", "Invalid or repeated listed slide layout",
          )
        }
        let tree = load_tree(
          self.opc,
          self.cache,
          link.target,
          parts=self.parts,
        )
        let root = tree.root("sldLayout")
        guard relation(self.opc, tree.part, "slideMaster") == Some(master.part) else {
          @failure.reject(
            "malformed-pptx", "Slide layout belongs to a different master",
          )
        }
        let name = tree
          .required(root.id, "cSld", uri=presentation_uri)
          .attribute("name")
          .unwrap_or(root.attribute("matchingName").unwrap_or(""))
        units += tree.part.length() +
          master.part.length() +
          name.length() +
          master_name.length()
        guard choices.length() < 256 &&
          units <= 1048576 &&
          name.length() <= 1024 &&
          master_name.length() <= 1024 else {
          @failure.reject(
            "limit-exceeded", "Slide layout catalog exceeds budget",
          )
        }
        seen[tree.part] = true
        choices.push({ tree, master, name, master_name, })
      }
    }
  }
  choices
}

///|
fn Session::layout_query(self : Session, slide : Slide) -> Json {
  let current = slide_layout(self.opc, slide.tree.part, self.parts).unwrap_or(
    "",
  ) catch {
    @failure.Failure(..) => ""
  }
  try {
    let choices = self.layout_choices()
    guard choices.any(choice => choice.tree.part == current) else {
      @failure.reject(
        "protected-content", "Current slide layout is not listed by the presentation masters",
      )
    }
    {
      "current": current,
      "choices": choices.map(choice => {
        let value : Json = {
          "id": choice.tree.part,
          "name": choice.name,
          "master": choice.master.part,
          "masterName": choice.master_name,
        }
        value
      }),
      "reason": self.slide_visibility_reason(),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "current": current, "choices": [], "reason": message }
  }
}

///|
fn layout_transform_reset(
  source : Ref,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let changes : Array[@xml.SourceChange] = []
  if source.child("spPr", uri=presentation_uri).bind(item => item.child("xfrm"))
    is Some(transform) {
    let tree = source.tree
    let node = transform.node
    let markup = tree.document.source()[node.start:node.end]
    guard !markup.contains("<!--") &&
      !markup.contains("<?") &&
      node.text.trim().is_empty() &&
      node.attributes.all(a => {
        a.uri.is_empty() && ["rot", "flipH", "flipV"].contains(a.name)
      }) &&
      tree.children
      .get(node.id)
      .unwrap_or([])
      .all(child => {
        child.uri == drawing_uri &&
        ["off", "ext"].contains(child.name) &&
        child.text.trim().is_empty() &&
        tree.children.get(child.id).unwrap_or([]).is_empty() &&
        child.attributes.all(a => {
          a.uri.is_empty() &&
          (if child.name == "off" { ["x", "y"] } else { ["cx", "cy"] }).contains(
            a.name,
          )
        })
      }) else {
      @failure.reject(
        "protected-content", "Unknown placeholder transform markup is protected",
      )
    }
    let parent = tree.nodes[node.parent]
    changes.push({
      node: parent.id,
      offset: node.start - parent.start,
      length: node.end - node.start,
      xml: "",
    })
  }
  changes
}

///|
fn layout_placeholder_markup(
  source : Ref,
  id : String,
  content~ : String,
) -> String raise @failure.Failure {
  guard source.node.name == "sp" &&
    placeholder(source) is Some(ph) &&
    [
      "title", "ctrTitle", "body", "subTitle", "obj", "dt", "ftr", "hdr", "sldNum",
    ].contains(ph.0) else {
    @failure.reject(
      "protected-content", "This layout placeholder requires content or field insertion support",
    )
  }
  let nv = source.child("nvSpPr", uri=presentation_uri).unwrap()
  let identity = nv.child("cNvPr", uri=presentation_uri).unwrap()
  let app = nv.child("nvPr", uri=presentation_uri).unwrap()
  let placeholder = app.child("ph", uri=presentation_uri).unwrap()
  guard placeholder.node.text.trim().is_empty() &&
    source.tree.children.get(placeholder.node.id).unwrap_or([]).is_empty() &&
    placeholder.node.attributes.all(a => {
      a.uri.is_empty() &&
      ["type", "idx", "sz", "orient", "hasCustomPrompt"].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "Unknown layout placeholder markup is protected",
    )
  }
  let properties = nv.child("cNvSpPr", uri=presentation_uri)
  if properties is Some(properties) {
    guard properties.node.attributes.all(a => {
        a.uri.is_empty() && a.name == "txBox"
      }) &&
      source.tree.children
      .get(properties.node.id)
      .unwrap_or([])
      .all(node => {
        node.uri == drawing_uri &&
        node.name == "spLocks" &&
        node.text.trim().is_empty() &&
        source.tree.children.get(node.id).unwrap_or([]).is_empty() &&
        node.attributes.all(a => {
          a.uri.is_empty() &&
          [
            "noGrp", "noSelect", "noRot", "noChangeAspect", "noMove", "noResize",
            "noEditPoints", "noAdjustHandles", "noChangeArrowheads", "noChangeShapeType",
            "noTextEdit",
          ].contains(a.name)
        })
      }) else {
      @failure.reject(
        "protected-content", "Unknown layout placeholder locks are protected",
      )
    }
  }
  let props = properties
    .map(item => {
      source.tree.standalone_markup(source.tree.document, item.node.id)
    })
    .unwrap_or("<p:cNvSpPr/>")
  let ph_xml = source.tree.standalone_markup(
    source.tree.document,
    placeholder.node.id,
  )
  let name = xml_attribute(
    identity.node.attribute("name").unwrap_or("Placeholder"),
  )
  "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"\{id}\" name=\"\{name}\"/>\{props}<p:nvPr>\{ph_xml}</p:nvPr></p:nvSpPr><p:spPr/>\{content}</p:sp>"
}

///|
fn layout_empty_placeholder(object : Object) -> Bool {
  guard object.kind == "shape" &&
    object.text().is_empty() &&
    object.text_reason.is_empty() &&
    !object.has_fill() &&
    object.stroke.is_empty() else {
    return false
  }
  let source = object.source
  let markup = source.tree.document.source()[source.node.start:source.node.end]
  guard !markup.contains("<!--") && !markup.contains("<?") else { return false }
  source.tree.document
  .nodes()
  .all(node => {
    if node.start < source.node.start || node.end > source.node.end {
      return true
    }
    [presentation_uri, drawing_uri].contains(node.uri) &&
    !["hlinkClick", "hlinkHover", "extLst", "fld"].contains(node.name) &&
    node.attributes.all(a => a.uri.is_empty()) &&
    (
      node.name != "cNvPr" ||
      ["descr", "title"].all(key => node.attribute(key).unwrap_or("").is_empty())
    )
  })
}

///|
fn Session::apply_layout(
  self : Session,
  index : Int,
  id : String,
  reset~ : Bool = false,
) -> Json raise @failure.Failure {
  let original = self.slides[index]
  let current = slide_layout(self.opc, original.tree.part, self.parts)
  if current == Some(id) && !reset {
    return self.query()
  }
  let choice = self
    .layout_choices()
    .iter()
    .find_first(choice => choice.tree.part == id)
  guard choice is Some(choice) else {
    @failure.reject("invalid-layout", "Unknown presentation slide layout")
  }
  let tree = original.tree
  let changes : Array[@xml.SourceChange] = []
  let used : Map[Int, String] = Map([])
  let affected : Map[String, Bool] = Map([])
  for node in choice.tree.document.nodes() {
    let source : Ref = { tree: choice.tree, node, }
    if placeholder(source) is Some(ph) {
      guard node.parent == shape_tree(choice.tree).id &&
        matching(choice.tree, ph, false).map(item => item.node.id) ==
        Some(node.id) else {
        @failure.reject(
          "invalid-layout", "Ambiguous or grouped target layout placeholders",
        )
      }
    }
  }
  for object in original.objects {
    if object.source.tree.part != tree.part ||
      object.source.node.parent != shape_tree(tree).id {
      continue
    }
    if placeholder(object.source) is Some(ph) {
      guard object.kind == "shape" || object.kind == "image" else {
        @failure.reject(
          "protected-content", "Unsupported local placeholder object",
        )
      }
      let matched = matching(choice.tree, ph, false)
      if matched is Some(target) && !used.contains(target.node.id) {
        guard object.read_only.is_empty() else {
          @failure.reject("protected-content", object.read_only)
        }
        used[target.node.id] = object.id
        changes.append(layout_transform_reset(object.source))
        affected[object.id] = true
      } else {
        guard layout_empty_placeholder(object) else {
          @failure.reject(
            "invalid-layout",
            "Target layout has no unambiguous position for placeholder: " +
            object.name,
          )
        }
        let reason = self.object_edit_reason(object, "delete")
        guard reason.is_empty() else {
          @failure.reject("protected-content", reason)
        }
        let node = object.source.node
        let parent = tree.nodes[node.parent]
        changes.push({
          node: parent.id,
          offset: node.start - parent.start,
          length: node.end - node.start,
          xml: "",
        })
      }
    }
  }
  let reserved = self.reserved_object_identities()
  let mut next = self.object_sequence
  let inserted = StringBuilder()
  let mut units = 0
  for node in choice.tree.children.get(shape_tree(choice.tree).id).unwrap_or([]) {
    let source : Ref = { tree: choice.tree, node, }
    if placeholder(source) is None ||
      used.contains(node.id) ||
      !layout_placeholder_enabled(source, choice.tree, choice.master) {
      continue
    }
    while reserved.contains(next.to_string()) {
      next += 1
    }
    guard next <= 4294967295L else {
      @failure.reject("limit-exceeded", "Object identities exhausted")
    }
    let issued = next.to_string()
    reserved[issued] = true
    next += 1
    // Ordinary placeholders start empty; header/footer placeholders keep their content.
    let content = if layout_special_placeholder(source) {
      let (content, after) = layout_placeholder_content(
        source,
        reserved,
        next,
        self.budget,
      )
      next = after
      content
    } else {
      "<p:txBody><a:bodyPr/><a:lstStyle/><a:p/></p:txBody>"
    }
    let markup = layout_placeholder_markup(source, issued, content~)
    units += markup.length()
    guard units <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Inserted layout placeholders exceed budget",
      )
    }
    inserted.write_string(markup)
    affected[tree.part + "#" + issued] = true
  }
  if !inserted.to_string().is_empty() {
    changes.push(object_insertion(tree, inserted.to_string()))
  }
  if changes.is_empty() && current == Some(id) {
    return self.query()
  }
  let parts = self.parts.copy()
  let edits : Array[(String, @xml.Edit)] = []
  if current != Some(id) {
    let path = relationship_part(tree.part)
    let relations = parts.get(path).unwrap_or_else(() => self.opc.xml(path))
    let links = relations
      .nodes()
      .filter(node => {
        node.attribute("Type") == Some(relationship_uri + "/slideLayout")
      })
    guard links is [link] else {
      @failure.reject("malformed-pptx", "Invalid slide layout relationship")
    }
    let relation_tree = Tree::new(path, relations)
    let (relations, edit) = relations.edit_source([
      attribute_change(
        { tree: relation_tree, node: link, },
        "Target",
        xml_attribute("/" + id),
      ),
    ])
    parts[path] = relations
    edits.push((path, edit))
  }
  let document = if changes.is_empty() {
    tree.document
  } else {
    let (document, edit) = tree.document.edit_source(changes)
    edits.push((tree.part, edit))
    document
  }
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(tree.part, document),
    index=self.index(tree.part),
    date_time=self.date_time,
    parts~,
  )
  guard candidate.read_only.is_empty() &&
    candidate.diagnostics.all(message => original.diagnostics.contains(message)) else {
    @failure.reject(
      "protected-content", "Target layout introduces unsupported visible content or unresolved geometry",
    )
  }
  for object in candidate.objects {
    if affected.contains(object.id) {
      guard object.geometry is Some(_) &&
        object.diagnostic.is_empty() &&
        (
          object.text_reason.is_empty() ||
          calculated_field_reason(object.text_reason)
        ) else {
        @failure.reject(
          "protected-content", "Target placeholder cannot be displayed and edited safely",
        )
      }
      if original.objects.iter().find_first(before => before.id == object.id)
        is Some(before) &&
        before.geometry is Some(initial) &&
        object.geometry is Some(updated) &&
        initial.rotation != updated.rotation {
        let reason = self.object_edit_reason(before, "rotate")
        guard reason.is_empty() else {
          @failure.reject("protected-content", reason)
        }
      }
    }
  }
  let mut after = self.selection
  if after.slide == tree.part {
    let objects = after.objects.filter(id => {
      candidate.objects.any(object => object.id == id)
    })
    if !objects.contains(after.object) {
      after = {
        ..after,
        objects,
        object: objects.last().unwrap_or(""),
        mode: "object",
        anchor: 0,
        focus: 0,
      }
    } else {
      after = { ..after, objects, }
    }
  }
  let slides = self.slides.copy()
  slides[index] = candidate
  self.commit_slides(self.main, slides, edits, after, parts~)
  self.object_sequence = next
  self.query()
}
