///|
let media_relationship_uri = "http://schemas.microsoft.com/office/2007/relationships/media"

///|
let media_extension_uri = "{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}"

///|
priv struct Media {
  kind : String
  key : String
  content_type : String
  reason : String
}

///|
fn media_extension(tree : Tree, node : @xml.Node) -> Bool {
  let children = tree.children.get(node.id).unwrap_or([])
  node.uri == presentation_uri &&
  node.name == "ext" &&
  node.attribute("uri") == Some(media_extension_uri) &&
  node.attributes.length() == 1 &&
  children is [child] &&
  child.uri == creation_uri &&
  child.name == "media" &&
  child.attributes.length() == 1 &&
  child.attribute("embed", uri=relationship_uri) is Some(_) &&
  tree.children.get(child.id).unwrap_or([]).is_empty() &&
  child.text.trim().is_empty()
}

///|
fn media_link(
  opc : @opc.Package,
  owner : String,
  id : String,
  parts : Map[String, @xml.Document],
) -> (String, String, Bool)? raise @failure.Failure {
  if parts.get(relationship_part(owner)) is Some(document) {
    let links = document
      .nodes()
      .filter(node => node.attribute("Id") == Some(id))
    guard links is [link] &&
      link.attribute("Type") is Some(kind) &&
      link.attribute("Target") is Some(target) else {
      return None
    }
    let external = link.attribute("TargetMode") == Some("External")
    return Some(
      (
        kind,
        if external {
          target
        } else {
          @opc.resolve_target(owner, target)
        },
        external,
      ),
    )
  }
  opc
  .relationships()
  .iter()
  .find_first(rel => rel.owner == owner && rel.id == id)
  .map(rel => (rel.kind, rel.target, rel.external))
}

///|
fn read_media(
  opc : @opc.Package,
  source : Ref,
  parts : Map[String, @xml.Document],
) -> Media? raise @failure.Failure {
  guard source.node.name == "pic" &&
    source
    .child("nvPicPr", uri=presentation_uri)
    .bind(nv => nv.child("nvPr", uri=presentation_uri))
    is Some(nv) else {
    return None
  }
  let files = nv.tree.children
    .get(nv.node.id)
    .unwrap_or([])
    .filter(node => {
      node.uri == drawing_uri && ["audioFile", "videoFile"].contains(node.name)
    })
  let extensions = nv
    .child("extLst", uri=presentation_uri)
    .map(list => {
      list.tree.children
      .get(list.node.id)
      .unwrap_or([])
      .filter(node => node.attribute("uri") == Some(media_extension_uri))
    })
    .unwrap_or([])
  guard !files.is_empty() || !extensions.is_empty() else { return None }
  let kind = if files.get(0).map(n => n.name == "audioFile").unwrap_or(false) {
    "audio"
  } else {
    "video"
  }
  let blocked = (reason : String) => {
    Some({ kind, key: "", content_type: "", reason, })
  }
  guard files.length() <= 1 &&
    extensions.length() <= 1 &&
    extensions.all(node => media_extension(nv.tree, node)) else {
    return blocked("Unknown media metadata is protected")
  }
  let legacy = files
    .get(0)
    .bind(node => node.attribute("link", uri=relationship_uri))
    .bind(id => media_link(opc, source.tree.part, id, parts))
  let embedded = extensions
    .get(0)
    .bind(node => nv.tree.children.get(node.id))
    .bind(nodes => nodes.get(0))
    .bind(node => node.attribute("embed", uri=relationship_uri))
    .bind(id => media_link(opc, source.tree.part, id, parts))
  guard (files.is_empty() || legacy is Some(_)) &&
    (extensions.is_empty() || embedded is Some(_)) else {
    return blocked("Missing media relationship")
  }
  if legacy is Some((_, _, true)) || embedded is Some((_, _, true)) {
    return blocked("External media requires explicitly supplied local bytes")
  }
  guard legacy
    .map(link => link.0 == relationship_uri + "/" + kind)
    .unwrap_or(true) &&
    embedded.map(link => link.0 == media_relationship_uri).unwrap_or(true) &&
    (
      legacy is None ||
      embedded is None ||
      legacy.unwrap().1 == embedded.unwrap().1
    ) else {
    return blocked("Conflicting media relationships are protected")
  }
  let key = embedded.unwrap_or_else(() => legacy.unwrap()).1
  let content_type = image_content_type(opc, key, parts).unwrap_or("")
  let kind = if files.is_empty() && content_type.has_prefix("audio/") {
    "audio"
  } else {
    kind
  }
  Some({
    kind,
    key,
    content_type,
    reason: if media_extension_for(kind, content_type) is Some(_) {
      ""
    } else {
      "Unsupported media content type"
    },
  })
}

///|
fn media_extension_for(kind : String, content_type : String) -> String? {
  match (kind, content_type) {
    ("audio", "audio/wav") => Some("wav")
    ("audio", "audio/mpeg") => Some("mp3")
    ("audio", "audio/mp4") => Some("m4a")
    ("video", "video/mp4") => Some("mp4")
    ("audio", "audio/webm") | ("video", "video/webm") => Some("webm")
    _ => None
  }
}

///|
fn Object::media_query(self : Object) -> Json {
  self.media
  .map(media => {
    let value : Json = {
      "kind": media.kind,
      "key": media.key,
      "contentType": media.content_type,
      "poster": self.image.map(key => Json(key)).unwrap_or(Json::null()),
      "reason": if media.reason.is_empty() && self.image is None {
        "Media poster is missing"
      } else {
        media.reason
      },
    }
    value
  })
  .unwrap_or(Json::null())
}

///|
/// Reads an embedded media resource declared by an object; external URLs are never fetched.
pub fn Session::media_bytes(
  self : Session,
  key : String,
) -> Bytes raise @failure.Failure {
  self.check()
  guard self.slides.any(slide => {
    slide.objects.any(object => {
      object.media is Some(media) && media.key == key && media.reason.is_empty()
    })
  }) else {
    @failure.reject(
      "invalid-operation", "Unknown or protected presentation media",
    )
  }
  self.check_media_budget(self.main, self.slides, self.parts, self.media)
  self.image_content(key)
}

///|
fn Session::check_media_budget(
  self : Session,
  main : Tree,
  slides : Array[Slide],
  parts : Map[String, @xml.Document],
  media : Map[String, Bytes],
  removed~ : Array[String] = self.removed,
) -> Unit raise @failure.Failure {
  let keys : Map[String, Bool] = Map([])
  let replacements = self.replacements(main, slides, parts, media~)
  let mut total = 0L
  for link in self.opc.relationships(replacements~, removed~) {
    if link.external ||
      ![
        relationship_uri + "/audio",
        relationship_uri + "/video",
        media_relationship_uri,
      ].contains(link.kind) ||
      keys.contains(link.target) {
      continue
    }
    keys[link.target] = true
    let bytes = media
      .get(link.target)
      .unwrap_or_else(() => self.opc.read(link.target))
    total += bytes.length().to_int64()
    guard bytes.length() <= 16777216 &&
      total <= 67108864L &&
      keys.length() <= 64 else {
      @failure.reject(
        "limit-exceeded", "Presentation media exceeds 16 MiB per resource, 64 resources or 64 MiB total",
      )
    }
  }
}
