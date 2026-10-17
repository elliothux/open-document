///|
fn check_external_hyperlink(target : String) -> Unit raise @failure.Failure {
  guard target.length() <= 2048 else {
    @failure.reject(
      "invalid-operation", "Hyperlink address exceeds 2048 UTF-16 units",
    )
  }
  let lower = target.to_lower()
  let prefix = if lower.has_prefix("https://") {
    8
  } else if lower.has_prefix("http://") {
    7
  } else if lower.has_prefix("mailto:") {
    7
  } else {
    0
  }
  guard prefix > 0 &&
    target.length() > prefix &&
    @xml.valid_text(target) &&
    target
    .iter()
    .all(c => {
      !c.is_whitespace() && c.to_int() > 32 && c.to_int() != 127 && c != '\\'
    }) else {
    @failure.reject(
      "invalid-operation", "Hyperlink requires a bounded HTTP, HTTPS or mailto address",
    )
  }
}

///|
fn hyperlink_properties(object : Object) -> Ref raise @failure.Failure {
  let kind = match object.kind {
    "image" => "nvPicPr"
    "group" => "nvGrpSpPr"
    _ => "nvSpPr"
  }
  object.source
  .child(kind, uri=presentation_uri)
  .bind(nv => nv.child("cNvPr", uri=presentation_uri))
  .unwrap_or_error(
    @failure.Failure(
      code="protected-content",
      part=object.source.tree.part,
      offset=-1,
      message="Missing object hyperlink properties",
    ),
  )
}

///|
fn hyperlink_node(properties : Ref) -> @xml.Node? raise @failure.Failure {
  let node = properties.child("hlinkClick")
  guard node is Some(source) else { return None }
  let raw = source.tree.document.source()[source.node.start:source.node.end]
  guard source.node.attributes.all(a => {
      (a.uri == relationship_uri && a.name == "id") ||
      (
        a.uri.is_empty() &&
        ["action", "tooltip", "tgtFrame", "history", "highlightClick", "endSnd"].contains(
          a.name,
        )
      )
    }) &&
    source.tree.children.get(source.node.id).unwrap_or([]).is_empty() &&
    source.node.text.is_empty() &&
    !raw.contains("<!--") &&
    !raw.contains("<?") else {
    @failure.reject(
      "protected-content", "Extended hyperlink actions are protected",
    )
  }
  for name in ["history", "highlightClick", "endSnd"] {
    ignore(flag(source.node, name))
  }
  Some(source.node)
}

///|
fn Session::read_hyperlink(
  self : Session,
  object : Object,
  links : ReadOnlyArray[@opc.Relationship],
) -> (String, String)? raise @failure.Failure {
  guard hyperlink_node(hyperlink_properties(object)) is Some(node) else {
    return None
  }
  let id = node.attribute("id", uri=relationship_uri).unwrap_or("")
  guard links
    .iter()
    .find_first(link => link.owner == object.source.tree.part && link.id == id)
    is Some(link) else {
    @failure.reject("protected-content", "Unresolved hyperlink relationship")
  }
  let action = node.attribute("action").unwrap_or("")
  if link.external &&
    link.kind == relationship_uri + "/hyperlink" &&
    action.is_empty() {
    check_external_hyperlink(link.target)
    Some(("external", link.target))
  } else if !link.external &&
    [relationship_uri + "/slide", relationship_uri + "/hyperlink"].contains(
      link.kind,
    ) &&
    action == "ppaction://hlinksldjump" &&
    self.slides.any(slide => slide.tree.part == link.target) {
    Some(("slide", link.target))
  } else {
    @failure.reject(
      "protected-content", "Unsupported hyperlink target or action",
    )
  }
}

///|
fn Session::hyperlink_query(
  self : Session,
  object : Object,
  links : ReadOnlyArray[@opc.Relationship],
) -> Json {
  try {
    let value = self.read_hyperlink(object, links)
    {
      "value": value
      .map(pair => {
        let result : Json = { "kind": pair.0, "target": pair.1 }
        result
      })
      .unwrap_or(Json::null()),
      "reason": self.object_edit_reason(object, "hyperlink"),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "value": Json::null(), "reason": Json(message) }
  }
}

///|
fn Session::set_object_hyperlink(
  self : Session,
  kind : String,
  target : String,
) -> Json raise @failure.Failure {
  guard self.selection.mode == "object" && self.selection.objects is [id] else {
    @failure.reject(
      "invalid-operation", "Hyperlink editing requires one selected object",
    )
  }
  guard ["none", "external", "slide"].contains(kind) &&
    (kind != "none" || target.is_empty()) else {
    @failure.reject("invalid-operation", "Invalid hyperlink kind")
  }
  if kind == "external" {
    check_external_hyperlink(target)
  }
  if kind == "slide" {
    ignore(self.index(target))
  }
  let original = self.current()
  let object = original.object(id)
  let reason = self.object_edit_reason(object, "hyperlink")
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let links = self.relationships()
  let value = self.read_hyperlink(object, links)
  let next = if kind == "none" { None } else { Some((kind, target)) }
  if value == next {
    return self.query()
  }
  let properties = hyperlink_properties(object)
  let node = hyperlink_node(properties)
  let parts = self.parts.copy()
  let created : Map[String, @xml.Document] = Map([])
  let edits : Array[(String, @xml.Edit)] = []
  let markup = if kind == "none" {
    ""
  } else {
    let external = kind == "external"
    let relation_kind = relationship_uri +
      (if external { "/hyperlink" } else { "/slide" })
    let existing = links
      .iter()
      .find_first(link => {
        link.owner == original.tree.part &&
        link.kind == relation_kind &&
        link.external == external &&
        link.target == target
      })
    let relation = if existing is Some(link) {
      link.id
    } else {
      let mut sequence = 1
      while links
            .iter()
            .any(link => {
              link.owner == original.tree.part && link.id == "odLink\{sequence}"
            }) {
        sequence += 1
        guard sequence <= 16384 else {
          @failure.reject("limit-exceeded", "Hyperlink identities exhausted")
        }
      }
      let id = "odLink\{sequence}"
      let path = relationship_part(original.tree.part)
      let present = self.parts.contains(path) ||
        self.opc.names.contains(path.to_lower())
      let source = if present {
        self.part_document(path)
      } else {
        @xml.Document::parse(
          b"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"/>",
          path,
          self.budget.xml_depth,
          self.budget.entry_bytes,
        )
      }
      let mode = if external { " TargetMode=\"External\"" } else { "" }
      let destination = if external { target } else { "/" + target }
      let (document, edit) = source.edit_source([
        insertion(
          source.nodes()[0],
          "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{id}\" Type=\"\{relation_kind}\" Target=\"\{xml_attribute(destination)}\"\{mode}/>",
        ),
      ])
      parts[path] = document
      if present {
        edits.push((path, edit))
      } else {
        created[path] = document
      }
      id
    }
    let metadata = StringBuilder()
    if node is Some(node) {
      for attribute in node.attributes {
        if attribute.uri.is_empty() && attribute.name != "action" {
          metadata.write_string(
            " \{attribute.name}=\"\{xml_attribute(attribute.value)}\"",
          )
        }
      }
    }
    let action = if external {
      ""
    } else {
      " action=\"ppaction://hlinksldjump\""
    }
    "<a:hlinkClick xmlns:a=\"\{drawing_uri}\" xmlns:r=\"\{relationship_uri}\" r:id=\"\{relation}\"\{action}\{metadata.to_string()}/>"
  }
  let (document, edit) = original.tree.document.edit_source([
    paint_child_change(properties, node, markup, ["hlinkMouseOver", "extLst"]),
  ])
  let candidate = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, document),
    parts~,
  )
  edits.push((original.tree.part, edit))
  let slides = self.slides.copy()
  slides[self.index(original.tree.part)] = candidate
  self.commit_slides(
    self.main,
    slides,
    edits,
    self.selection,
    parts~,
    created_parts=created,
  )
  self.query()
}
