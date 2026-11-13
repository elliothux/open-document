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
  self.start_save(replacements, removed~).finish()
}

///|
/// Starts a ZIP write whose source reads can be resumed after a missing range.
pub fn Package::start_save(
  self : Package,
  replacements : Map[String, Bytes],
  removed~ : Array[String] = [],
) -> Writer raise @failure.Failure {
  let size = self.validate_changes(replacements, removed~)
  let entries = self.names()
  for name, _ in replacements {
    if !self.index.contains(name) {
      entries.push(name)
    }
  }
  {
    archive: self,
    originals: self.names().filter(name => !self.cache.contains(name)),
    entries: entries.filter(name => !removed.contains(name)),
    replacements: replacements.copy(),
    verified: self.inflated,
    verify_index: 0,
    verifier: None,
    out: FixedArray::make(size, b'\x00'),
    offsets: FixedArray::make(entries.length() - removed.length(), 0),
    cursor: 0,
    local_index: 0,
    local_offset: 0,
    central_start: -1,
    central_index: 0,
    finished: false,
  }
}

///|
pub struct Writer {
  priv archive : Package
  priv originals : Array[String]
  priv entries : Array[String]
  priv replacements : Map[String, Bytes]
  priv mut verified : Int32
  priv mut verify_index : Int32
  priv mut verifier : EntryVerifier?
  priv out : FixedArray[Byte]
  priv offsets : FixedArray[Int32]
  priv mut cursor : Int32
  priv mut local_index : Int32
  priv mut local_offset : Int32
  priv mut central_start : Int32
  priv mut central_index : Int32
  priv mut finished : Bool
}

///|
/// Completes the archive. After each checkpoint the host may discard supplied
/// source bytes. Resume after a missing read, and discard the writer on errors.
pub fn Writer::finish(
  self : Writer,
  checkpoint~ : () -> Unit = () => (),
) -> Bytes raise @failure.Failure {
  guard !self.finished else {
    @failure.reject("invalid-operation", "ZIP writer already finished")
  }
  self.archive.check()
  self.verify(checkpoint)
  while self.local_index < self.entries.length() {
    self.write_local(checkpoint)
    self.local_index += 1
    self.local_offset = 0
    checkpoint()
  }
  if self.central_start < 0 {
    self.central_start = self.cursor
  }
  while self.central_index < self.entries.length() {
    self.write_central()
    self.central_index += 1
    checkpoint()
  }
  let { out, cursor, central_start, entries, .. } = self
  put32(out, cursor, 0x06054b50U)
  put16(out, cursor + 8, entries.length())
  put16(out, cursor + 10, entries.length())
  put32(out, cursor + 12, (cursor - central_start).reinterpret_as_uint())
  put32(out, cursor + 16, central_start.reinterpret_as_uint())
  self.finished = true
  Bytes::from_array(out)
}

///|
fn Writer::write_local(
  self : Writer,
  checkpoint : () -> Unit,
) -> Unit raise @failure.Failure {
  let { archive, out, cursor, local_index, .. } = self
  let name = self.entries[local_index]
  let entry = archive.index.get(name)
  if self.local_offset == 0 {
    self.offsets[local_index] = cursor
  }
  if self.replacements.get(name) is Some(bytes) {
    let encoded = @utf8.encode(name)
    let timestamp = match entry {
      Some(entry) => archive.source.read(entry.central + 12, 4)
      None => b"\x00\x00\x21\x00"[:]
    }
    put32(out, cursor, 0x04034b50U)
    put16(out, cursor + 4, 20)
    put16(out, cursor + 6, 0x800)
    out.blit_from_bytesview(cursor + 10, timestamp)
    put32(out, cursor + 14, @checksum.crc32(bytes))
    put32(out, cursor + 18, bytes.length().reinterpret_as_uint())
    put32(out, cursor + 22, bytes.length().reinterpret_as_uint())
    put16(out, cursor + 26, encoded.length())
    out.blit_from_bytesview(cursor + 30, encoded)
    out.blit_from_bytesview(cursor + 30 + encoded.length(), bytes)
    self.cursor += 30 + encoded.length() + bytes.length()
  } else {
    let entry = entry.unwrap()
    for offset = entry.local_start + self.local_offset; offset < entry.local_end; {
      let length = (entry.local_end - offset).min(EntryChunkBytes)
      out.blit_from_bytesview(self.cursor, archive.source.read(offset, length))
      self.cursor += length
      self.local_offset += length
      checkpoint()
      continue offset + length
    }
  }
}

///|
fn Writer::write_central(self : Writer) -> Unit raise @failure.Failure {
  let { archive, out, cursor, central_index, .. } = self
  let name = self.entries[central_index]
  let central_size = if archive.index.get(name) is Some(entry) {
    out.blit_from_bytesview(
      cursor,
      archive.source.read(entry.central, entry.central_size),
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
  put32(out, cursor + 42, self.offsets[central_index].reinterpret_as_uint())
  if self.replacements.get(name) is Some(bytes) {
    put16(out, cursor + 6, 20)
    put16(out, cursor + 8, 0x800)
    put16(out, cursor + 10, 0)
    put32(out, cursor + 16, @checksum.crc32(bytes))
    put32(out, cursor + 20, bytes.length().reinterpret_as_uint())
    put32(out, cursor + 24, bytes.length().reinterpret_as_uint())
  }
  self.cursor += central_size
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
