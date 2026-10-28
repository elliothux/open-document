///|
let slide_number_text_reason = "Slide number fields are read-only"

///|
fn slide_number_field(source : Ref) -> Bool {
  simple_text_field(source) &&
  source.node.attribute("type").unwrap_or("").to_lower() == "slidenum"
}

///|
fn simple_text_field(source : Ref) -> Bool {
  let node = source.node
  let children = source.tree.children.get(node.id).unwrap_or([])
  node.uri == drawing_uri &&
  node.name == "fld" &&
  !node.attribute("id").unwrap_or("").is_empty() &&
  node.attribute("id").unwrap_or("").length() <= 128 &&
  node.text.trim().is_empty() &&
  node.attributes.all(a => a.uri.is_empty() && ["id", "type"].contains(a.name)) &&
  children.all(child => {
    child.uri == drawing_uri && ["rPr", "t"].contains(child.name)
  }) &&
  ["rPr", "t"].all(name => {
    children.filter(child => child.name == name).length() <= 1
  }) &&
  children
  .filter(child => child.name == "t")
  .all(child => {
    source.tree.children.get(child.id).unwrap_or([]).is_empty() &&
    child.attributes.all(a => {
      a.uri == "http://www.w3.org/XML/1998/namespace" &&
      a.name == "space" &&
      ["default", "preserve"].contains(a.value)
    })
  })
}

///|
fn presentation_first_number(main : Tree) -> Double raise @failure.Failure {
  let start = main
    .root("presentation")
    .attribute("firstSlideNum")
    .unwrap_or("1")
  guard !start.is_empty() && start.iter().all(c => c >= '0' && c <= '9') else {
    @failure.reject(
      "malformed-pptx",
      "Invalid first slide number",
      part=main.part,
    )
  }
  number(start, 0, 4294967295)
}

///|
fn presentation_number(
  main : Tree,
  index : Int32,
) -> String raise @failure.Failure {
  (presentation_first_number(main).to_int64() + index.to_int64()).to_string()
}

///|
fn numbered_slide(slide : Slide, number : String) -> Slide {
  if !slide.objects.any(object => {
      object.paragraphs.any(paragraph => {
        paragraph.runs.any(run => {
          run.text != number &&
          run.source.map(slide_number_field).unwrap_or(false)
        })
      })
    }) {
    return slide
  }
  {
    ..slide,
    objects: slide.objects.map(object => {
      ..object,
      paragraphs: object.paragraphs.map(paragraph => {
        ..paragraph,
        runs: paragraph.runs.map(run => {
          if run.source.map(slide_number_field).unwrap_or(false) {
            { ..run, text: number, parts: [(run.parts[0].0, number)], }
          } else {
            run
          }
        }),
      }),
    }),
  }
}
