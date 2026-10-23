///|
priv struct ClipboardMedia {
  kind : String
  content_type : String
  bytes : Bytes
  playback : MediaPlaybackSettings
}

///|
fn read_clipboard_media(
  kind : String,
  value : String,
) -> ClipboardMedia raise @failure.Failure {
  let parsed = @json.parse(value) catch {
    _ => @failure.reject("invalid-operation", "Invalid clipboard media JSON")
  }
  guard parsed is Object(fields) &&
    fields.length() == 5 &&
    fields
    is {
      "bytes": String(encoded),
      "contentType": String(content_type),
      "loop": cycling,
      "volume": Number(volume, ..),
      "mute": mute,
      ..
    } &&
    (cycling is True || cycling is False) &&
    (mute is True || mute is False) &&
    encoded.length() <= 22369624 &&
    volume.floor() == volume &&
    volume >= 0 &&
    volume <= 100000 else {
    @failure.reject("invalid-operation", "Invalid clipboard media fields")
  }
  let bytes = @base64.decode(encoded) catch {
    _ => @failure.reject("invalid-operation", "Invalid clipboard media bytes")
  }
  ignore(check_media_input(kind, content_type, bytes))
  {
    kind,
    content_type,
    bytes,
    playback: {
      cycling: cycling is True,
      volume: volume.to_int(),
      mute: mute is True,
    },
  }
}

///|
fn Session::clipboard_media(
  self : Session,
  object : Object,
  resources : Map[String, Json],
) -> Array[@xml.SourceChange] raise @failure.Failure {
  guard object.media is Some(media) && media.reason.is_empty() else {
    @failure.reject("protected-content", "Clipboard requires local media")
  }
  let playback = read_media_nodes(self.current().tree)
    .get(object.id)
    .map(value => value.1)
    .unwrap_or(MediaPlaybackSettings::initial())
  let key = media.kind + "\n" + media.key + "\n" + playback.json().stringify()
  let id = if resources.get(key) is Some({ "id": String(id), .. }) {
    id
  } else {
    guard resources.length() < 256 else {
      @failure.reject(
        "limit-exceeded", "Object clipboard exceeds 256 resources",
      )
    }
    let bytes = self.image_content(media.key)
    ignore(check_media_input(media.kind, media.content_type, bytes))
    let id = "odClip" + resources.length().to_string()
    let value : Json = {
      "bytes": @base64.encode(bytes),
      "contentType": media.content_type,
      "loop": playback.cycling,
      "volume": playback.volume,
      "mute": playback.mute,
    }
    resources[key] = {
      "id": id,
      "kind": media.kind,
      "value": value.stringify(),
    }
    id
  }
  let changes : Array[@xml.SourceChange] = []
  let source = object.source
  for node in source.tree.document.nodes() {
    if node.start < source.node.start || node.end > source.node.end {
      continue
    }
    if (
        node.uri == drawing_uri &&
        ["audioFile", "videoFile"].contains(node.name)
      ) ||
      (node.uri == creation_uri && node.name == "media") {
      for attr in node.attributes {
        if attr.uri == relationship_uri {
          changes.push({
            node: node.id,
            offset: attr.start - node.start,
            length: attr.end - attr.start,
            xml: id,
          })
        }
      }
    }
  }
  changes
}

///|
fn clipboard_media_click(tree : Tree, node : @xml.Node) -> Bool {
  if node.uri != drawing_uri ||
    node.name != "hlinkClick" ||
    node.attribute("action") != Some("ppaction://media") {
    return false
  }
  guard node.attribute("id", uri=relationship_uri) == Some("") &&
    node.attributes.length() == 2 &&
    tree.children.get(node.id).unwrap_or([]).is_empty() &&
    node.text.trim().is_empty() &&
    tree.nodes.get(node.parent) is Some(properties) &&
    properties.name == "cNvPr" &&
    tree.nodes.get(properties.parent) is Some(nv) &&
    nv.name == "nvPicPr" &&
    tree.nodes.get(nv.parent) is Some(picture) &&
    picture.name == "pic" else {
    return false
  }
  tree.document
  .nodes()
  .any(child => {
    child.start > picture.start &&
    child.end < picture.end &&
    (
      (
        child.uri == drawing_uri &&
        ["audioFile", "videoFile"].contains(child.name)
      ) ||
      (child.uri == creation_uri && child.name == "media")
    )
  })
}

///|
fn clipboard_media_reference(
  tree : Tree,
  node : @xml.Node,
  attr : @xml.Attribute,
) -> Bool {
  attr.uri == relationship_uri &&
  (
    (
      node.uri == drawing_uri &&
      ["audioFile", "videoFile"].contains(node.name) &&
      attr.name == "link"
    ) ||
    (
      node.uri == creation_uri &&
      node.name == "media" &&
      attr.name == "embed" &&
      node.parent >= 0 &&
      media_extension(tree, tree.nodes[node.parent])
    )
  )
}

///|
/// Returns validated local media for platform decoding before object paste.
pub fn Session::object_fragment_media(
  self : Session,
  revision : Int,
  value : String,
) -> Array[Json] raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  read_object_fragment(value, self.budget).resources.filter_map(resource => {
    resource.media.map(media => {
      "kind": media.kind,
      "contentType": media.content_type,
      "bytes": @base64.encode(media.bytes),
    })
  })
}

///|
fn Session::attach_clipboard_media(
  self : Session,
  value : ClipboardMedia,
  id : String,
  parts : Map[String, @xml.Document],
  media : Map[String, Bytes],
  created : Map[String, @xml.Document],
  created_media : Map[String, Bytes],
  edits : Array[(String, @xml.Edit)],
  reserved : Set[String],
) -> String raise @failure.Failure {
  let extension = check_media_input(value.kind, value.content_type, value.bytes)
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let prefix = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  let (path, link) = for sequence in 0..<=self.budget.entries {
    let path = prefix + "media/odClip\{id}-\{sequence}.\{extension}"
    let link = "odClipboardMedia\{id}_\{sequence}"
    if !self.opc.names.contains(path.to_lower()) &&
      !parts.contains(path) &&
      !media.contains(path) &&
      !reserved.contains(link) &&
      !reserved.contains(link + "File") {
      break (path, link)
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Media clipboard identities exhausted")
  }
  media[path] = value.bytes
  created_media[path] = value.bytes
  reserved.add(link)
  reserved.add(link + "File")
  self.append_chart_xml(
    relationship_part(self.current().tree.part),
    "<Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='\{link}' Type='\{media_relationship_uri}' Target='/\{xml_attribute(path)}'/><Relationship xmlns='http://schemas.openxmlformats.org/package/2006/relationships' Id='\{link}File' Type='\{relationship_uri}/\{value.kind}' Target='/\{xml_attribute(path)}'/>",
    parts,
    created,
    edits,
  )
  self.append_chart_xml(
    "[Content_Types].xml",
    "<Override xmlns='http://schemas.openxmlformats.org/package/2006/content-types' PartName='/\{xml_attribute(path)}' ContentType='\{value.content_type}'/>",
    parts,
    created,
    edits,
  )
  link
}
