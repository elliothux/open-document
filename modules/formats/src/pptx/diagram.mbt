///|
pub(all) struct DiagramSettings {
  template : String
  items : Array[String]
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
fn diagram_boxes(
  settings : DiagramSettings,
) -> Array[Geometry] raise @failure.Failure {
  let { template, items, x, y, width, height, } = settings
  guard ["process", "hierarchy", "cycle"].contains(template) &&
    items.length() >= (if template == "cycle" { 3 } else { 2 }) &&
    items.length() <= 16 &&
    items.all(item => item.length() <= 4096) &&
    items.fold(init=0, (sum, item) => sum + item.length()) <= 32767 else {
    @failure.reject("invalid-operation", "Invalid diagram template or labels")
  }
  validate_object_box(x, y, width, height, false)
  let count = items.length().to_double()
  let box_width = if template == "process" {
    width / (count * 1.25 - 0.25)
  } else if template == "hierarchy" {
    width / ((count - 1) * 1.25).max(1)
  } else {
    width / (count / 2).ceil().max(3)
  }
  let box_height = height /
    (if template == "cycle" { (count / 2).ceil().max(3) } else { 3 })
  items.mapi((index, _) => {
    let (left, top) = if template == "process" {
      (index.to_double() * box_width * 1.25, (height - box_height) / 2)
    } else if template == "hierarchy" {
      if index == 0 {
        ((width - box_width) / 2, 0.0)
      } else {
        (
          (index - 1).to_double() * (width - box_width) / (count - 2).max(1),
          height - box_height,
        )
      }
    } else {
      let angle = 2.0 * @math.PI * index.to_double() / count - @math.PI / 2
      (
        (width - box_width) / 2 * (1 + @math.cos(angle)),
        (height - box_height) / 2 * (1 + @math.sin(angle)),
      )
    }
    geometry_in_parent(
      (left * 12700).round() / 12700,
      (top * 12700).round() / 12700,
      (box_width * 12700).round() / 12700,
      (box_height * 12700).round() / 12700,
      0,
      false,
      false,
      @layout.Matrix::identity(),
    )
  })
}

///|
fn Session::insert_diagram(
  self : Session,
  settings : DiagramSettings,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let boxes = diagram_boxes(settings)
  let slide = self.current()
  let content = StringBuilder()
  let count = boxes.length()
  let edges = if settings.template == "cycle" { count } else { count - 1 }
  for index in 0..<edges {
    let first = if settings.template == "hierarchy" { 0 } else { index }
    let last = (index + 1) % count
    let a = boxes[first]
    let b = boxes[last]
    let dx = b.x + b.width / 2 - a.x - a.width / 2
    let dy = b.y + b.height / 2 - a.y - a.height / 2
    let (start_site, end_site) = if dx.abs() >= dy.abs() {
      if dx > 0 {
        (3, 1)
      } else {
        (1, 3)
      }
    } else if dy > 0 {
      (2, 0)
    } else {
      (0, 2)
    }
    let endpoint = fn(g : Geometry, node : Int, site : Int) -> ConnectorEnd {
      {
        x: g.x +
        (if site == 1 { 0 } else if site == 3 { g.width } else { g.width / 2 }),
        y: g.y +
        (if site == 0 {
          0
        } else if site == 2 {
          g.height
        } else {
          g.height / 2
        }),
        target: slide.tree.part + "#" + (node + 2).to_string(),
        site,
      }
    }
    content.write_string(
      connector_markup(
        (count + index + 2).to_string(),
        "straight",
        endpoint(a, first, start_site),
        endpoint(b, last, end_site),
      ).replace(old="</a:ln>", new="<a:tailEnd type=\"triangle\"/></a:ln>"),
    )
  }
  for index, box in boxes {
    content.write_string(
      object_markup(
        (index + 2).to_string(),
        "rect",
        box.x,
        box.y,
        box.width,
        box.height,
        settings.items[index],
      )
      .replace(old="anchor=\"t\"", new="anchor=\"ctr\"")
      .replace(old="<a:pPr>", new="<a:pPr algn=\"ctr\">"),
    )
  }
  let markup = group_markup(
    "1",
    settings.x,
    settings.y,
    settings.width,
    settings.height,
    content.to_string(),
  )
  let document = @xml.Document::parse(
    @utf8.encode(
      "<p:spTree xmlns:p=\"\{presentation_uri}\">\{markup}</p:spTree>",
    ),
    slide.tree.part,
    self.budget.xml_depth,
    self.budget.entry_bytes,
  )
  // Allocate every native identity and reference with the existing subtree-copy transaction.
  let (document, next) = copy_slide_objects(
    Tree::new(slide.tree.part, document),
    slide.tree.part,
    self.reserved_object_identities(),
    self.object_sequence,
    self.budget,
  )
  let tree = Tree::new(slide.tree.part, document)
  let group = tree.required(
    document.nodes()[0].id,
    "grpSp",
    uri=presentation_uri,
  )
  let identity = tree
    .required(
      tree.required(group.id, "nvGrpSpPr", uri=presentation_uri).id,
      "cNvPr",
      uri=presentation_uri,
    )
    .attribute("id")
    .unwrap()
  let (candidate, edit) = self.prepare(slide, [
    object_insertion(slide.tree, tree.standalone_markup(document, group.id)),
  ])
  for object in candidate.objects {
    if object.parent == slide.tree.part + "#" + identity &&
      object.kind == "shape" &&
      object.source.node.name == "sp" {
      let (_, _, diagnostic, _) = fit_text(
        object,
        object.geometry.unwrap(),
        probe,
        profile,
      )
      guard diagnostic.is_empty() else {
        @failure.reject("layout-overflow", diagnostic)
      }
    }
  }
  let identity = slide.tree.part + "#" + identity
  self.commit(
    candidate,
    edit,
    {
      ..self.selection,
      object: identity,
      objects: [identity],
      mode: "object",
      anchor: 0,
      focus: 0,
    },
    probe~,
    profile~,
  )
  self.object_sequence = next
  self.query()
}
