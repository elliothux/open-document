///|
pub const FooterTextUnits : Int32 = 4096

///|
pub const FooterParagraphCount : Int32 = 256

///|
/// A fixed label or date format 1–13 with en-US, zh-CN or zh-TW language.
pub(all) enum FooterDate {
  Fixed(String)
  Automatic(Int32, String)
} derive(Eq)

///|
pub extend FooterDate with Eq::{equal, not_equal}

///|
pub(all) struct FooterContent {
  date : FooterDate?
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
          (kind == "sldNum" && object.text_reason == slide_number_text_reason) ||
          (kind == "dt" && object.text_reason == date_field_text_reason)
        ) &&
        object.text().length() <= FooterTextUnits else {
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
      if kind == "dt" {
        ignore(object.footer_date())
      }
      result[kind] = object
    }
  }
  result
}

///|
priv struct QueryFooter {
  content : FooterContent
  reason : String
}

///|
impl ToJson for FooterDate with fn to_json(self) {
  match self {
    Fixed(text) => Json(text)
    Automatic(format, language) => { "format": format, "language": language }
  }
}

///|
impl ToJson for QueryFooter with fn to_json(self) {
  {
    "date": nullable_json(self.content.date),
    "footer": nullable_json(self.content.footer),
    "number": self.content.number,
    "reason": self.reason,
  }
}

///|
fn Session::footer_query(self : Session, slide : Slide) -> QueryFooter {
  try {
    let objects = slide.footer_objects()
    let reason = self.slide_visibility_reason()
    {
      content: {
        date: objects.get("dt").map(Object::footer_date),
        footer: objects.get("ftr").map(Object::text),
        number: objects.contains("sldNum"),
      },
      reason,
    }
  } catch {
    @failure.Failure(message~, ..) =>
      {
        content: { date: None, footer: None, number: false, },
        reason: message,
      }
  }
}

///|
fn Object::footer_date(self : Object) -> FooterDate raise @failure.Failure {
  if self.text_reason.is_empty() {
    return Fixed(self.text())
  }
  if self.paragraphs is [paragraph] &&
    paragraph.runs is [run] &&
    run.date_field is Some((format, language)) {
    return Automatic(format, language)
  }
  @failure.reject(
    "protected-content", "Mixed date field content requires editing support",
  )
}

///|
fn footer_date(value : FooterDate?) -> FooterDate? raise @failure.Failure {
  value.map(date => {
    match date {
      Fixed(text) => Fixed(footer_text(Some(text)).unwrap())
      Automatic(format, language) => {
        guard format >= 1 &&
          format <= 13 &&
          ["en-US", "zh-CN", "zh-TW"].contains(language) else {
          @failure.reject(
            "invalid-operation", "Invalid automatic slide date format or language",
          )
        }
        date
      }
    }
  })
}

///|
fn footer_text(value : String?) -> String? raise @failure.Failure {
  value.map(text => {
    let text = text
      .replace_all(old="\r\n", new="\n")
      .replace_all(old="\r", new="\n")
    guard text.length() <= FooterTextUnits &&
      text.split("\n").count() <= FooterParagraphCount &&
      @xml.valid_text(text) else {
      @failure.reject("invalid-text", "Invalid or excessive slide footer text")
    }
    text
  })
}
