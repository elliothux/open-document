///|
/// Reuses untouched compressed records; changed entries are stored without compression.
pub fn Package::validate_replacements(
  self : Package,
  replacements : Map[String, Bytes],
) -> Int raise @failure.Failure {
  self.check()
  for name, bytes in replacements {
    guard self.index.contains(name) else {
      @failure.reject("missing-part", "Cannot replace missing entry", part=name)
    }
    guard bytes.length() <= self.budget.entry_bytes else {
      @failure.reject(
        "limit-exceeded",
        "Replacement entry exceeds budget",
        part=name,
      )
    }
  }
  let mut size = 22
  let mut total = 0
  for name, entry in self.index {
    let bytes = replacements.get(name)
    let local_size = match bytes {
      Some(bytes) => {
        let header = 30 + @utf8.encode(name).length()
        guard bytes.length() <= self.budget.output_bytes - header else {
          @failure.reject(
            "limit-exceeded",
            "Replacement output budget exceeded",
            part=name,
          )
        }
        header + bytes.length()
      }
      None => entry.local_end - entry.local_start
    }
    let decoded = match bytes {
      Some(bytes) => bytes.length()
      None => entry.decoded
    }
    guard decoded <= self.budget.total_bytes - total else {
      @failure.reject(
        "limit-exceeded",
        "Saved decode budget exceeded",
        part=name,
      )
    }
    total += decoded
    guard local_size <= self.budget.output_bytes - size &&
      entry.central_size <= self.budget.output_bytes - size - local_size else {
      @failure.reject("limit-exceeded", "Output budget exceeded", part=name)
    }
    size += local_size + entry.central_size
  }
  guard size <= self.budget.output_bytes else {
    @failure.reject("limit-exceeded", "Output budget exceeded")
  }
  size
}

///|
pub fn Package::save(
  self : Package,
  replacements : Map[String, Bytes],
) -> Bytes raise @failure.Failure {
  let size = self.validate_replacements(replacements)
  // Saving verifies integrity even for entries not queried by the caller.
  for name, _ in self.index {
    ignore(self.read(name))
  }
  let out = FixedArray::make(size, b'\x00')
  let offsets : Map[String, Int] = Map([])
  let mut cursor = 0
  for name, entry in self.index {
    offsets[name] = cursor
    if replacements.get(name) is Some(bytes) {
      let encoded = @utf8.encode(name)
      put32(out, cursor, 0x04034b50U)
      put16(out, cursor + 4, 20)
      put16(out, cursor + 6, 0x800)
      put16(out, cursor + 10, u16(self.source, entry.central + 12))
      put16(out, cursor + 12, u16(self.source, entry.central + 14))
      put32(out, cursor + 14, @checksum.crc32(bytes))
      put32(out, cursor + 18, bytes.length().reinterpret_as_uint())
      put32(out, cursor + 22, bytes.length().reinterpret_as_uint())
      put16(out, cursor + 26, encoded.length())
      out.blit_from_bytesview(cursor + 30, encoded)
      out.blit_from_bytesview(cursor + 30 + encoded.length(), bytes)
      cursor += 30 + encoded.length() + bytes.length()
    } else {
      let raw = span(
        self.source,
        entry.local_start,
        entry.local_end - entry.local_start,
      )
      out.blit_from_bytesview(cursor, raw)
      cursor += raw.length()
    }
  }
  let central_start = cursor
  for name, entry in self.index {
    out.blit_from_bytesview(
      cursor,
      span(self.source, entry.central, entry.central_size),
    )
    put32(out, cursor + 42, offsets[name].reinterpret_as_uint())
    if replacements.get(name) is Some(bytes) {
      put16(out, cursor + 6, 20)
      put16(out, cursor + 8, 0x800)
      put16(out, cursor + 10, 0)
      put32(out, cursor + 16, @checksum.crc32(bytes))
      put32(out, cursor + 20, bytes.length().reinterpret_as_uint())
      put32(out, cursor + 24, bytes.length().reinterpret_as_uint())
    }
    cursor += entry.central_size
  }
  put32(out, cursor, 0x06054b50U)
  put16(out, cursor + 8, self.index.length())
  put16(out, cursor + 10, self.index.length())
  put32(out, cursor + 12, (cursor - central_start).reinterpret_as_uint())
  put32(out, cursor + 16, central_start.reinterpret_as_uint())
  Bytes::from_array(out)
}
