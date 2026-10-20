///|
pub(all) struct Guide {
  orientation : String
  position : Double
} derive(Eq)

///|
pub extend Guide with Eq::{equal, not_equal}

///|
fn Session::guide_properties(self : Session) -> Tree? raise @failure.Failure {
  let links = self
    .relationships()
    .filter(link => {
      link.owner == self.main.part &&
      link.kind == relationship_uri + "/viewProps"
    })
  guard links.length() <= 1 && links.all(link => !link.external) else {
    @failure.reject(
      "protected-content", "Ambiguous or external presentation view properties",
    )
  }
  links
  .get(0)
  .map(link => {
    guard image_content_type(self.opc, link.target, self.parts) ==
      Some(
        "application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml",
      ) else {
      @failure.reject(
        "protected-content", "Invalid presentation view properties content type",
      )
    }
    let tree = load_tree(self.opc, self.cache, link.target, parts=self.parts)
    ignore(tree.root("viewPr"))
    tree
  })
}

///|
fn guide_owner(tree : Tree) -> @xml.Node? raise @failure.Failure {
  tree
  .one(tree.root("viewPr").id, "slideViewPr", uri=presentation_uri)
  .map(view => tree.one(view.id, "cSldViewPr", uri=presentation_uri))
  .bind(value => value)
}

///|
fn read_guides(tree : Tree) -> (Bool, Array[Guide]) raise @failure.Failure {
  guard guide_owner(tree) is Some(owner) else { return (false, []) }
  let visible = flag(owner, "showGuides", default=false)
  guard tree.one(owner.id, "guideLst", uri=presentation_uri) is Some(list) else {
    return (visible, [])
  }
  custom_show_node(tree, list, "guideLst", [], ["guide"])
  let source = tree.document.source()[list.start:list.end]
  guard !source.contains("<!--") && !source.contains("<?") else {
    @failure.reject(
      "protected-content", "Guide annotations require editing support",
    )
  }
  let nodes = tree.all(list.id, "guide", uri=presentation_uri)
  guard nodes.length() <= 64 else {
    @failure.reject("limit-exceeded", "Presentation guides exceed 64")
  }
  let guides = nodes.map(node => {
    custom_show_node(tree, node, "guide", ["orient", "pos"], [])
    let orientation = node.attribute("orient").unwrap_or("vert")
    guard ["horz", "vert"].contains(orientation) else {
      @failure.reject("protected-content", "Unknown guide orientation")
    }
    // DrawingML guide positions are eighths of a point (1587.5 EMU).
    let position = number(
        node.attribute("pos").unwrap_or("0"),
        -2147483648,
        2147483647,
      ) /
      8
    { orientation, position, }
  })
  (visible, guides)
}

///|
fn Session::guides_query(self : Session) -> Json {
  try {
    let (visible, items) = self
      .guide_properties()
      .map(read_guides)
      .unwrap_or((false, []))
    if self.candidate.bind(candidate => candidate.guide) is Some(guide) {
      items[guide.index] = { ..items[guide.index], position: guide.position, }
    }
    {
      "visible": visible,
      "items": items.map(item => {
        let item : Json = {
          "orientation": item.orientation,
          "position": item.position,
        }
        item
      }),
      "reason": self.slide_visibility_reason(),
    }
  } catch {
    @failure.Failure(message~, ..) =>
      { "visible": false, "items": [], "reason": message }
  }
}

///|
fn guides_markup(guides : Array[Guide]) -> String {
  "<od:guideLst xmlns:od=\"\{presentation_uri}\">" +
  guides
  .map(guide => {
    "<od:guide orient=\"\{guide.orientation}\" pos=\"\{(guide.position * 8).round().to_int64()}\"/>"
  })
  .join("") +
  "</od:guideLst>"
}

///|
fn Session::set_guides(
  self : Session,
  visible : Bool,
  guides : Array[Guide],
) -> Json raise @failure.Failure {
  guard guides.length() <= 64 else {
    @failure.reject("limit-exceeded", "Presentation guides exceed 64")
  }
  for guide in guides {
    guard ["horz", "vert"].contains(guide.orientation) &&
      !guide.position.is_nan() &&
      !guide.position.is_inf() &&
      guide.position >= -268435456 &&
      guide.position <= 268435455.875 else {
      @failure.reject("invalid-operation", "Invalid presentation guide")
    }
  }
  let guides = guides.map(guide => {
    ..guide,
    position: (guide.position * 8).round() / 8,
  })
  let tree = self.guide_properties()
  let previous = tree.map(read_guides).unwrap_or((false, []))
  if previous.0 == visible && previous.1 == guides {
    return self.query()
  }
  let body = slide_view_markup(visible, guides)
  let changes : Array[@xml.SourceChange] = []
  if tree is Some(tree) {
    if guide_owner(tree) is Some(owner) {
      if previous.0 != visible {
        changes.push(
          attribute_change(
            { tree, node: owner, },
            "showGuides",
            if visible {
              "1"
            } else {
              "0"
            },
          ),
        )
      }
      if previous.1 != guides {
        if tree.one(owner.id, "guideLst", uri=presentation_uri) is Some(list) {
          changes.push({
            node: owner.id,
            offset: list.start - owner.start,
            length: list.end - list.start,
            xml: guides_markup(guides),
          })
        } else {
          changes.push(insertion(owner, guides_markup(guides)))
        }
      }
    } else {
      changes.push(insert_slide_view(tree, body))
    }
  }
  self.commit_view_properties(tree, changes, body)
}

///|
fn guide_size_changes(
  tree : Tree,
  sx : Double,
  sy : Double,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let (_, guides) = read_guides(tree)
  guard guide_owner(tree) is Some(owner) &&
    tree.one(owner.id, "guideLst", uri=presentation_uri) is Some(list) else {
    return []
  }
  tree
  .all(list.id, "guide", uri=presentation_uri)
  .mapi((index, node) => {
    let guide = guides[index]
    let position = (guide.position *
    8 *
    (if guide.orientation == "horz" { sy } else { sx })).round()
    guard position >= -2147483648 && position <= 2147483647 else {
      @failure.reject(
        "limit-exceeded", "Resized guide exceeds native coordinates",
      )
    }
    attribute_change({ tree, node, }, "pos", position.to_int64().to_string())
  })
}
