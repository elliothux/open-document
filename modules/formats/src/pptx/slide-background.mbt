///|
fn Session::background_reason(self : Session, slide : Slide) -> String {
  let protection = self.slide_visibility_reason()
  if !protection.is_empty() {
    return protection
  }
  try {
    let tree = slide.tree
    let container = tree.required(
      tree.root("sld").id,
      "cSld",
      uri=presentation_uri,
    )
    guard tree.one(container.id, "bg", uri=presentation_uri) is Some(bg) else {
      return ""
    }
    let source = tree.document.source()[bg.start:bg.end]
    guard !source.contains("<!--") &&
      !source.contains("<?") &&
      bg.text.trim().is_empty() &&
      bg.attributes.all(a => a.uri.is_empty() && a.name == "bwMode") else {
      return "Unknown background markup is protected"
    }
    let children = tree.children.get(bg.id).unwrap_or([])
    guard children is [properties] &&
      properties.uri == presentation_uri &&
      ["bgPr", "bgRef"].contains(properties.name) &&
      properties.text.trim().is_empty() &&
      properties.attributes.all(a => {
        a.uri.is_empty() &&
        (if properties.name == "bgPr" {
          a.name == "shadeToTitle"
        } else {
          a.name == "idx"
        })
      }) else {
      return "Unknown background properties are protected"
    }
    if properties.name == "bgPr" &&
      tree.one(properties.id, "blipFill") is Some(image) {
      let properties : Ref = { tree, node: properties, }
      let image : Ref = { tree, node: image, }
      background_image_properties(properties, image)
      ignore(read_shape_image(self.opc, image, self.parts, background=true))
      return ""
    }
    if properties.name == "bgPr" &&
      tree.one(properties.id, "gradFill") is Some(gradient) {
      ignore(linear_background_source({ tree, node: gradient, }))
      guard tree.children
        .get(properties.id)
        .unwrap_or([])
        .all(node => {
          node.id == gradient.id ||
          (
            node.uri == drawing_uri &&
            node.name == "effectLst" &&
            node.attributes.is_empty() &&
            node.text.trim().is_empty() &&
            tree.children.get(node.id).unwrap_or([]).is_empty()
          )
        }) else {
        return "Unsupported gradient background properties"
      }
      return ""
    }
    for node in tree.document.nodes() {
      if node.start <= properties.start || node.end > properties.end {
        continue
      }
      guard node.uri == drawing_uri && node.text.trim().is_empty() else {
        return "Background extensions are protected"
      }
      match node.name {
        "solidFill" | "noFill" | "effectLst" => {
          guard properties.name == "bgPr" &&
            node.parent == properties.id &&
            node.attributes.is_empty() &&
            (
              node.name == "solidFill" ||
              tree.children.get(node.id).unwrap_or([]).is_empty()
            ) else {
            return "Background effects are protected"
          }
          if node.name == "solidFill" &&
            tree.children.get(node.id).unwrap_or([]).length() != 1 {
            return "Ambiguous background color is protected"
          }
        }
        "srgbClr" | "schemeClr" | "sysClr" => {
          let parent = tree.nodes[node.parent]
          guard (parent.id == properties.id && properties.name == "bgRef") ||
            (
              parent.uri == drawing_uri &&
              parent.name == "solidFill" &&
              parent.parent == properties.id
            ) else {
            return "Unknown background color structure is protected"
          }
          guard node.attributes.all(a => {
            a.uri.is_empty() &&
            (a.name == "val" || (node.name == "sysClr" && a.name == "lastClr"))
          }) else {
            return "Unknown background color is protected"
          }
        }
        "tint" | "shade" | "lumMod" | "lumOff" => {
          guard ["srgbClr", "schemeClr", "sysClr"].contains(
              tree.nodes[node.parent].name,
            ) &&
            node.attributes.all(a => a.uri.is_empty() && a.name == "val") &&
            tree.children.get(node.id).unwrap_or([]).is_empty() else {
            return "Unknown background transform is protected"
          }
        }
        _ => return "Unsupported background fill is protected"
      }
    }
    if properties.name == "bgPr" {
      guard tree.all(properties.id, "solidFill").length() +
        tree.all(properties.id, "noFill").length() ==
        1 &&
        tree.all(properties.id, "effectLst").length() <= 1 else {
        return "Ambiguous background fill is protected"
      }
    } else if tree.children.get(properties.id).unwrap_or([]).length() != 1 {
      return "Ambiguous background reference is protected"
    }
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
fn Session::set_background(
  self : Session,
  index : Int,
  value : BackgroundFill?,
) -> Json raise @failure.Failure {
  let value = value.map(v => v.normalized())
  let original = self.slides[index]
  let reason = self.background_reason(original)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let tree = original.tree
  let container = tree.required(
    tree.root("sld").id,
    "cSld",
    uri=presentation_uri,
  )
  let background = tree.one(container.id, "bg", uri=presentation_uri)
  if (background is None && value is None) ||
    (
      background is Some(_) &&
      value is Some(fill) &&
      fill == original.background
    ) {
    return self.query()
  }
  let change = background_change(original, value.map(v => v.markup()))
  let (candidate, edit) = self.prepare(original, [change])
  self.commit(candidate, edit, self.selection)
  self.query()
}
