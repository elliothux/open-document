///|
priv struct PictureResource {
  path : String
  link : String
  data : Bytes
  parts : Map[String, @xml.Document]
  media : Map[String, Bytes]
  edits : Map[String, Array[@xml.Edit]]
  created : Map[String, @xml.Document]
}

///|
fn Session::prepare_picture_resource(
  self : Session,
  id : Int,
  bytes : Bytes,
  kind : (String, String),
  owner~ : String = self.main,
) -> PictureResource raise @failure.Failure {
  let (extension, content_type) = kind
  let rel_uri = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  let segments = self.main.split("/").to_array()
  let directory = segments[:segments.length() - 1]
    .map(s => s.to_owned())
    .join("/")
  let prefix = if directory.is_empty() { "" } else { directory + "/" }
  let links = self.relationships()
  let (path, link) = for sequence = 1
                         sequence <= 16384
                         sequence = sequence + 1 {
    let path = prefix + "media/image\{id}_\{sequence}.\{extension}"
    let link = "odImage\{id}_\{sequence}"
    if !self.opc.names.contains(path.to_lower()) &&
      !self.media.contains(path) &&
      !self.parts.contains(path) &&
      !links.iter().any(rel => rel.owner == owner && rel.id == link) {
      break (path, link)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Image identities exhausted")
  }
  let parts = self.parts.copy()
  let media = self.media.copy()
  media[path] = bytes
  let edits : Map[String, Array[@xml.Edit]] = Map([])
  let created : Map[String, @xml.Document] = Map([])
  let owner_segments = owner.split("/").to_array()
  let owner_directory = owner_segments[:owner_segments.length() - 1]
    .map(s => s.to_owned())
    .join("/")
  let rels_path = (if owner_directory.is_empty() {
      ""
    } else {
      owner_directory + "/"
    }) +
    "_rels/" +
    owner_segments.last().unwrap().to_owned() +
    ".rels"
  let rels_path = self.opc.names.get(rels_path.to_lower()).unwrap_or(rels_path)
  let markup = "<Relationship xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\" Id=\"\{link}\" Type=\"\{rel_uri}/image\" Target=\"/" +
    property_attribute(path) +
    "\"/>"
  if self.opc.names.contains(rels_path.to_lower()) || parts.contains(rels_path) {
    let (candidate, edit) = append_part_xml(self.part_xml(rels_path), markup)
    parts[rels_path] = candidate
    edits[rels_path] = [edit]
  } else {
    let candidate = @xml.Document::parse(
      @utf8.encode(
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\{markup}</Relationships>",
      ),
      rels_path,
      self.opc.budget.xml_depth,
      self.opc.budget.entry_bytes,
    )
    parts[rels_path] = candidate
    created[rels_path] = candidate
  }
  let types = self.opc.names["[content_types].xml"]
  let (candidate_types, types_edit) = append_part_xml(
    self.part_xml(types),
    "<Override xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" PartName=\"/" +
    property_attribute(path) +
    "\" ContentType=\"\{content_type}\"/>",
  )
  parts[types] = candidate_types
  edits[types] = [types_edit]
  { path, link, data: bytes, parts, media, edits, created, }
}

///|
fn Session::commit_picture_resource(
  self : Session,
  resource : PictureResource,
  candidate : @xml.Document,
  xml : Array[@xml.Edit],
  paragraphs : Array[Int],
  after : Selection?,
) -> Json raise @failure.Failure {
  let mut count = xml_part_edit_bytes(resource.edits, resource.created)
  for step in xml {
    let size = edit_bytes(step)
    guard size <= history_byte_limit - count else {
      @failure.reject("limit-exceeded", "Picture source exceeds history budget")
    }
    count += size
  }
  guard resource.data.length() <= history_byte_limit - count else {
    @failure.reject("limit-exceeded", "Picture resource exceeds history budget")
  }
  self.commit_edit(
    {
      xml,
      parts: resource.edits,
      created: resource.created,
      created_media: Map([(resource.path, resource.data)]),
      before: self.selection,
      after,
      paragraphs,
      bytes: count + resource.data.length(),
    },
    candidate,
    parts=resource.parts,
    media=resource.media,
  )
  self.edit_result(paragraphs)
}
