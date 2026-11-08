///|
fn empty_readonly_widget(
  document : @pdflite.PdfDocument,
  reference : @syntax.PdfObject,
  object : @syntax.PdfObject,
  fields : Array[FormField],
) -> Bool raise {
  guard reference is PdfIndirect(number) &&
    (
      raw(object, "MK") == @syntax.PdfNull ||
      raw(object, "MK") == @syntax.PdfDictionary([])
    ) &&
    raw(object, "BS") == @syntax.PdfNull &&
    raw(object, "Border") == @syntax.PdfNull else {
    return false
  }
  for field in fields {
    @pdfcore.sdk_check(field.widgets.length() + 1)
    if field.widgets.any(widget => widget.0 == number) {
      let kind = field.attributes.get("FT").unwrap_or(@syntax.PdfNull)
      let flags = field.attributes.get("Ff").map(integer).unwrap_or(0)
      let combo = is_name(kind, "Ch") && (flags & 131072) != 0
      guard (is_name(kind, "Tx") || combo) &&
        (flags & 1) != 0 &&
        !field.attributes.contains("RV") else {
        return false
      }
      if combo {
        let owner = resolve(document, @syntax.PdfIndirect(field.number))
        for key in ["I", "TI"] {
          if raw(owner, key) != @syntax.PdfNull ||
            raw(object, key) != @syntax.PdfNull {
            return false
          }
        }
      }
      // An empty, unpainted read-only control has no visible appearance to synthesize.
      match field.attributes.get("V") {
        None | Some(PdfNull) | Some(PdfString(b"")) => return true
        _ => return false
      }
    }
  }
  false
}
