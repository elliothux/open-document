///|
#derive(ToJson)
priv struct PdfQueryPage {
  id : String
  object : Int32
  generation : Int32
  width : Double
  height : Double
  rotate : Int32
}

///|
fn SourcePage::query_page(self : SourcePage) -> PdfQueryPage {
  {
    id: self.id,
    object: self.number,
    generation: self.generation,
    width: self.width,
    height: self.height,
    rotate: self.rotate,
  }
}

///|
#derive(ToJson)
priv struct PdfQueryAnnotation {
  id : String
  page : String
  kind : String
  text : String
  readOnlyReason : String
}

///|
#derive(ToJson)
priv struct PdfQueryState {
  revision : Int32
  page : String
  pages : Array[PdfQueryPage]
  annotations : Array[PdfQueryAnnotation]
  fields : Array[PdfQueryField]
  readOnlyReason : String
  pageOrderReason : String
  canUndo : Bool
  canRedo : Bool
  historyBytes : Int32
  modified : Bool
  diagnostics : Array[String]
}

///|
pub fn PdfSession::query(self : PdfSession) -> Json raise @failure.Failure {
  self.check(self.revision)
  pdf_bound(self.budget, () => {
    let annotations : Array[PdfQueryAnnotation] = []
    for page in (if self.ranged is None { self.pages } else { [] }) {
      for
        index, reference in annotation_refs(
          self.document,
          self.document.lookup_object_or_null(page.number),
        ) {
        let object = resolve(self.document, reference)
        if is_name(raw(object, "Subtype"), "Popup") {
          continue
        }
        let contents = get(self.document, object, "Contents")
        let id = match reference {
          PdfIndirect(n) => "\{n}:\{self.generations.get(n).unwrap_or(0)}"
          _ => "\{page.id}:direct:\{index}"
        }
        let subtype = match get(self.document, object, "Subtype") {
          PdfNameObject(name) => @utf8.decode_lossy(name.bytes())[1:].to_owned()
          _ => "Unknown"
        }
        check_pdf_text(subtype)
        let text = if contents == @syntax.PdfNull {
          ""
        } else {
          pdf_text_string(contents)
        }
        check_pdf_text(text)
        let reason = if reference is PdfIndirect(_) {
          annotation_reason(self.document, object)
        } else {
          "Direct annotation is protected"
        }
        guard annotations.length() < 4096 else {
          @failure.reject("limit-exceeded", "PDF annotations exceed budget")
        }
        annotations.push({
          id,
          page: page.id,
          kind: subtype,
          text,
          readOnlyReason: reason,
        })
      }
    }
    let order_reason = if self.ranged is None {
      self.page_order_reason()
    } else {
      self.readOnlyReason
    }
    let pages = self.pages.map(SourcePage::query_page)
    let state : PdfQueryState = {
      revision: self.revision,
      page: self.current,
      pages,
      annotations,
      fields: if self.ranged is None {
        self.fields().map(field_query)
      } else {
        []
      },
      readOnlyReason: self.readOnlyReason,
      pageOrderReason: order_reason,
      canUndo: !self.undo.is_empty(),
      canRedo: !self.redo.is_empty(),
      historyBytes: self.historyBytes,
      modified: self.stateId != 0,
      diagnostics: if self.readOnlyReason.is_empty() {
        []
      } else {
        [self.readOnlyReason]
      },
    }
    ToJson::to_json(state)
  })
}
