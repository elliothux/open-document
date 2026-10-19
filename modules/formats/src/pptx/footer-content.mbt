///|
fn footer_body(
  source : Ref?,
  kind : String,
  text : String,
  field~ : String = "",
  language~ : String = "",
) -> String raise @failure.Failure {
  let body = source.bind(source => source.child("txBody", uri=presentation_uri))
  if body is Some(body) {
    guard body.node.end - body.node.start <= 1048576 else {
      @failure.reject("limit-exceeded", "Slide footer source exceeds budget")
    }
  }
  let first = body.bind(body => {
    body.tree
    .all(body.node.id, "p")
    .get(0)
    .map(node => { tree: body.tree, node, })
  })
  let properties = first
    .bind(first => first.child("pPr"))
    .map(item => item.tree.standalone_markup(item.tree.document, item.node.id))
    .unwrap_or(
      if source is None {
        "<a:pPr algn=\"\{if kind=="ftr" { "ctr" } else if kind=="sldNum" { "r" } else { "l" }}\"><a:buNone/></a:pPr>"
      } else {
        ""
      },
    )
  let run = first.bind(first => {
    first.tree.children
    .get(first.node.id)
    .unwrap_or([])
    .iter()
    .find_first(node => {
      ["r", "fld"].contains(node.name) && node.uri == drawing_uri
    })
    .map(node => { tree: first.tree, node, })
  })
  let style = run
    .bind(run => run.child("rPr"))
    .map(item => {
      let document = if language.is_empty() {
        item.tree.document
      } else {
        item.tree.document.edit_source([
          attribute_change(item, "lang", language),
        ]).0
      }
      item.tree.standalone_markup(document, item.node.id)
    })
    .unwrap_or(
      if source is None {
        "<a:rPr\{if language.is_empty() { "" } else { " lang=\"" + language + "\"" }} sz=\"1200\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:latin typeface=\"Arial\"/></a:rPr>"
      } else if !language.is_empty() {
        "<a:rPr lang=\"\{language}\"/>"
      } else {
        ""
      },
    )
  let body_properties = body
    .bind(body => body.child("bodyPr"))
    .map(item => item.tree.standalone_markup(item.tree.document, item.node.id))
    .unwrap_or(
      "<a:bodyPr lIns=\"0\" rIns=\"0\" tIns=\"0\" bIns=\"0\" anchor=\"ctr\"><a:normAutofit/></a:bodyPr>",
    )
  let list = body
    .bind(body => body.child("lstStyle"))
    .map(item => item.tree.standalone_markup(item.tree.document, item.node.id))
    .unwrap_or("<a:lstStyle/>")
  let output = StringBuilder()
  let mut units = body_properties.length().to_int64() +
    list.length().to_int64() +
    256
  guard units <= 1048576L else {
    @failure.reject("limit-exceeded", "Slide footer source exceeds budget")
  }
  output.write_string(
    "<p:txBody xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\">\{body_properties}\{list}",
  )
  for line in text.split("\n") {
    units += properties.length().to_int64() +
      line.length().to_int64() * 6 +
      line.split("\u2028").count().to_int64() *
      (style.length().to_int64() + 128)
    guard units <= 1048576L else {
      @failure.reject("limit-exceeded", "Slide footer source exceeds budget")
    }
    output.write_string("<a:p>\{properties}")
    if kind == "sldNum" || !field.is_empty() {
      let field_id = if kind == "dt" {
        if run is Some(item) && simple_text_field(item) {
          item.node.attribute("id").unwrap_or("new")
        } else {
          "new"
        }
      } else {
        "new"
      }
      let field_type = if kind == "sldNum" { "slidenum" } else { field }
      output.write_string(
        "<a:fld id=\"\{xml_attribute(field_id)}\" type=\"\{field_type}\">\{style}<a:t>\{@xml.escape_text(text)}</a:t></a:fld>",
      )
    } else {
      output.write_string(generated_text(line.to_owned(), "a:", style))
    }
    output.write_string("</a:p>")
  }
  output.write_string("</p:txBody>")
  output.to_string()
}

///|
fn footer_copy(
  markup : String,
  part : String,
  reserved : Map[String, Bool],
  next : Int64,
  budget : @archive.Budget,
) -> (@xml.Document, Int64) raise @failure.Failure {
  guard markup.length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Slide footer source exceeds budget")
  }
  let document = @xml.Document::parse(
    @utf8.encode(markup),
    part,
    budget.xml_depth,
    budget.entry_bytes,
  )
  guard document
    .nodes()
    .all(node => node.attributes.all(a => a.uri != relationship_uri)) else {
    @failure.reject(
      "protected-content", "Footer template relationships require copying support",
    )
  }
  copy_slide_objects(Tree::new(part, document), part, reserved, next, budget)
}

///|
fn Session::footer_template(
  self : Session,
  slide : Slide,
  kind : String,
) -> Ref? raise @failure.Failure {
  let layout = load_tree(
    self.opc,
    self.cache,
    slide_layout(self.opc, slide.tree.part, self.parts).unwrap(),
    parts=self.parts,
  )
  let master = load_tree(
    self.opc,
    self.cache,
    relation(self.opc, layout.part, "slideMaster", parts=self.parts).unwrap(),
    parts=self.parts,
  )
  for tree in [layout, master] {
    let candidates = tree.children
      .get(shape_tree(tree).id)
      .unwrap_or([])
      .filter(node => {
        placeholder({ tree, node, }).map(ph => ph.0 == kind).unwrap_or(false)
      })
    guard candidates.length() <= 1 else {
      @failure.reject(
        "protected-content", "Ambiguous footer template placeholders",
      )
    }
    if candidates is [node] {
      return Some({ tree, node, })
    }
  }
  None
}

///|
fn Session::footer_shape(
  self : Session,
  kind : String,
  content : String,
) -> String {
  let column = if kind == "dt" {
    0.04
  } else if kind == "ftr" {
    0.36
  } else {
    0.68
  }
  let x = (self.width * column * 12700).round().to_int64()
  let y = (self.height * 0.90 * 12700).round().to_int64()
  let width = (self.width * 0.28 * 12700).round().to_int64()
  let height = (self.height * 0.06 * 12700).round().to_int64()
  "<p:sp xmlns:p=\"\{presentation_uri}\" xmlns:a=\"\{drawing_uri}\"><p:nvSpPr><p:cNvPr id=\"1\" name=\"\{kind}\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr><p:ph type=\"\{kind}\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\{x}\" y=\"\{y}\"/><a:ext cx=\"\{width}\" cy=\"\{height}\"/></a:xfrm><a:prstGeom prst=\"rect\"/><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>\{content}</p:sp>"
}
