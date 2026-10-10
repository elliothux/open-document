///|
pub(all) struct Budget {
  file_bytes : Int
  entry_bytes : Int
  total_bytes : Int
  retained_bytes : Int
  entries : Int
  xml_depth : Int
  output_bytes : Int
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
  compression : Int
  crc : UInt
  compressed : Int
  decoded : Int
  local_start : Int
  local_end : Int
  payload : Int
  central : Int
  central_size : Int
}

///|
pub struct Package {
  mut source : Bytes
  index : Map[String, Entry]
  cache : Map[String, Bytes]
  budget : Budget
  mut inflated : Int
  mut closed : Bool
}

///|
pub fn Package::open(
  source : Bytes,
  budget : Budget,
) -> Package raise @failure.Failure {
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
  guard source.length() <= budget.file_bytes &&
    source.length() <= budget.retained_bytes else {
    @failure.reject(
      "limit-exceeded", "Package or retained source budget exceeded",
    )
  }
  let floor = (source.length() - 22 - 65535).max(0)
  let end = for cursor = source.length() - 22
                cursor >= floor
                cursor = cursor - 1 {
    if u32(source, cursor) == 0x06054b50U &&
      u16(source, cursor + 20) == source.length() - cursor - 22 {
      break cursor
    }
  } nobreak {
    -1
  }
  guard end >= floor else {
    @failure.reject("malformed-package", "Missing ZIP end record")
  }
  guard u16(source, end + 4) == 0 &&
    u16(source, end + 6) == 0 &&
    u16(source, end + 8) == u16(source, end + 10) else {
    @failure.reject(
      "unsupported-package",
      "Multi-disk ZIP is unsupported",
      offset=end,
    )
  }
  let count = u16(source, end + 10)
  guard count != 65535 else {
    @failure.reject("unsupported-package", "ZIP64 is unsupported")
  }
  guard count <= budget.entries else {
    @failure.reject("limit-exceeded", "Entry count budget exceeded")
  }
  let central_size = size32(source, end + 12)
  let central_start = size32(source, end + 16)
  guard central_start <= end && central_size == end - central_start else {
    @failure.reject("malformed-package", "Invalid central directory range")
  }
  let index : Map[String, Entry] = Map([])
  let ranges : Array[(Int, Int)] = []
  let mut cursor = central_start
  for _ in 0..<count {
    ignore(span(source, cursor, 46))
    guard u32(source, cursor) == 0x02014b50U else {
      @failure.reject(
        "malformed-package",
        "Invalid central record",
        offset=cursor,
      )
    }
    let flags = u16(source, cursor + 8)
    let compression = u16(source, cursor + 10)
    guard (flags & 0xf7f1) == 0 &&
      (compression == 0 || compression == 8) &&
      u16(source, cursor + 34) == 0 else {
      @failure.reject(
        "unsupported-package",
        "Encrypted ZIP, compression or flags unsupported",
        offset=cursor,
      )
    }
    let crc = u32(source, cursor + 16)
    let compressed = size32(source, cursor + 20)
    let decoded = size32(source, cursor + 24)
    guard compression != 0 || compressed == decoded else {
      @failure.reject(
        "malformed-package",
        "Stored entry sizes differ",
        offset=cursor,
      )
    }
    let name_size = u16(source, cursor + 28)
    let extra_size = u16(source, cursor + 30)
    let record_size = 46 + name_size + extra_size + u16(source, cursor + 32)
    guard record_size <= end - cursor else {
      @failure.reject(
        "malformed-package",
        "Central record exceeds directory",
        offset=cursor,
      )
    }
    let name = @utf8.decode(span(source, cursor + 46, name_size)) catch {
      _ =>
        @failure.reject(
          "malformed-package",
          "Invalid UTF-8 entry name",
          offset=cursor,
        )
    }
    guard !name.is_empty() && !index.contains(name) else {
      @failure.reject(
        "malformed-package",
        "Empty or duplicate entry name",
        part=name,
      )
    }
    if (flags & 0x800) == 0 {
      for ch in name {
        guard ch.to_int() < 128 else {
          @failure.reject(
            "unsupported-package",
            "Non-UTF-8 ZIP names unsupported",
            part=name,
          )
        }
      }
    }
    extra(source, cursor + 46 + name_size, extra_size)
    let local_start = size32(source, cursor + 42)
    ignore(span(source, local_start, 30))
    guard local_start <= central_start - 30 &&
      u32(source, local_start) == 0x04034b50U &&
      u16(source, local_start + 6) == flags &&
      u16(source, local_start + 8) == compression else {
      @failure.reject(
        "malformed-package",
        "Local/central metadata mismatch",
        part=name,
        offset=local_start,
      )
    }
    let local_name_size = u16(source, local_start + 26)
    let local_extra = u16(source, local_start + 28)
    guard span(source, local_start + 30, local_name_size) ==
      span(source, cursor + 46, name_size) else {
      @failure.reject(
        "malformed-package",
        "Local/central name mismatch",
        part=name,
        offset=local_start,
      )
    }
    extra(source, local_start + 30 + local_name_size, local_extra)
    let payload = local_start + 30 + local_name_size + local_extra
    guard payload <= central_start && compressed <= central_start - payload else {
      @failure.reject(
        "malformed-package",
        "Entry overlaps directory",
        part=name,
      )
    }
    let mut local_end = payload + compressed
    if (flags & 8) == 0 {
      guard u32(source, local_start + 14) == crc &&
        size32(source, local_start + 18) == compressed &&
        size32(source, local_start + 22) == decoded else {
        @failure.reject(
          "malformed-package",
          "Local/central sizes or CRC differ",
          part=name,
        )
      }
    } else {
      guard (
          u32(source, local_start + 14) == 0U ||
          u32(source, local_start + 14) == crc
        ) &&
        (
          u32(source, local_start + 18) == 0U ||
          size32(source, local_start + 18) == compressed
        ) &&
        (
          u32(source, local_start + 22) == 0U ||
          size32(source, local_start + 22) == decoded
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
      let descriptor = if u32(source, local_end) == crc &&
        u32(source, local_end + 4) == compressed.reinterpret_as_uint() &&
        u32(source, local_end + 8) == decoded.reinterpret_as_uint() {
        local_end
      } else {
        guard local_end <= central_start - 16 &&
          u32(source, local_end) == 0x08074b50U else {
          @failure.reject(
            "malformed-package",
            "Invalid data descriptor",
            part=name,
          )
        }
        local_end + 4
      }
      guard u32(source, descriptor) == crc &&
        u32(source, descriptor + 4) == compressed.reinterpret_as_uint() &&
        u32(source, descriptor + 8) == decoded.reinterpret_as_uint() else {
        @failure.reject(
          "malformed-package",
          "Invalid data descriptor",
          part=name,
        )
      }
      local_end = descriptor + 12
      guard local_end <= central_start else {
        @failure.reject(
          "malformed-package",
          "Descriptor overlaps directory",
          part=name,
        )
      }
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
      central: cursor,
      central_size: record_size,
    }
    cursor += record_size
  }
  guard cursor == end else {
    @failure.reject("malformed-package", "Directory size/count mismatch")
  }
  ranges.sort_by((a, b) => a.0.compare(b.0))
  for i in 1..<ranges.length() {
    guard ranges[i].0 >= ranges[i - 1].1 else {
      @failure.reject("malformed-package", "Overlapping ZIP entries")
    }
  }
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
  guard entry.decoded <= ceiling else {
    @failure.reject(
      "limit-exceeded",
      "Entry or cumulative decode budget exceeded",
      part=name,
    )
  }
  let payload = span(self.source, entry.payload, entry.compressed)
  let decoded = if entry.compression == 0 {
    payload.to_owned()
  } else {
    @flate.inflate_all_limited(payload.to_owned(), max_output=ceiling) catch {
      @flate.InflateError(kind, message) =>
        @failure.reject(
          if kind == @flate.OutputLimitExceeded {
            "limit-exceeded"
          } else {
            "malformed-package"
          },
          message,
          part=name,
        )
    }
  }
  guard decoded.length() == entry.decoded &&
    @checksum.crc32(decoded) == entry.crc else {
    @failure.reject(
      "malformed-package",
      "Entry size or CRC mismatch",
      part=name,
    )
  }
  self.inflated += decoded.length()
  self.cache[name] = decoded
  decoded
}

///|
pub fn Package::decoded_bytes(self : Package) -> Int raise @failure.Failure {
  self.check()
  self.inflated
}

///|
pub fn Package::close(self : Package) -> Unit {
  self.closed = true
  self.source = b""
  self.index.clear()
  self.cache.clear()
}
