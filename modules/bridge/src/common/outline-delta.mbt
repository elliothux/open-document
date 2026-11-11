///|
pub struct OutlineDelta {
  mut previous : Map[String, String]
  mut encoded : (Json, String)?
}

///|
pub fn OutlineDelta::new() -> OutlineDelta {
  { previous: Map([]), encoded: None, }
}

///|
pub fn OutlineDelta::clear(self : OutlineDelta) -> Unit {
  self.previous.clear()
  self.encoded = None
}

///|
pub fn OutlineDelta::encode(self : OutlineDelta, value : Json) -> Json {
  self.encoded = None
  guard value is Array(outlines) else { return value }
  let next : Map[String, String] = Map([])
  let encoded : Array[Json] = []
  for outline in outlines {
    guard outline is { "key": String(key), "path": String(path), .. } else {
      return value
    }
    next[key] = path
    encoded.push(
      if self.previous.get(key) == Some(path) {
        Json(key)
      } else {
        outline
      },
    )
  }
  self.previous = next
  Json::array(encoded)
}

///|
pub fn OutlineDelta::encode_string(self : OutlineDelta, value : Json) -> String {
  if self.encoded is Some((previous, encoded)) &&
    physical_equal(previous, value) {
    return encoded
  }
  let delta = self.encode(value)
  let encoded = delta.stringify()
  if delta is Array(entries) && entries.all(entry => entry is String(_)) {
    self.encoded = Some((value, encoded))
  }
  encoded
}

///|
pub fn OutlineDelta::drawing(self : OutlineDelta, value : Json) -> Json {
  if value is Object(fields) &&
    fields.get("regions") is Some(Array(_)) &&
    fields.get("outlines") is Some(outlines) {
    let copy = fields.copy()
    copy["outlines"] = self.encode(outlines)
    return Json::object(copy)
  }
  value
}
