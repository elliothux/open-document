///|
fn check_picture_bullet(source : Ref) -> Ref raise @failure.Failure {
  let xml = source_xml(source)
  let tree = source.tree
  guard source.node.attributes.is_empty() &&
    source.node.text.trim().is_empty() &&
    !xml.contains("<!--") &&
    !xml.contains("<?") &&
    tree.children.get(source.node.id).unwrap_or([]) is [blip] &&
    blip.uri == drawing_uri &&
    blip.name == "blip" &&
    blip.text.trim().is_empty() &&
    tree.children.get(blip.id).unwrap_or([]).is_empty() &&
    blip.attributes is [{ name: "embed", uri, value: embed, .. }] &&
    uri == relationship_uri &&
    !embed.is_empty() else {
    @failure.reject(
      "unsupported-text", "Extended picture bullets are protected",
    )
  }
  { tree, node: blip, }
}

///|
fn read_picture_bullet(
  opc : @opc.Package,
  styles : Array[Ref],
  parts : Map[String, @xml.Document],
  media : Map[String, Bytes],
) -> (String, Double) raise @failure.Failure {
  let source = for item in styles {
    if item.child("buBlip") is Some(source) {
      break source
    }
  } nobreak {
    @failure.reject("unsupported-text", "Missing picture bullet source")
  }
  let blip = check_picture_bullet(source)
  let target = relationship_target(
    opc,
    source.tree.part,
    blip.node.attribute("embed", uri=relationship_uri).unwrap(),
    relationship_uri + "/image",
    parts,
  )
  guard target is Some(key) &&
    [Some("image/png"), Some("image/jpeg"), Some("image/gif")].contains(
      image_content_type(opc, key, parts),
    ) else {
    @failure.reject(
      "unsupported-text", "Missing unsupported or external picture bullet image",
    )
  }
  let bytes = media.get(key).unwrap_or_else(() => opc.read(key))
  let (_, mime, width, height) = raster_image_info(bytes)
  guard image_content_type(opc, key, parts) == Some(mime) else {
    @failure.reject(
      "unsupported-text", "Picture bullet image type does not match its content type",
    )
  }
  (key, width.to_double() / height.to_double())
}
