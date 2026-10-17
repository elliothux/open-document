///|
pub(all) struct FooterContent {
  date : String?
  footer : String?
  number : Bool
}

///|
fn Slide::footer_objects(
  slide : Slide,
) -> Map[String, Object] raise @failure.Failure {
  guard slide.read_only.is_empty() else {
    @failure.reject("protected-content", slide.read_only)
  }
  let result : Map[String, Object] = Map([])
  for object in slide.objects {
    if object.source.tree.part != slide.tree.part {
      continue
    }
    if placeholder(object.source) is Some((kind, _)) &&
      ["dt", "ftr", "sldNum"].contains(kind) {
      guard !result.contains(kind) &&
        object.kind == "shape" &&
        object.parent.is_empty() &&
        object.source.node.parent == shape_tree(slide.tree).id &&
        object.read_only.is_empty() &&
        (
          object.text_reason.is_empty() ||
          (kind == "sldNum" && object.text_reason == slide_number_text_reason)
        ) &&
        object.text().length() <= 4096 else {
        @failure.reject(
          "protected-content", "Complex or protected slide footer content requires editing support",
        )
      }
      if object.source.child("txBody", uri=presentation_uri) is Some(body) {
        let markup = source_xml(body)
        guard !markup.contains("<!--") && !markup.contains("<?") else {
          @failure.reject(
            "protected-content", "Annotated slide footer text is protected",
          )
        }
      }
      result[kind] = object
    }
  }
  result
}

///|
fn Session::footer_query(self : Session, slide : Slide) -> Json {
  try {
    let objects = slide.footer_objects()
    let reason = self.slide_visibility_reason()
    {
      "date": objects
      .get("dt")
      .map(object => Json(object.text()))
      .unwrap_or(Json::null()),
      "footer": objects
      .get("ftr")
      .map(object => Json(object.text()))
      .unwrap_or(Json::null()),
      "number": objects.contains("sldNum"),
      "reason": reason,
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        "date": Json::null(),
        "footer": Json::null(),
        "number": false,
        "reason": message,
      }
  }
}

///|
fn footer_text(value : String?) -> String? raise @failure.Failure {
  value.map(text => {
    let text = text
      .replace_all(old="\r\n", new="\n")
      .replace_all(old="\r", new="\n")
    guard text.length() <= 4096 &&
      text.split("\n").count() <= 256 &&
      @xml.valid_text(text) else {
      @failure.reject("invalid-text", "Invalid or excessive slide footer text")
    }
    text
  })
}
