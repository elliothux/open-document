///|
pub fn Session::replace_picture(
  self : Session,
  revision : Int,
  id : Int,
  bytes : Bytes,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let document = self.document()
  let tree = WordTree::new(document)
  let (image, paragraph, fill, _) = self.editable_picture(
    tree,
    id,
    replace=true,
  )
  let kind = @image.type_info(bytes)
  if self.image_bytes(image.key) == bytes {
    return self.edit_state()
  }
  let blip = tree.children[fill]
    .iter()
    .find_first(child => {
      tree.nodes[child].uri == picture_drawing_uri &&
      tree.nodes[child].name == "blip"
    })
    .unwrap()
  let node = tree.nodes[blip]
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let embed = node.attributes
    .iter()
    .find_first(attr => attr.uri == rel_uri && attr.name == "embed")
    .unwrap()
  let resource = self.prepare_picture_resource(id, bytes, kind)
  let (candidate, xml) = document.edit_source([
    {
      node: blip,
      offset: embed.start - node.start,
      length: embed.end - embed.start,
      xml: resource.link,
    },
  ])
  self.commit_picture_resource(
    resource,
    candidate,
    [xml],
    [paragraph],
    self.selection,
  )
}
