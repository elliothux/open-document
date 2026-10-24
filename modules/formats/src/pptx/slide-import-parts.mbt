///|
priv struct ImportedParts {
  documents : Map[String, @xml.Document]
  media : Map[String, Bytes]
  kinds : Map[String, String]
}

///|
fn import_relationship_kinds(kind : String) -> Array[String] {
  match kind {
    "slide" =>
      [
        "slideLayout", "image", "hyperlink", "slide", "notesSlide", "audio", "video",
        "media", "chart", "comments",
      ]
    "slideLayout" => ["slideMaster", "image", "hyperlink", "slide"]
    "slideMaster" => ["slideLayout", "theme", "image", "hyperlink", "slide"]
    "notesSlide" => ["notesMaster", "image", "hyperlink", "slide"]
    "notesMaster" => ["theme", "image", "hyperlink"]
    "theme" => ["image", "hyperlink"]
    "chart" => ["package"]
    "comments" => ["hyperlink"]
    _ => []
  }
}

///|
fn Session::slide_import_parts(
  self : Session,
  selected : Array[String],
) -> ImportedParts raise @failure.Failure {
  let links = self.relationships()
  let mut comments = 0
  for slide in selected {
    if self.comment_part(slide, "comments", links) is Some(tree) {
      let entries = read_comment_entries(tree)
      let author_tree = self.comment_authors(Some(tree), links)
      if author_tree is Some(owner) {
        guard !links.any(link => link.owner == owner.part) else {
          @failure.reject(
            "protected-content", "Imported author resources require ownership support",
          )
        }
      }
      let authors = author_tree.map(read_comment_authors).unwrap_or([])
      guard entries.all(e => authors.any(a => a.id == e.author)) else {
        @failure.reject(
          "protected-content", "Imported comment author is missing",
        )
      }
      if tree.document.nodes()[0].uri == modern_comment_uri {
        self.check_comment_anchors(tree, slide)
      }
      comments += entries.length()
      guard comments <= 16384 else {
        @failure.reject(
          "limit-exceeded", "Imported comments exceed allocation budget",
        )
      }
    }
  }
  let kinds = Map::from_array(selected.map(part => (part, "slide")))
  let pending = selected.copy()
  let documents : Map[String, @xml.Document] = Map([])
  let media : Map[String, Bytes] = Map([])
  let mut payload = 0L
  let mut media_payload = 0L
  let mut pixels = 0L
  let mut index = 0
  while index < pending.length() {
    let part = pending[index]
    let kind = kinds[part]
    index += 1
    if ["image", "audio", "video", "media", "package"].contains(kind) {
      let bytes = self.image_content(part)
      let content_type = self.opc.content_type(part).unwrap_or("")
      if kind == "image" {
        let (_, _, width, height) = @image.type_info(bytes)
        pixels += width.to_int64() * height.to_int64() * 4
        guard bytes.length() <= 2097152 else {
          @failure.reject(
            "limit-exceeded",
            "Imported image exceeds 2MiB",
            part~,
          )
        }
      } else if kind != "package" {
        let media_kind = if content_type.has_prefix("audio/") {
          "audio"
        } else {
          "video"
        }
        ignore(check_media_input(media_kind, content_type, bytes))
      }
      if content_type.has_prefix("audio/") || content_type.has_prefix("video/") {
        media_payload += bytes.length().to_int64()
      } else {
        payload += bytes.length().to_int64()
      }
      media[part] = bytes
    } else {
      let document = self.part_document(part)
      let tree = Tree::new(part, document)
      if kind == "chart" {
        ignore(@chart.read(self.opc, part, self.parts))
      } else if kind == "comments" {
        ignore(read_comment_entries(tree))
      } else {
        check_slide_copy_markup(tree)
      }
      payload += document.source().length().to_int64() * 2
      documents[part] = document
      let path = relationship_part(part)
      if self.opc.names.contains(path.to_lower()) {
        let relations = self.part_document(path)
        payload += relations.source().length().to_int64() * 2
        documents[path] = relations
      }
    }
    guard payload <= 4194304L &&
      media_payload <= 67108864L &&
      pixels <= 16777216L else {
      @failure.reject(
        "limit-exceeded", "Imported slide resources exceed history budget",
      )
    }
    let allowed = import_relationship_kinds(kind)
    for link in links {
      if link.owner != part {
        continue
      }
      let child_kind = if link.kind == media_relationship_uri {
        "media"
      } else if link.kind == modern_comment_relationship + "/comments" {
        "comments"
      } else if link.kind.has_prefix(relationship_uri + "/") {
        link.kind[relationship_uri.length() + 1:].to_owned()
      } else {
        ""
      }
      guard allowed.contains(child_kind) &&
        (!link.external || child_kind == "hyperlink") else {
        @failure.reject(
          "protected-content",
          "Slide resource requires cross-presentation import support",
          part~,
        )
      }
      if link.external {
        check_external_hyperlink(link.target)
        continue
      }
      let target = self.opc.names
        .get(link.target.to_lower())
        .unwrap_or(link.target)
      guard child_kind != "slide" || selected.contains(target) else {
        @failure.reject(
          "protected-content",
          "Import the destination of the slide hyperlink as well",
          part~,
        )
      }
      if !kinds.contains(target) {
        kinds[target] = child_kind
        pending.push(target)
        guard pending.length() + documents.length() <= self.budget.entries else {
          @failure.reject(
            "limit-exceeded", "Imported part count exceeds budget",
          )
        }
      }
    }
  }
  { documents, media, kinds, }
}

///|
fn import_main_entries(
  tree : Tree,
  name : String,
  markup : String,
) -> (@xml.Document, @xml.Edit) raise @failure.Failure {
  let root = tree.root("presentation")
  let change = if tree.one(root.id, name, uri=presentation_uri) is Some(list) {
    insertion(list, markup)
  } else {
    let after = if name == "notesMasterIdLst" {
      tree
      .one(root.id, "sldMasterIdLst", uri=presentation_uri)
      .map(n => n.end)
      .unwrap_or(root.opening_end)
    } else {
      root.opening_end
    }
    @xml.SourceChange::{
      node: root.id,
      offset: after - root.start,
      length: 0,
      xml: "<p:\{name} xmlns:p='\{presentation_uri}'>\{markup}</p:\{name}>",
    }
  }
  tree.document.edit_source([change])
}

///|
fn Session::import_prefix(self : Session) -> String raise @failure.Failure {
  let segments = self.main.part.split("/").map(s => s.to_owned()).to_array()
  ignore(segments.pop())
  let root = if segments.is_empty() { "" } else { segments.join("/") + "/" }
  for sequence in 0..<=self.budget.entries {
    let prefix = root + "odImport\{self.slide_sequence}-\{sequence}/"
    if !self.opc.names.keys().any(path => path.has_prefix(prefix.to_lower())) &&
      !self.parts
      .keys()
      .any(path => path.to_lower().has_prefix(prefix.to_lower())) &&
      !self.media
      .keys()
      .any(path => path.to_lower().has_prefix(prefix.to_lower())) {
      break prefix
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Imported part identities exhausted")
  }
}
