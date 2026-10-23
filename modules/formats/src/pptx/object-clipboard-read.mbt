///|
priv struct ObjectFragment {
  tree : Tree
  selection : Array[String]
  active : String
  resources : Array[ObjectClipboardResource]
}

///|
priv struct ObjectClipboardResource {
  id : String
  target : String
  image : Bytes?
  style : Ref?
  chart : @layout.ChartData?
}

///|
fn clipboard_object_identity(
  tree : Tree,
  node : @xml.Node,
) -> String raise @failure.Failure {
  let nv = match node.name {
    "sp" => "nvSpPr"
    "cxnSp" => "nvCxnSpPr"
    "pic" => "nvPicPr"
    "grpSp" => "nvGrpSpPr"
    "graphicFrame" => "nvGraphicFramePr"
    _ =>
      @failure.reject("protected-content", "Unsupported portable object kind")
  }
  let nv = tree.required(node.id, nv, uri=presentation_uri)
  source_identity(
    tree
    .required(nv.id, "cNvPr", uri=presentation_uri)
    .attribute("id")
    .unwrap_or(""),
  )
}

///|
fn read_object_fragment(
  value : String,
  budget : @archive.Budget,
) -> ObjectFragment raise @failure.Failure {
  guard value.length() <= 4194304 else {
    @failure.reject("limit-exceeded", "Object clipboard exceeds 4Mi units")
  }
  let data = @json.parse(value) catch {
    _ => @failure.reject("invalid-operation", "Invalid object clipboard JSON")
  }
  guard data is Object(fields) &&
    fields.length() == 4 &&
    data
    is {
      "source": String(source),
      "selection": Array(selected),
      "active": String(active),
      "resources": Array(assets),
      ..
    } &&
    source.length() <= 1048576 &&
    !selected.is_empty() &&
    selected.length() <= 256 &&
    assets.length() <= 256 else {
    @failure.reject("invalid-operation", "Invalid object clipboard fields")
  }
  let tree = Tree::new(
    "clipboard",
    @xml.Document::parse(
      @utf8.encode(source),
      "clipboard",
      budget.xml_depth,
      budget.entry_bytes.min(4194304),
    ),
  )
  let root = tree.root("spTree")
  let objects = tree.children.get(root.id).unwrap_or([])
  guard root.attributes.is_empty() &&
    root.text.trim().is_empty() &&
    objects.length() == selected.length() else {
    @failure.reject("protected-content", "Invalid portable object tree")
  }
  check_slide_copy_markup(tree)
  let roots = objects.map(node => clipboard_object_identity(tree, node))
  let selection = selected.map(value => {
    match value {
      String(id) => source_identity(id)
      _ =>
        @failure.reject("invalid-operation", "Invalid copied object selection")
    }
  })
  guard selection.all(id => roots.contains(id)) &&
    Set(selection).length() == selection.length() &&
    selection.contains(active) else {
    @failure.reject(
      "invalid-operation", "Copied selection does not match object roots",
    )
  }
  let resources : Array[ObjectClipboardResource] = []
  let ids : Set[String] = Set([])
  let mut units = 0
  let mut image_bytes = 0
  let mut pixels = 0L
  for asset in assets {
    guard asset is Object(fields) &&
      fields.length() == 3 &&
      asset
      is { "id": String(id), "kind": String(kind), "value": String(value), .. } &&
      !id.is_empty() &&
      id.length() <= 64 &&
      id
      .iter()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' ||
        c == '-'
      }) &&
      !ids.contains(id) &&
      ["image", "external", "tableStyle", "chart"].contains(kind) else {
      @failure.reject("invalid-operation", "Invalid portable object resource")
    }
    ids.add(id)
    units += value.length()
    guard units <= 2796204 else {
      @failure.reject(
        "limit-exceeded", "Object clipboard resources exceed budget",
      )
    }
    if kind == "external" {
      check_external_hyperlink(value)
    }
    let image = if kind == "image" {
      let bytes = @base64.decode(value) catch {
        _ => @failure.reject("invalid-image", "Invalid clipboard image bytes")
      }
      image_bytes += bytes.length()
      let (_, _, width, height) = @image.type_info(bytes)
      pixels += width.to_int64() * height.to_int64() * 4
      guard image_bytes <= 2097152 && pixels <= 16777216L else {
        @failure.reject(
          "limit-exceeded", "Clipboard image resources exceed budget",
        )
      }
      Some(bytes)
    } else {
      None
    }
    let style = if kind == "tableStyle" {
      let document = @xml.Document::parse(
        @utf8.encode(value),
        "clipboard-style",
        budget.xml_depth,
        budget.entry_bytes.min(4194304),
      )
      let tree = Tree::new("clipboard-style", document)
      let root = tree.root("tblStyle", uri=drawing_uri)
      guard root.attribute("styleId") == Some(id) &&
        !value.contains("<!--") &&
        !value.contains("<?") &&
        document
        .nodes()
        .all(node => {
          node.uri == drawing_uri &&
          !["schemeClr", "sysClr", "fontRef", "fillRef", "lnRef"].contains(
            node.name,
          ) &&
          node.attributes.all(a => {
            a.uri.is_empty() &&
            !(a.name == "typeface" && a.value.has_prefix("+"))
          })
        }) else {
        @failure.reject(
          "protected-content", "Table clipboard styles must be independent",
        )
      }
      let style = { tree, node: root, }
      ignore(
        table_style_parts(
          {
            part: None,
            default_id: id,
            styles: Map([(id, style)]),
            reason: "",
          },
          id,
        ),
      )
      Some(style)
    } else {
      None
    }
    let chart = if kind == "chart" {
      guard value.length() <= 1048576 else {
        @failure.reject("limit-exceeded", "Portable chart exceeds 1Mi units")
      }
      let document = @xml.Document::parse(
        @utf8.encode(value),
        "clipboard-chart",
        budget.xml_depth,
        budget.entry_bytes.min(4194304),
      )
      guard !value.contains("<!--") &&
        !value[document.nodes()[0].start:].contains("<?") else {
        @failure.reject("protected-content", "Invalid portable chart source")
      }
      let (data, link) = @chart.read_data("clipboard-chart", document)
      guard link == "workbook" else {
        @failure.reject(
          "protected-content", "Unresolved portable chart workbook",
        )
      }
      Some(data)
    } else {
      None
    }
    resources.push({
      id,
      target: if kind == "external" {
        value
      } else {
        ""
      },
      image,
      style,
      chart,
    })
  }
  let used : Set[String] = Set([])
  for node in tree.document.nodes() {
    if node.uri == drawing_uri && node.name == "tbl" {
      guard tree.one(node.id, "tblPr").bind(p => tree.one(p.id, "tableStyleId"))
        is Some(_) else {
        @failure.reject(
          "protected-content", "Portable tables require an independent style",
        )
      }
    }
    if node.uri == drawing_uri && node.name == "tableStyleId" {
      let id = node.text.trim().to_owned()
      guard resources.any(resource => {
        resource.id == id && resource.style is Some(_)
      }) else {
        @failure.reject("protected-content", "Unresolved portable table style")
      }
      used.add(id)
    }
    guard node.uri != presentation_uri || !["ph", "style"].contains(node.name) else {
      @failure.reject(
        "protected-content", "Portable objects must detach placeholder roles",
      )
    }
    if node.uri == drawing_uri && node.name == "hlinkClick" {
      ignore(hyperlink_node({ tree, node: tree.nodes[node.parent], }))
      check_clipboard_link_metadata(node)
      let id = node.attribute("id", uri=relationship_uri).unwrap_or("")
      let action = node.attribute("action").unwrap_or("")
      guard (
          id.is_empty() &&
          action.has_prefix("ppaction://hlinkshowjump?jump=") &&
          navigation_action(
            action["ppaction://hlinkshowjump?jump=".length():].to_owned(),
          )
        ) ||
        (!id.is_empty() && action.is_empty()) else {
        @failure.reject(
          "protected-content", "Unsupported portable object hyperlink action",
        )
      }
    }
    for attr in node.attributes {
      if attr.uri != relationship_uri {
        continue
      }
      if node.name == "hlinkClick" && attr.name == "id" && attr.value.is_empty() {
        continue
      }
      let kind = if node.uri == drawing_uri &&
        node.name == "blip" &&
        attr.name == "embed" {
        "image"
      } else if node.uri == drawing_uri &&
        node.name == "hlinkClick" &&
        attr.name == "id" {
        "external"
      } else if chart_frame_reference(tree, node) && attr.name == "id" {
        "chart"
      } else {
        ""
      }
      guard resources.any(resource => {
        resource.id == attr.value &&
        resource.style is None &&
        (if resource.image is Some(_) {
          "image"
        } else if resource.chart is Some(_) {
          "chart"
        } else {
          "external"
        }) ==
        kind
      }) else {
        @failure.reject(
          "protected-content", "Unresolved portable object resource",
        )
      }
      used.add(attr.value)
    }
    if node.uri == drawing_uri && node.name == "hlinkMouseOver" {
      @failure.reject(
        "protected-content", "Hover clipboard links require support",
      )
    }
  }
  guard used.length() == resources.length() else {
    @failure.reject(
      "invalid-operation", "Object clipboard contains unused resources",
    )
  }
  { tree, selection, active, resources, }
}
