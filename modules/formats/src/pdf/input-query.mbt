///|
pub fn PdfSession::query(self : PdfSession) -> Json raise @failure.Failure {
  self.check(self.revision)
  pdf_bound(self.budget, () => {
    let annotations : Array[Json] = []
    for page in self.pages {
      for
        index, reference in annotation_refs(
          self.document,
          self.document.lookup_object_or_null(page.number),
        ) {
        let object = resolve(self.document, reference)
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
          annotation_reason(object)
        } else {
          "Direct annotation is protected"
        }
        guard annotations.length() < 4096 else {
          @failure.reject("limit-exceeded", "PDF annotations exceed budget")
        }
        annotations.push({
          "id": id,
          "page": page.id,
          "kind": subtype,
          "text": text,
          "readOnlyReason": reason,
        })
      }
    }
    let order_reason = self.page_order_reason()
    let pages : Array[Json] = self.pages.map(page => {
      "id": page.id,
      "object": page.number,
      "generation": page.generation,
      "width": page.width,
      "height": page.height,
      "rotate": page.rotate,
    })
    {
      "revision": self.revision,
      "page": self.current,
      "pages": pages,
      "annotations": annotations,
      "fields": self.fields().map(field_json),
      "readOnlyReason": self.readOnlyReason,
      "pageOrderReason": order_reason,
      "canUndo": !self.undo.is_empty(),
      "canRedo": !self.redo.is_empty(),
      "historyBytes": self.historyBytes,
      "modified": self.stateId != 0,
      "diagnostics": if self.readOnlyReason.is_empty() {
        []
      } else {
        [self.readOnlyReason]
      },
    }
  })
}
