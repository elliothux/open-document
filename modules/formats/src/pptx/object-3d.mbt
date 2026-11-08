///|
fn check_object_3d(theme : Theme, source : Ref) -> Unit raise @failure.Failure {
  let tree = source.tree
  let nodes = tree.children.get(source.node.id).unwrap_or([])
  let xml = source_xml(source)
  guard source.node.text.trim().is_empty() &&
    !xml.contains("<!--") &&
    !xml.contains("<?") else {
    @failure.reject(
      "unsupported-style", "Extended object 3D metadata is protected",
    )
  }
  if source.node.name == "scene3d" {
    guard source.node.attributes.is_empty() &&
      nodes is [camera, light] &&
      camera.name == "camera" &&
      camera.uri == drawing_uri &&
      camera.text.trim().is_empty() &&
      camera.attribute("prst") == Some("orthographicFront") &&
      camera.attributes.all(a => {
        a.uri.is_empty() && ["prst", "fov"].contains(a.name)
      }) &&
      light.name == "lightRig" &&
      light.uri == drawing_uri &&
      light.text.trim().is_empty() &&
      light.attributes.length() == 2 &&
      light.attributes.all(a => {
        a.uri.is_empty() && ["rig", "dir"].contains(a.name)
      }) &&
      [
        "balanced", "brightRoom", "chilly", "contrasting", "flat", "flood", "freezing",
        "glow", "harsh", "legacyFlat1", "legacyFlat2", "legacyFlat3", "legacyFlat4",
        "legacyHarsh1", "legacyHarsh2", "legacyHarsh3", "legacyHarsh4", "legacyNormal1",
        "legacyNormal2", "legacyNormal3", "legacyNormal4", "morning", "soft", "sunrise",
        "sunset", "threePt", "twoPt",
      ].contains(light.attribute("rig").unwrap_or("")) &&
      ["t", "tr", "r", "br", "b", "bl", "l", "tl"].contains(
        light.attribute("dir").unwrap_or(""),
      ) else {
      @failure.reject(
        "unsupported-style", "Nonfront or extended object scene is protected",
      )
    }
    if camera.attribute("fov") is Some(value) {
      ignore(number(value, 0, 10800000))
    }
    for item in [camera, light] {
      let rotations = tree.children.get(item.id).unwrap_or([])
      guard rotations.is_empty() ||
        (
          rotations is [rotation] &&
          rotation.uri == drawing_uri &&
          rotation.name == "rot" &&
          rotation.text.trim().is_empty() &&
          tree.children.get(rotation.id).unwrap_or([]).is_empty() &&
          rotation.attributes.length() == 3 &&
          rotation.attributes.all(a => {
            a.uri.is_empty() && ["lat", "lon", "rev"].contains(a.name)
          })
        ) else {
        @failure.reject(
          "unsupported-style", "Extended object scene rotation is protected",
        )
      }
      if rotations.get(0) is Some(rotation) {
        for name in ["lat", "lon", "rev"] {
          let angle = number(rotation.attribute(name).unwrap(), 0, 21599999)
          guard item.name != "camera" || angle == 0 else {
            @failure.reject(
              "unsupported-style", "Nonfront object camera is protected",
            )
          }
        }
      }
    }
  } else {
    guard source.node.name == "sp3d" &&
      source.node.attributes.all(a => {
        a.uri.is_empty() &&
        ["extrusionH", "contourW", "prstMaterial"].contains(a.name)
      }) &&
      [
        "clear", "dkEdge", "flat", "legacyMatte", "legacyMetal", "legacyPlastic",
        "legacyWireframe", "matte", "metal", "plastic", "powder", "softEdge", "softmetal",
        "translucentPowder", "warmMatte",
      ].contains(source.node.attribute("prstMaterial").unwrap_or("warmMatte")) else {
      @failure.reject(
        "unsupported-style", "Extended object material is protected",
      )
    }
    for name in ["extrusionH", "contourW"] {
      if source.node.attribute(name) is Some(value) {
        ignore(number(value, 0, 2147483647))
      }
    }
    for node in nodes {
      guard node.uri == drawing_uri &&
        node.text.trim().is_empty() &&
        ["bevelT", "bevelB", "contourClr"].contains(node.name) &&
        nodes.filter(n => n.name == node.name).length() == 1 else {
        @failure.reject(
          "unsupported-style", "Extended object bevel or contour is protected",
        )
      }
      if node.name == "contourClr" {
        guard node.attributes.is_empty() else {
          @failure.reject(
            "unsupported-style", "Extended object contour color is protected",
          )
        }
        let reference : Ref = { tree, node, }
        background_color_markup(reference)
        ignore(color_rgba(theme, reference))
      } else {
        guard tree.children.get(node.id).unwrap_or([]).is_empty() &&
          node.attributes.all(a => {
            a.uri.is_empty() && ["w", "h", "prst"].contains(a.name)
          }) &&
          [
            "angle", "artDeco", "circle", "convex", "coolSlant", "cross", "divot",
            "hardEdge", "relaxedInset", "riblet", "slope", "softRound",
          ].contains(node.attribute("prst").unwrap_or("circle")) else {
          @failure.reject(
            "unsupported-style", "Extended object bevel is protected",
          )
        }
        for name in ["w", "h"] {
          if node.attribute(name) is Some(value) {
            ignore(number(value, 0, 2147483647))
          }
        }
      }
    }
  }
}
