///|
fn Session::copy_objects(
  self : Session,
  dx : Double,
  dy : Double,
) -> (Array[@xml.SourceChange], Selection, Int64) raise @failure.Failure {
  guard self.selection.mode == "object" else {
    @failure.reject(
      "invalid-operation", "Object copying requires object selection",
    )
  }
  let slide = self.current()
  let checked = self.transform_objects(action="duplicate")
  let selected = self.selection.objects
  let objects = slide.objects.filter(object => selected.contains(object.id))
  let changes : Array[@xml.SourceChange] = []
  let mut units = 0
  for object in objects {
    let reason = self.object_edit_reason(object, "duplicate")
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    units += object.source.node.end - object.source.node.start
    guard units <= 2097152 else {
      @failure.reject("limit-exceeded", "Copied objects exceed history budget")
    }
    let geometry = object.geometry.unwrap()
    let inverse = object.source.parent_frame().inverse()
    let target = {
      ..geometry,
      x: geometry.x + inverse.a * dx + inverse.c * dy,
      y: geometry.y + inverse.b * dx + inverse.d * dy,
    }
    validate_object_box(
      target.x,
      target.y,
      target.width,
      target.height,
      object.preset == "line",
    )
    changes.append(transform_changes(object, target))
  }
  let (positioned, _) = slide.tree.document.edit_source(changes)
  let content = StringBuilder()
  content.write_string("<p:spTree xmlns:p=\"\{presentation_uri}\">")
  units = 0
  for object in objects {
    let markup = slide.tree.standalone_markup(positioned, object.source.node.id)
    units += markup.length()
    guard units <= 2097152 else {
      @failure.reject(
        "limit-exceeded", "Copied object namespaces exceed history budget",
      )
    }
    content.write_string(markup)
  }
  content.write_string("</p:spTree>")
  let source = @xml.Document::parse(
    @utf8.encode(content.to_string()),
    slide.tree.part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  // Reuse slide copying's identity and local-reference remapping for the selected subtrees.
  let (copied, next) = copy_slide_objects(
    Tree::new(slide.tree.part, source),
    slide.tree.part,
    self.reserved_object_identities(),
    self.object_sequence,
    self.budget,
  )
  let identities : Map[String, String] = Map([])
  let originals = source
    .nodes()
    .filter(node => node.uri == presentation_uri && node.name == "cNvPr")
  let copies = copied
    .nodes()
    .filter(node => node.uri == presentation_uri && node.name == "cNvPr")
  for index, node in originals {
    identities[slide.tree.part +
    "#" +
    source_identity(node.attribute("id").unwrap_or(""))] = slide.tree.part +
      "#" +
      source_identity(copies[index].attribute("id").unwrap_or(""))
  }
  let root = copied.nodes()[0]
  (
    [
      object_insertion(
        slide.tree,
        copied.source()[root.opening_end:root.closing_start].to_owned(),
        parent=Some(slide.tree.nodes[checked[0].source.node.parent]),
      ),
      ..self.copy_media_settings(slide, identities),
    ],
    {
      ..self.selection,
      objects: selected.map(id => identities[id]),
      object: identities[self.selection.object],
      anchor: 0,
      focus: 0,
    },
    next,
  )
}
