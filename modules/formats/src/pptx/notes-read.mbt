///|
priv struct Notes {
  tree : Tree
  shape : Ref?
  paragraphs : Array[@xml.Node]
  text : String
}

///|
fn Session::read_notes(
  self : Session,
  slide : String,
) -> Notes? raise @failure.Failure {
  let links = self.relationships()
  let owned = links.filter(link => {
    link.owner == slide && link.kind == relationship_uri + "/notesSlide"
  })
  guard owned.length() <= 1 else {
    @failure.reject("protected-content", "Multiple notes owners are protected")
  }
  guard owned.get(0) is Some(link) else { return None }
  guard !link.external &&
    links
    .filter(l => {
      !l.external &&
      l.target == link.target &&
      l.kind == relationship_uri + "/notesSlide"
    })
    .length() ==
    1 else {
    @failure.reject(
      "protected-content", "External or shared notes are protected",
    )
  }
  let back = links.filter(l => {
    l.owner == link.target && l.kind == relationship_uri + "/slide"
  })
  guard back is [back] && !back.external && back.target == slide else {
    @failure.reject(
      "protected-content", "Notes must belong to the selected slide",
    )
  }
  let tree = Tree::new(link.target, self.part_document(link.target))
  ignore(tree.root("notes"))
  let shapes = shape_tree(tree)
  let bodies = tree
    .all(shapes.id, "sp", uri=presentation_uri)
    .filter(node => {
      placeholder({ tree, node, }).map(ph => ph.0 == "body").unwrap_or(false)
    })
  guard bodies.length() <= 1 else {
    @failure.reject(
      "protected-content", "Ambiguous notes body placeholders are protected",
    )
  }
  guard bodies.get(0) is Some(shape) else {
    return Some({ tree, shape: None, paragraphs: [], text: "", })
  }
  let body = tree.required(shape.id, "txBody", uri=presentation_uri)
  let paragraphs = tree.all(body.id, "p")
  guard paragraphs.length() <= 256 &&
    body.text.trim().is_empty() &&
    tree.children
    .get(body.id)
    .unwrap_or([])
    .all(n => {
      n.uri == drawing_uri && ["bodyPr", "lstStyle", "p"].contains(n.name)
    }) else {
    @failure.reject("protected-content", "Unknown notes text body is protected")
  }
  let lines : Array[String] = []
  let mut units = 0
  if paragraphs is [first, ..] {
    let source = tree.document.source()[first.start:paragraphs.last().unwrap().end]
    guard !source.contains("<!--") && !source.contains("<?") else {
      @failure.reject("protected-content", "Opaque notes text is protected")
    }
  }
  for paragraph in paragraphs {
    let source = tree.document.source()[paragraph.start:paragraph.end]
    guard !source.contains("<!--") &&
      !source.contains("<?") &&
      paragraph.attributes.is_empty() &&
      paragraph.text.trim().is_empty() else {
      @failure.reject("protected-content", "Opaque notes text is protected")
    }
    let line = StringBuilder()
    for atom in tree.children.get(paragraph.id).unwrap_or([]) {
      guard atom.uri == drawing_uri else {
        @failure.reject("protected-content", "Unknown notes text is protected")
      }
      match atom.name {
        "pPr" | "endParaRPr" => ()
        "br" => {
          guard atom.attributes.is_empty() &&
            atom.text.trim().is_empty() &&
            tree.children
            .get(atom.id)
            .unwrap_or([])
            .all(n => n.uri == drawing_uri && n.name == "rPr") else {
            @failure.reject(
              "protected-content", "Unknown notes break content is protected",
            )
          }
          line.write_string("\u2028")
        }
        "r" => {
          guard atom.attributes.is_empty() &&
            atom.text.trim().is_empty() &&
            tree.children
            .get(atom.id)
            .unwrap_or([])
            .all(n => n.uri == drawing_uri && ["rPr", "t"].contains(n.name)) else {
            @failure.reject(
              "protected-content", "Unknown notes text atom is protected",
            )
          }
          let text = tree.required(atom.id, "t")
          guard tree.children.get(text.id).unwrap_or([]).is_empty() &&
            text.attributes.all(a => {
              a.uri == "http://www.w3.org/XML/1998/namespace" &&
              a.name == "space"
            }) else {
            @failure.reject(
              "protected-content", "Unknown notes text content is protected",
            )
          }
          line.write_string(text.text)
        }
        _ =>
          @failure.reject(
            "protected-content", "Notes fields and unknown text nodes are protected",
          )
      }
    }
    let text = line.to_string()
    units += text.length() + (if lines.is_empty() { 0 } else { 1 })
    guard text.length() <= 4096 && units <= 32767 else {
      @failure.reject("limit-exceeded", "Notes exceed text budget")
    }
    lines.push(text)
  }
  Some({
    tree,
    shape: Some({ tree, node: shape, }),
    paragraphs,
    text: lines.join("\n"),
  })
}

///|
fn Session::notes_query(self : Session, slide : String) -> Json {
  try {
    let notes = self.read_notes(slide)
    {
      "text": notes.map(n => n.text).unwrap_or(""),
      "reason": self.slide_visibility_reason(),
    }
  } catch {
    @failure.Failure(message~, ..) => { "text": "", "reason": message }
  }
}

///|
fn notes_paragraphs(
  notes : Notes,
  text : String,
) -> String raise @failure.Failure {
  let tree = notes.tree
  let first = notes.paragraphs.get(0)
  let prefix = first
    .map(n => n.qualified[:n.qualified.length() - 1].to_owned())
    .unwrap_or("a:")
  let opening = first
    .map(n => {
      let source = tree.document.source()
      if n.empty {
        source[n.start:n.opening_end - 2].to_owned() + ">"
      } else {
        source[n.start:n.opening_end].to_owned()
      }
    })
    .unwrap_or("<a:p xmlns:a=\"\{drawing_uri}\">")
  let properties = first
    .bind(n => tree.one(n.id, "pPr"))
    .map(n => source_xml({ tree, node: n, }))
    .unwrap_or("")
  let ending = first
    .bind(n => tree.one(n.id, "endParaRPr"))
    .map(n => source_xml({ tree, node: n, }))
    .unwrap_or("")
  let style = first
    .bind(n => tree.all(n.id, "r").get(0))
    .bind(n => tree.one(n.id, "rPr"))
    .map(n => tree.standalone_markup(tree.document, n.id))
    .unwrap_or("")
  let lines = text.split("\n").to_array()
  let runs = lines.length() + text.split("\u2028").count() - 1
  guard lines.length().to_int64() *
    (opening.length() + properties.length() + ending.length() + 64).to_int64() +
    runs.to_int64() * (style.length() + prefix.length() * 5 + 80).to_int64() +
    text.length().to_int64() * 6 <=
    2097152L else {
    @failure.reject("limit-exceeded", "Generated notes exceed source budget")
  }
  lines
  .map(line => {
    opening +
    properties +
    generated_text(line.to_owned(), prefix, style) +
    ending +
    "</\{prefix}p>"
  })
  .join("")
}
