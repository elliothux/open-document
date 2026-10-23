///|
fn Session::clipboard_object_resource(
  self : Session,
  kind : String,
  target : String,
  resources : Map[String, Json],
) -> String raise @failure.Failure {
  let key = kind + "\n" + target
  if resources.get(key) is Some({ "id": String(id), .. }) {
    return id
  }
  guard resources.length() < 256 else {
    @failure.reject("limit-exceeded", "Object clipboard exceeds 256 resources")
  }
  let id = "odClip" + resources.length().to_string()
  let value = if kind == "image" {
    let bytes = self.image_bytes(target)
    ignore(@image.type_info(bytes))
    guard bytes.length() <= 2097152 else {
      @failure.reject("limit-exceeded", "Object clipboard image exceeds 2MiB")
    }
    @base64.encode(bytes)
  } else {
    check_external_hyperlink(target)
    target
  }
  resources[key] = { "id": id, "kind": kind, "value": value }
  guard resources
    .values()
    .fold(init=0, (sum, r) => {
      sum +
      (match r {
        { "value": String(value), .. } => value.length()
        _ => 0
      })
    }) <=
    2796204 else {
    @failure.reject(
      "limit-exceeded", "Object clipboard resources exceed budget",
    )
  }
  id
}

///|
fn Session::clipboard_object_links(
  self : Session,
  tree : Tree,
  resources : Map[String, Json],
) -> @xml.Document raise @failure.Failure {
  let links = self.relationships()
  let changes : Array[@xml.SourceChange] = []
  let image_ids = resources
    .values()
    .filter_map(r => {
      match r {
        { "id": String(id), "kind": String("image"), .. } => Some(id)
        _ => None
      }
    })
    .to_array()
  for node in tree.document.nodes() {
    if node.uri == drawing_uri && node.name == "hlinkMouseOver" {
      @failure.reject(
        "protected-content", "Hover object links require clipboard support",
      )
    }
    if node.uri == drawing_uri && node.name == "hlinkClick" {
      check_clipboard_link_metadata(node)
      let value = self
        .read_hyperlink_at(
          Some({ tree, node: tree.nodes[node.parent], }),
          tree.part,
          links,
        )
        .unwrap()
      guard value.0 == "external" || value.0 == "action" else {
        @failure.reject(
          "protected-content", "Object slide links require copying their destination",
        )
      }
      let id = if value.0 == "external" {
        self.clipboard_object_resource("external", value.1, resources)
      } else {
        ""
      }
      if node.attributes
        .iter()
        .find_first(a => a.uri == relationship_uri && a.name == "id")
        is Some(attr) {
        changes.push({
          node: node.id,
          offset: attr.start - node.start,
          length: attr.end - attr.start,
          xml: id,
        })
      }
    }
    for attr in node.attributes {
      if attr.uri != relationship_uri {
        continue
      }
      guard (
          node.uri == drawing_uri &&
          node.name == "blip" &&
          attr.name == "embed" &&
          image_ids.contains(attr.value)
        ) ||
        (
          node.uri == drawing_uri &&
          node.name == "hlinkClick" &&
          attr.name == "id"
        ) ||
        (
          chart_frame_reference(tree, node) &&
          attr.name == "id" &&
          resources
          .values()
          .any(resource => {
            resource is { "id": String(id), "kind": String("chart"), .. } &&
            id == attr.value
          })
        ) else {
        @failure.reject(
          "protected-content", "Unsupported object clipboard relationship",
        )
      }
    }
  }
  if changes.is_empty() {
    tree.document
  } else {
    tree.document.edit_source(changes).0
  }
}

///|
/// Captures supported selected native objects with resolved formatting and only their resources.
fn Session::copy_object_fragment(
  self : Session,
  revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let selected = self.transform_objects(action="duplicate")
  let original = self.current()
  guard !selected.is_empty() &&
    selected.all(o => {
      o.parent.is_empty() && o.source.tree.part == original.tree.part
    }) else {
    @failure.reject(
      "protected-content", "Object clipboard requires local top-level selection",
    )
  }
  let ranges = selected.map(o => (o.source.node.start, o.source.node.end))
  let objects = original.objects.filter(o => {
    ranges.any(range => {
      range.0 <= o.source.node.start && o.source.node.end <= range.1
    })
  })
  for object in objects {
    check_clipboard_object(object)
  }
  let positioned = original.tree.document.edit_source(
      selected.map(o => transform_changes(o, o.geometry.unwrap())).flatten(),
    ).0
  let positioned = read_slide(
    self.opc,
    self.main,
    self.cache,
    Tree::new(original.tree.part, positioned),
    index=self.source_index(original.tree.part),
    parts=self.parts,
    date_time=self.date_time,
  )
  let resources : Map[String, Json] = Map([])
  let changes = []
  for old in objects {
    let object = positioned.object(old.id)
    if object.table is Some(_) {
      changes.append(self.clipboard_table_style(object, resources))
      continue
    }
    if object.chart is Some(_) {
      changes.push(self.clipboard_chart(object, resources))
      continue
    }
    let image = object.image.map(key => {
      self.clipboard_object_resource("image", key, resources)
    })
    changes.append(clipboard_object_style(object, image))
  }
  let document = if changes.is_empty() {
    positioned.tree.document
  } else {
    positioned.tree.document.edit_source(changes).0
  }
  let markup = StringBuilder()
  markup.write_string(
    "<p:spTree xmlns:p='\{presentation_uri}' xmlns:a='\{drawing_uri}' xmlns:r='\{relationship_uri}'>",
  )
  for object in original.objects {
    if self.selection.objects.contains(object.id) {
      markup.write_string(
        original.tree.standalone_markup(document, object.source.node.id),
      )
    }
  }
  markup.write_string("</p:spTree>")
  guard markup.to_string().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Copied object XML exceeds 1Mi units")
  }
  let tree = Tree::new(
    original.tree.part,
    @xml.Document::parse(
      @utf8.encode(markup.to_string()),
      original.tree.part,
      self.budget.xml_depth,
      self.budget.entry_bytes,
    ),
  )
  check_slide_copy_markup(tree)
  let source = self.clipboard_object_links(tree, resources).source()
  let text = selected
    .map(o => {
      if o.accessible_text().is_empty() {
        o.name
      } else {
        o.accessible_text()
      }
    })
    .join("\n")
  guard text.length() <= 32767 else {
    @failure.reject(
      "limit-exceeded", "Copied object text exceeds clipboard budget",
    )
  }
  let fragment : Json = {
    "source": source,
    "resources": resources.values().to_array(),
    "selection": self.selection.objects.map(id => {
      id.split("#").last().unwrap().to_owned()
    }),
    "active": self.selection.object.split("#").last().unwrap().to_owned(),
  }
  let fragment = fragment.stringify()
  guard fragment.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Object clipboard exceeds 4Mi units")
  }
  ignore(read_object_fragment(fragment, self.budget))
  { "text": text, "fragment": fragment, "reason": "" }
}

///|
/// Returns validated local images for platform decoding before the paste commits.
pub fn Session::object_fragment_images(
  self : Session,
  revision : Int,
  value : String,
) -> Array[String] raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  read_object_fragment(value, self.budget).resources.filter_map(resource => {
    resource.image.map(bytes => @base64.encode(bytes))
  })
}
