///|
pub(all) struct ImageResource {
  identity : String
  width : Int
  height : Int
  rgba : Bytes
}

///|
pub struct Images {
  entries : Map[String, ImageResource]
  mut retained : Int
}

///|
pub fn Images::new() -> Images {
  { entries: Map([]), retained: 0, }
}

///|
pub fn Images::add(
  self : Images,
  key : String,
  width : Int,
  height : Int,
  rgba : Bytes,
) -> Unit raise @failure.Failure {
  guard !key.is_empty() &&
    key.length() <= 256 &&
    width > 0 &&
    width <= 4096 &&
    height > 0 &&
    height <= 4096 &&
    width.to_int64() * height.to_int64() * 4 == rgba.length().to_int64() else {
    @failure.reject(
      "invalid-image", "Invalid image dimensions or RGBA byte length",
    )
  }
  let previous = self.entries
    .get(key)
    .map(image => image.rgba.length())
    .unwrap_or(0)
  guard previous > 0 || self.entries.length() < 256 else {
    @failure.reject("limit-exceeded", "Image count budget exceeded")
  }
  guard rgba.length() <= 16777216 - self.retained + previous else {
    @failure.reject("limit-exceeded", "Decoded image budget exceeded")
  }
  let identity = StringBuilder()
  identity <+ "\{width}x\{height}:"
  for byte in @crypto.sha256(rgba) {
    identity.write_char(
      "0123456789abcdef"[byte.to_int() >> 4].to_char().unwrap(),
    )
    identity.write_char(
      "0123456789abcdef"[byte.to_int() & 15].to_char().unwrap(),
    )
  }
  self.entries[key] = { identity: identity.to_string(), width, height, rgba, }
  self.retained += rgba.length() - previous
}

///|
pub fn Images::get(
  self : Images,
  key : String,
) -> ImageResource raise @failure.Failure {
  self.entries
  .get(key)
  .unwrap_or_error(
    @failure.Failure(
      code="missing-image",
      part=key,
      offset=-1,
      message="Missing decoded image: " + key,
    ),
  )
}

///|
pub fn Images::clear(self : Images) -> Unit {
  self.entries.clear()
  self.retained = 0
}

///|
pub fn Images::retain(self : Images, keys : Array[String]) -> Unit {
  for key in self.entries.keys().collect() {
    if !keys.contains(key) {
      self.retained -= self.entries[key].rgba.length()
      self.entries.remove(key)
    }
  }
}
