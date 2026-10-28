///|
/// Traverse candidate dictionary references without treating superseded, orphaned
/// source objects as live document relationships.
fn PdfTransaction::reachable_objects(
  self : PdfTransaction,
) -> Map[Int32, Bool] raise {
  let reachable : Map[Int32, Bool] = Map([])
  let pending : Array[@syntax.PdfObject] = [
    self.trailer,
    @syntax.PdfIndirect(self.session.document.root()),
  ]
  fn collect(value : @syntax.PdfObject, depth : Int32) -> Unit raise {
    @pdfcore.sdk_check(1)
    guard depth < 64 else {
      @failure.reject(
        "limit-exceeded", "Candidate relationship depth exceeds budget",
      )
    }
    match value {
      PdfIndirect(number) =>
        if !reachable.contains(number) {
          guard reachable.length() < self.session.budget.objects else {
            @failure.reject(
              "limit-exceeded", "Candidate relationships exceed object budget",
            )
          }
          reachable[number] = true
          pending.push(self.object(number))
        }
      PdfArray(items) =>
        for item in items {
          collect(item, depth + 1)
        }
      PdfDictionary(entries) =>
        for (_, value) in entries {
          collect(value, depth + 1)
        }
      PdfStreamObject(stream) => collect(stream.dictionary, depth + 1)
      _ => ()
    }
  }
  while pending.pop() is Some(value) {
    collect(value, 0)
  }
  reachable
}
