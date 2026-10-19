///|
fn check_media_input(
  kind : String,
  content_type : String,
  bytes : Bytes,
) -> String raise @failure.Failure {
  guard bytes.length() > 0 && bytes.length() <= 16777216 else {
    @failure.reject(
      "limit-exceeded", "Media input must contain 1 to 16777216 bytes",
    )
  }
  guard media_extension_for(kind, content_type) is Some(extension) else {
    @failure.reject(
      "invalid-operation", "Unsupported media kind or content type",
    )
  }
  // Container signatures do not prove codec support; the browser must decode before insertion.
  let valid = match extension {
    "wav" =>
      bytes.length() >= 44 && bytes[0:4] == b"RIFF" && bytes[8:12] == b"WAVE"
    "mp3" =>
      bytes.length() >= 4 &&
      (
        bytes[0:3] == b"ID3" ||
        (bytes[0] == 0xff && (bytes[1].to_int() & 0xe0) == 0xe0)
      )
    "webm" => bytes.length() >= 8 && bytes[0:4] == b"\x1a\x45\xdf\xa3"
    _ => bytes.length() >= 16 && bytes[4:8] == b"ftyp"
  }
  guard valid else {
    @failure.reject(
      "invalid-operation", "Media content does not match its declared container",
    )
  }
  extension
}
