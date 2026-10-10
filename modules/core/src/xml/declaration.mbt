///|
/// Validates the declaration separately because the upstream reader guesses byte encoding from decoded text.
fn declaration(
  source : String,
  encoding : String,
  part : String,
) -> (String, Int, String) raise @failure.Failure {
  if !source.has_prefix("<?xml") ||
    source.length() <= 5 ||
    !(source[5] == ' ' ||
    source[5] == '\t' ||
    source[5] == '\r' ||
    source[5] == '\n') {
    return (source, 0, "")
  }
  guard source.find("?>") is Some(end) else {
    @failure.reject(
      "malformed-xml",
      "Unterminated XML declaration",
      part~,
      offset=0,
    )
  }
  let end = end + 2
  let reader = @parser.Reader::from_string(
    "<xml" + source[5:end - 2].to_owned() + "/>",
  )
  let event = reader.read_event() catch {
    @parser.At(error~, ..) =>
      @failure.reject("malformed-xml", error.to_string(), part~, offset=0)
  }
  guard event.kind is Empty(element) else {
    @failure.reject("malformed-xml", "Invalid XML declaration", part~, offset=0)
  }
  let attrs = element.attributes
  guard attrs.length() >= 1 && attrs.length() <= 3 && attrs[0].name == "version" else {
    @failure.reject(
      "malformed-xml",
      "XML version must come first",
      part~,
      offset=0,
    )
  }
  guard attrs[0].value == "1.0" else {
    @failure.reject(
      "unsupported-xml",
      "Only XML 1.0 is supported",
      part~,
      offset=0,
    )
  }
  let mut standalone = ""
  for i in 1..<attrs.length() {
    let attr = attrs[i]
    if attr.name == "encoding" && i == 1 {
      let value = attr.value.to_lower()
      guard value == encoding || (value == "utf-16" && encoding != "utf-8") else {
        @failure.reject(
          "unsupported-xml",
          "XML declaration conflicts with byte encoding",
          part~,
          offset=0,
        )
      }
    } else if attr.name == "standalone" &&
      (attr.value == "yes" || attr.value == "no") &&
      standalone.is_empty() {
      standalone = " standalone=\"" + attr.value + "\""
    } else {
      @failure.reject(
        "malformed-xml",
        "Invalid declaration attribute order or value",
        part~,
        offset=0,
      )
    }
  }
  // Declaration pseudo-attributes cannot contain character/entity references.
  guard !source[0:end].contains("&") else {
    @failure.reject(
      "malformed-xml",
      "Reference in XML declaration",
      part~,
      offset=0,
    )
  }
  let padding = StringBuilder()
  for i in 0..<end {
    padding.write_char(
      if source[i] == '\n' || source[i] == '\r' {
        source[i].to_char().unwrap()
      } else {
        ' '
      },
    )
  }
  (
    padding.to_string() + source[end:].to_owned(),
    end,
    "<?xml version=\"1.0\" encoding=\"UTF-8\"" + standalone + "?>",
  )
}
