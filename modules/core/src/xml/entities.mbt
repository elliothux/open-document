///|
/// Skips inert markup so literal DOCTYPE text in comments or CDATA is preserved.
fn reject_dtd(source : String, part : String) -> Unit raise @failure.Failure {
  for cursor = 0; cursor < source.length(); {
    guard source[cursor:].find("<") is Some(relative) else { break }
    let start = cursor + relative
    let rest = source[start:]
    let ending = if rest.has_prefix("<!--") {
      Some("-->")
    } else if rest.has_prefix("<![CDATA[") {
      Some("]]>")
    } else if rest.has_prefix("<?") {
      Some("?>")
    } else {
      None
    }
    if ending is Some(ending) {
      guard rest.find(ending) is Some(end) else { break }
      continue start + end + ending.length()
    }
    guard !rest.has_prefix("<!DOCTYPE") else {
      @failure.reject("unsupported-xml", "DTD is disabled", part~, offset=start)
    }
    continue start + 1
  }
}
