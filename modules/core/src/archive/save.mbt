///|
/// Reuses untouched compressed records; changed entries are stored without compression.
pub fn Package::validate_changes(
  self : Package,
  replacements : Map[String, Bytes],
  removed~ : Array[String] = [],
) -> Int32 raise @failure.Failure {
  self.check()
  let names : Map[String, Bool] = Map([])
  for name in removed {
    guard self.index.contains(name) &&
      !names.contains(name) &&
      !replacements.contains(name) else {
      @failure.reject(
        "invalid-operation",
        "Invalid, duplicate or replaced removal entry",
        part=name,
      )
    }
    names[name] = true
  }
  let entries = self.names()
  for name, bytes in replacements {
    guard !name.is_empty() &&
      !name.contains("\u0000") &&
      name.length() <= 65535 &&
      @utf8.encode(name).length() <= 65535 else {
      @failure.reject("malformed-package", "Invalid entry name", part=name)
    }
    guard bytes.length() <= self.budget.entry_bytes else {
      @failure.reject(
        "limit-exceeded",
        "Replacement entry exceeds budget",
        part=name,
      )
    }
    if !self.index.contains(name) {
      guard entries.length() - removed.length() < self.budget.entries &&
        entries.length() - removed.length() < 65534 else {
        @failure.reject("limit-exceeded", "Saved entry count budget exceeded")
      }
      entries.push(name)
    }
  }
  guard entries.length() - removed.length() <= self.budget.entries &&
    entries.length() - removed.length() < 65535 else {
    @failure.reject("limit-exceeded", "Saved entry count budget exceeded")
  }
  let mut size = 22
  let mut total = 0
  for name in entries {
    if names.contains(name) {
      continue
    }
    let entry = self.index.get(name)
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
      None => {
        let entry = entry.unwrap()
        entry.local_end - entry.local_start
      }
    }
    let decoded = match bytes {
      Some(bytes) => bytes.length()
      None => entry.unwrap().decoded
    }
    guard decoded <= self.budget.total_bytes - total else {
      @failure.reject(
        "limit-exceeded",
        "Saved decode budget exceeded",
        part=name,
      )
    }
    total += decoded
    let central_size = match entry {
      Some(entry) => entry.central_size
      None => 46 + @utf8.encode(name).length()
    }
    guard local_size <= self.budget.output_bytes - size &&
      central_size <= self.budget.output_bytes - size - local_size else {
      @failure.reject("limit-exceeded", "Output budget exceeded", part=name)
    }
    size += local_size + central_size
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
  removed~ : Array[String] = [],
) -> Bytes raise @failure.Failure {
  let size = self.validate_changes(replacements, removed~)
  // Saving verifies integrity even for entries not queried by the caller.
  for name, _ in self.index {
    ignore(self.read(name))
  }
  let out = FixedArray::make(size, b'\x00')
  let offsets : Map[String, Int32] = Map([])
  let entries = self.names()
  for name, _ in replacements {
    if !self.index.contains(name) {
      entries.push(name)
    }
  }
  let mut cursor = 0
  for name in entries {
    if removed.contains(name) {
      continue
    }
    offsets[name] = cursor
    let entry = self.index.get(name)
    if replacements.get(name) is Some(bytes) {
      let encoded = @utf8.encode(name)
      put32(out, cursor, 0x04034b50U)
      put16(out, cursor + 4, 20)
      put16(out, cursor + 6, 0x800)
      if entry is Some(entry) {
        put16(out, cursor + 10, u16(self.source, entry.central + 12))
        put16(out, cursor + 12, u16(self.source, entry.central + 14))
      } else {
        put16(out, cursor + 12, 0x21)
      }
      put32(out, cursor + 14, @checksum.crc32(bytes))
      put32(out, cursor + 18, bytes.length().reinterpret_as_uint())
      put32(out, cursor + 22, bytes.length().reinterpret_as_uint())
      put16(out, cursor + 26, encoded.length())
      out.blit_from_bytesview(cursor + 30, encoded)
      out.blit_from_bytesview(cursor + 30 + encoded.length(), bytes)
      cursor += 30 + encoded.length() + bytes.length()
    } else {
      let entry = entry.unwrap()
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
  for name in entries {
    if removed.contains(name) {
      continue
    }
    let central_size = if self.index.get(name) is Some(entry) {
      out.blit_from_bytesview(
        cursor,
        span(self.source, entry.central, entry.central_size),
      )
      entry.central_size
    } else {
      let encoded = @utf8.encode(name)
      put32(out, cursor, 0x02014b50U)
      put16(out, cursor + 4, 20)
      put16(out, cursor + 14, 0x21)
      put16(out, cursor + 28, encoded.length())
      out.blit_from_bytesview(cursor + 46, encoded)
      46 + encoded.length()
    }
    put32(out, cursor + 42, offsets[name].reinterpret_as_uint())
    if replacements.get(name) is Some(bytes) {
      put16(out, cursor + 6, 20)
      put16(out, cursor + 8, 0x800)
      put16(out, cursor + 10, 0)
      put32(out, cursor + 16, @checksum.crc32(bytes))
      put32(out, cursor + 20, bytes.length().reinterpret_as_uint())
      put32(out, cursor + 24, bytes.length().reinterpret_as_uint())
    }
    cursor += central_size
  }
  put32(out, cursor, 0x06054b50U)
  put16(out, cursor + 8, entries.length() - removed.length())
  put16(out, cursor + 10, entries.length() - removed.length())
  put32(out, cursor + 12, (cursor - central_start).reinterpret_as_uint())
  put32(out, cursor + 16, central_start.reinterpret_as_uint())
  Bytes::from_array(out)
}

///|
/// Creates a ZIP from explicit entries using the same checked writer as saves.
pub fn Package::create(
  entries : Map[String, Bytes],
  budget : Budget,
) -> Package raise @failure.Failure {
  let empty = FixedArray::make(22, b'\x00')
  put32(empty, 0, 0x06054b50U)
  let source = Package::open(Bytes::from_array(empty), budget)
  defer source.close()
  Package::open(source.save(entries), budget)
}
