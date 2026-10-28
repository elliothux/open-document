///|
fn PdfSession::metadata_reason(self : PdfSession) -> String {
  if !self.readOnlyReason.is_empty() {
    return self.readOnlyReason
  }
  try {
    ignore(self.xmp_metadata())
    ""
  } catch {
    @failure.Failure(message~, ..) => message
  }
}

///|
pub fn PdfSession::metadata(self : PdfSession) -> Json raise @failure.Failure {
  self.check(self.revision)
  pdf_bound(self.budget, () => {
    let info = get(self.document, self.document.trailer_dict(), "Info")
    let fields : Map[String, Json] = Map([])
    let xmp = self.xmp_metadata() catch { _ => None }
    for key in ["Title", "Author", "Subject", "Keywords"] {
      let value = get(self.document, info, key)
      fields[key] = Json(
        if value == @syntax.PdfNull {
          match xmp {
            Some((_, _, leaves)) =>
              leaves.get(key).map(node => node.text).unwrap_or("")
            None => ""
          }
        } else {
          pdf_text_string(value)
        },
      )
    }
    {
      "revision": self.revision,
      "fields": fields,
      "readOnlyReason": self.metadata_reason(),
    }
  })
}

///|
pub fn PdfSession::set_metadata(
  self : PdfSession,
  revision : Int32,
  fields : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  guard self.metadata_reason().is_empty() else {
    @failure.reject("protected-content", self.metadata_reason())
  }
  let reference = raw(self.document.trailer_dict(), "Info")
  let mut info = if reference == @syntax.PdfNull {
    dict([])
  } else {
    resolve(self.document, reference).deep_copy()
  }
  for key, value in fields {
    guard ["Title", "Author", "Subject", "Keywords"].contains(key) &&
      value.length() <= 32767 else {
      @failure.reject(
        "invalid-operation", "Unknown or oversized PDF metadata field",
      )
    }
    check_pdf_text(value)
    info = info.with_entry(pdf_name(key), @syntax.PdfString(utf16_bytes(value)))
  }
  if fields.is_empty() {
    return self.query()
  }
  self.update_xmp(tx, fields)
  if reference is PdfIndirect(id) {
    tx.objects[id] = info
  } else {
    let added = tx.add(info)
    tx.trailer = tx.trailer.with_entry(pdf_name("Info"), added)
  }
  tx.commit(self.current)
}
