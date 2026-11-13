///|
pub(all) struct Budget {
  file_bytes : Int32
  entry_bytes : Int32
  total_bytes : Int32
  retained_bytes : Int32
  entries : Int32
  xml_depth : Int32
  output_bytes : Int32
}

///|
pub fn Budget::default() -> Budget {
  {
    file_bytes: 33554432,
    entry_bytes: 16777216,
    total_bytes: 134217728,
    retained_bytes: 33554432,
    entries: 4096,
    xml_depth: 128,
    output_bytes: 67108864,
  }
}

///|
struct Entry {
  compression : Int32
  crc : UInt32
  compressed : Int32
  decoded : Int32
  local_start : Int32
  local_end : Int32
  payload : Int32
  central : Int32
  central_size : Int32
}

///|
pub struct Package {
  mut source : Source
  index : Map[String, Entry]
  cache : Map[String, Bytes]
  budget : Budget
  mut inflated : Int32
  mut closed : Bool
}

///|
pub fn Package::open(
  source : Bytes,
  budget : Budget,
) -> Package raise @failure.Failure {
  let source = Source::memory(source)
  validate_budget(source.size, budget)
  guard source.size <= budget.retained_bytes else {
    @failure.reject("limit-exceeded", "Retained source budget exceeded")
  }
  Reader::begin(source, budget).finish()
}

///|
/// Opens a ZIP backed by a stable, random-access source. The reader receives
/// zero-based byte offsets and must return exactly the requested length.
/// The caller must keep the source available and unchanged until close.
pub fn Package::open_reader(
  size : Int32,
  read_at : (Int32, Int32) -> BytesView raise @failure.Failure,
  budget : Budget,
) -> Package raise @failure.Failure {
  Reader::open(size, read_at, budget).finish()
}

///|
fn validate_budget(
  size : Int32,
  budget : Budget,
) -> Unit raise @failure.Failure {
  for
    limit in [
      budget.file_bytes,
      budget.entry_bytes,
      budget.total_bytes,
      budget.retained_bytes,
      budget.entries,
      budget.xml_depth,
      budget.output_bytes,
    ] {
    guard limit >= 0 else {
      @failure.reject("invalid-budget", "Budgets must be nonnegative")
    }
  }
  guard size >= 0 else {
    @failure.reject("invalid-source", "Source size must be nonnegative")
  }
  guard size <= budget.file_bytes else {
    @failure.reject("limit-exceeded", "Package source budget exceeded")
  }
}

///|
pub struct Reader {
  priv source : Source
  priv budget : Budget
  priv central_start : Int32
  priv central : BytesView
  priv count : Int32
  priv index : Map[String, Entry]
  priv ranges : Array[(Int32, Int32)]
  priv mut cursor : Int32
  priv mut finished : Bool
}

///|
/// Reads the ZIP directory. The caller can resume local record checks with
/// `finish` if the byte source needs time to fetch a range.
pub fn Reader::open(
  size : Int32,
  read_at : (Int32, Int32) -> BytesView raise @failure.Failure,
  budget : Budget,
) -> Reader raise @failure.Failure {
  validate_budget(size, budget)
  Reader::begin({ size, read_at, }, budget)
}

///|
fn Reader::begin(
  source : Source,
  budget : Budget,
) -> Reader raise @failure.Failure {
  if source.size >= 512 &&
    source.read(0, 8) == b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" {
    @failure.reject(
      "unsupported-package",
      "OLE compound files are unsupported. This container is used by legacy Office files and encrypted OOXML packages.",
      offset=0,
    )
  }
  let (end, end_record) = source.end_record()
  guard u16(end_record, 4) == 0 &&
    u16(end_record, 6) == 0 &&
    u16(end_record, 8) == u16(end_record, 10) else {
    @failure.reject(
      "unsupported-package",
      "Multi-disk ZIP is unsupported",
      offset=end,
    )
  }
  let count = u16(end_record, 10)
  guard count != 65535 else {
    @failure.reject("unsupported-package", "ZIP64 is unsupported")
  }
  guard count <= budget.entries else {
    @failure.reject("limit-exceeded", "Entry count budget exceeded")
  }
  let central_size = size32(end_record, 12, base=end)
  let central_start = size32(end_record, 16, base=end)
  guard central_start <= end && central_size == end - central_start else {
    @failure.reject("malformed-package", "Invalid central directory range")
  }
  guard central_size <= budget.retained_bytes else {
    @failure.reject("limit-exceeded", "Central directory budget exceeded")
  }
  let central = source.read(central_start, central_size)
  {
    source,
    budget,
    central_start,
    central,
    count,
    index: Map([]),
    ranges: [],
    cursor: 0,
    finished: false,
  }
}

///|
/// Validates local records and returns a package exactly once. A read failure
/// leaves completed records in place so a host can supply a missing range.
pub fn Reader::finish(self : Reader) -> Package raise @failure.Failure {
  guard !self.finished else {
    @failure.reject("invalid-operation", "ZIP reader already finished")
  }
  let { source, budget, central_start, central, count, index, ranges, .. } = self
  let central_size = central.length()
  while index.length() < count {
    let cursor = self.cursor
    let record_start = central_start + cursor
    guard central_size - cursor >= 46 && u32(central, cursor) == 0x02014b50U else {
      @failure.reject(
        "malformed-package",
        "Invalid central record",
        offset=record_start,
      )
    }
    let flags = u16(central, cursor + 8)
    let compression = u16(central, cursor + 10)
    guard (flags & 0xf7f1) == 0 &&
      (compression == 0 || compression == 8) &&
      u16(central, cursor + 34) == 0 else {
      @failure.reject(
        "unsupported-package",
        "Encrypted ZIP, compression or flags unsupported",
        offset=record_start,
      )
    }
    let crc = u32(central, cursor + 16)
    let compressed = size32(central, cursor + 20, base=central_start)
    let decoded = size32(central, cursor + 24, base=central_start)
    guard compression != 0 || compressed == decoded else {
      @failure.reject(
        "malformed-package",
        "Stored entry sizes differ",
        offset=record_start,
      )
    }
    let name_size = u16(central, cursor + 28)
    let extra_size = u16(central, cursor + 30)
    let record_size = 46 + name_size + extra_size + u16(central, cursor + 32)
    guard record_size <= central_size - cursor else {
      @failure.reject(
        "malformed-package",
        "Central record exceeds directory",
        offset=record_start,
      )
    }
    let encoded_name = span(central, cursor + 46, name_size)
    let name = @utf8.decode(encoded_name) catch {
      _ =>
        @failure.reject(
          "malformed-package",
          "Invalid UTF-8 entry name",
          offset=record_start,
        )
    }
    guard !name.is_empty() && !index.contains(name) else {
      @failure.reject(
        "malformed-package",
        "Empty or duplicate entry name",
        part=name,
      )
    }
    if zip64_extra(
        central,
        cursor + 46 + name_size,
        extra_size,
        base=central_start,
      )
      is Some(_) {
      @failure.reject(
        "unsupported-package",
        "ZIP64 is unsupported",
        offset=record_start,
      )
    }
    let local_start = size32(central, cursor + 42, base=central_start)
    guard local_start <= central_start - 30 - name_size else {
      @failure.reject(
        "malformed-package",
        "Local header overlaps directory",
        part=name,
        offset=local_start,
      )
    }
    let header = source.read(local_start, 30 + name_size)
    guard u32(header, 0) == 0x04034b50U &&
      u16(header, 6) == flags &&
      u16(header, 8) == compression else {
      @failure.reject(
        "malformed-package",
        "Local/central metadata mismatch",
        part=name,
        offset=local_start,
      )
    }
    let local_name_size = u16(header, 26)
    guard local_name_size == name_size && header[30:] == encoded_name else {
      @failure.reject(
        "malformed-package",
        "Local/central name mismatch",
        part=name,
        offset=local_start,
      )
    }
    let local_extra = u16(header, 28)
    let extra_start = local_start + 30 + name_size
    guard local_extra <= central_start - extra_start &&
      compressed <= central_start - extra_start - local_extra else {
      @failure.reject(
        "malformed-package",
        "Entry overlaps directory",
        part=name,
      )
    }
    if zip64_extra(
        source.read(extra_start, local_extra),
        0,
        local_extra,
        base=extra_start,
      )
      is Some(sizes) {
      // Some writers repeat ZIP32 sizes in a local ZIP64 extra field.
      guard sizes.length() == 16 &&
        u32(sizes, 0) == decoded.reinterpret_as_uint() &&
        u32(sizes, 4) == 0U &&
        u32(sizes, 8) == compressed.reinterpret_as_uint() &&
        u32(sizes, 12) == 0U else {
        @failure.reject(
          "malformed-package",
          "Local ZIP64 sizes differ from the directory",
          part=name,
          offset=extra_start,
        )
      }
    }
    let payload = extra_start + local_extra
    let mut local_end = payload + compressed
    if (flags & 8) == 0 {
      guard u32(header, 14) == crc &&
        size32(header, 18, base=local_start) == compressed &&
        size32(header, 22, base=local_start) == decoded else {
        @failure.reject(
          "malformed-package",
          "Local/central sizes or CRC differ",
          part=name,
        )
      }
    } else {
      guard (u32(header, 14) == 0U || u32(header, 14) == crc) &&
        (
          u32(header, 18) == 0U ||
          size32(header, 18, base=local_start) == compressed
        ) &&
        (
          u32(header, 22) == 0U ||
          size32(header, 22, base=local_start) == decoded
        ) else {
        @failure.reject(
          "malformed-package",
          "Conflicting descriptor metadata",
          part=name,
        )
      }
      guard local_end <= central_start - 12 else {
        @failure.reject(
          "malformed-package",
          "Truncated data descriptor",
          part=name,
        )
      }
      let descriptor = source.read(
        local_end,
        (central_start - local_end).min(16),
      )
      let start = if u32(descriptor, 0) == crc &&
        u32(descriptor, 4) == compressed.reinterpret_as_uint() &&
        u32(descriptor, 8) == decoded.reinterpret_as_uint() {
        0
      } else {
        guard descriptor.length() == 16 && u32(descriptor, 0) == 0x08074b50U else {
          @failure.reject(
            "malformed-package",
            "Invalid data descriptor",
            part=name,
          )
        }
        4
      }
      guard u32(descriptor, start) == crc &&
        u32(descriptor, start + 4) == compressed.reinterpret_as_uint() &&
        u32(descriptor, start + 8) == decoded.reinterpret_as_uint() else {
        @failure.reject(
          "malformed-package",
          "Invalid data descriptor",
          part=name,
        )
      }
      local_end += start + 12
    }
    ranges.push((local_start, local_end))
    index[name] = {
      compression,
      crc,
      compressed,
      decoded,
      local_start,
      local_end,
      payload,
      central: record_start,
      central_size: record_size,
    }
    self.cursor += record_size
  }
  guard self.cursor == central_size else {
    @failure.reject("malformed-package", "Directory size/count mismatch")
  }
  ranges.sort_by((a, b) => a.0.compare(b.0))
  for i in 1..<ranges.length() {
    guard ranges[i].0 >= ranges[i - 1].1 else {
      @failure.reject("malformed-package", "Overlapping ZIP entries")
    }
  }
  self.finished = true
  { source, index, cache: Map([]), budget, inflated: 0, closed: false, }
}

///|
fn Package::check(self : Package) -> Unit raise @failure.Failure {
  guard !self.closed else {
    @failure.reject("closed-session", "Package is closed")
  }
}

///|
pub fn Package::names(self : Package) -> Array[String] raise @failure.Failure {
  self.check()
  self.index.keys().collect()
}

///|
pub fn Package::read(
  self : Package,
  name : String,
) -> Bytes raise @failure.Failure {
  self.check()
  if self.cache.get(name) is Some(bytes) {
    return bytes
  }
  guard self.index.get(name) is Some(entry) else {
    @failure.reject("missing-part", "Entry does not exist", part=name)
  }
  let ceiling = self.budget.entry_bytes.min(
    self.budget.total_bytes - self.inflated,
  )
  let decoded = self.source.read_checked(entry, ceiling, name)
  self.inflated += decoded.length()
  self.cache[name] = decoded
  decoded
}

///|
fn Source::read_checked(
  self : Source,
  entry : Entry,
  ceiling : Int32,
  name : String,
) -> Bytes raise @failure.Failure {
  guard entry.decoded <= ceiling else {
    @failure.reject(
      "limit-exceeded",
      "Entry or cumulative decode budget exceeded",
      part=name,
    )
  }
  let decoded = self.decode_entry(entry, ceiling, name)
  guard @checksum.crc32(decoded) == entry.crc else {
    @failure.reject(
      "malformed-package",
      "Entry size or CRC mismatch",
      part=name,
    )
  }
  decoded
}

///|
pub fn Package::decoded_bytes(self : Package) -> Int32 raise @failure.Failure {
  self.check()
  self.inflated
}

///|
pub fn Package::close(self : Package) -> Unit {
  self.closed = true
  self.source = Source::memory(b"")
  self.index.clear()
  self.cache.clear()
}
