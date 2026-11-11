///|
pub struct OutputBytes {
  parts : Array[Bytes?]
}

///|
pub fn OutputBytes::new() -> OutputBytes {
  { parts: [], }
}

///|
pub fn OutputBytes::clear(self : OutputBytes) -> Unit {
  self.parts.clear()
}

///|
pub fn OutputBytes::add(self : OutputBytes, bytes : Bytes) -> Int32 {
  let slot = self.parts.length()
  self.parts.push(Some(bytes))
  slot
}

///|
pub fn OutputBytes::take(self : OutputBytes, slot : Int32) -> Bytes? {
  guard self.parts.get(slot) is Some(Some(bytes)) else { return None }
  self.parts[slot] = None
  Some(bytes)
}

///|
pub fn OutputBytes::take_string(self : OutputBytes, slot : Int32) -> String? {
  self
  .take(slot)
  .map(bytes => {
    let output = StringBuilder(size_hint=bytes.length() * 2)
    for byte in bytes {
      output.write_char(byte.to_int().unsafe_to_char())
    }
    output.to_string()
  })
}
