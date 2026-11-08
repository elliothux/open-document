///|
priv struct CompoundStorage {
  data : Bytes
  fat : Bytes
  block : Int32
  base : Int32
  used : Set[Int32]
}

///|
fn compound_id(data : Bytes, offset : Int32) -> Int32 raise @failure.Failure {
  u32(data, offset).reinterpret_as_int()
}

///|
fn CompoundStorage::read(
  self : CompoundStorage,
  start : Int32,
  size? : Int32,
) -> Bytes raise @failure.Failure {
  let out = Buffer(size_hint=size.unwrap_or(0))
  let capacity = (self.data.length() - self.base) / self.block
  for sector = start; sector != -2; {
    guard sector >= 0 &&
      sector < capacity &&
      !self.used.contains(sector) &&
      size.unwrap_or(self.data.length()) > out.length() else {
      @failure.reject("malformed-package", "Invalid compound sector chain")
    }
    self.used.add(sector)
    let offset = self.base + sector * self.block
    let length = size
      .map(n => (n - out.length()).min(self.block))
      .unwrap_or(self.block)
    out.write_bytes(self.data[offset:offset + length])
    continue compound_id(self.fat, sector * 4)
  }
  guard size is None || size == Some(out.length()) else {
    @failure.reject("malformed-package", "Truncated compound sector chain")
  }
  out.to_bytes()
}

///|
fn compound_storage(data : Bytes) -> CompoundStorage raise @failure.Failure {
  let version = u16(data, 26)
  let shift = u16(data, 30)
  guard (version == 3 && shift == 9) || (version == 4 && shift == 12) else {
    @failure.reject("unsupported-package", "Unsupported compound sector format")
  }
  let block = 1 << shift
  let sectors = data.length() / block - 1
  guard sectors >= 2 &&
    data.length() % block == 0 &&
    u16(data, 28) == 0xfffe &&
    u16(data, 32) == 6 &&
    u32(data, 56) == 4096U else {
    @failure.reject("malformed-package", "Invalid compound file header")
  }
  let fat_count = compound_id(data, 44)
  let difat_count = compound_id(data, 72)
  guard fat_count > 0 &&
    fat_count <= sectors &&
    difat_count >= 0 &&
    difat_count <= sectors - fat_count &&
    fat_count >= (sectors - 1) / (block / 4) + 1 else {
    @failure.reject("malformed-package", "Invalid compound allocation tables")
  }
  let fat = Buffer(size_hint=fat_count * block)
  let used : Set[Int32] = Set([])
  let allocation : Array[(Int32, Int32)] = []
  let add_fat = fn(sector : Int32) raise @failure.Failure {
    if sector == -1 {
      return
    }
    guard sector >= 0 &&
      sector < sectors &&
      !used.contains(sector) &&
      fat.length() / block < fat_count else {
      @failure.reject("malformed-package", "Invalid compound FAT sector")
    }
    used.add(sector)
    allocation.push((sector, -3))
    let offset = (sector + 1) * block
    fat.write_bytes(data[offset:offset + block])
  }
  for slot in 0..<109 {
    add_fat(compound_id(data, 76 + slot * 4))
  }
  let mut difat = compound_id(data, 68)
  for _ in 0..<difat_count {
    guard difat >= 0 && difat < sectors && !used.contains(difat) else {
      @failure.reject("malformed-package", "Invalid compound DIFAT sector")
    }
    used.add(difat)
    allocation.push((difat, -4))
    let offset = (difat + 1) * block
    for slot in 0..<(block / 4 - 1) {
      add_fat(compound_id(data, offset + slot * 4))
    }
    difat = compound_id(data, offset + block - 4)
  }
  guard fat.length() / block == fat_count && difat == -2 else {
    @failure.reject("malformed-package", "Truncated compound allocation tables")
  }
  let fat = fat.to_bytes()
  for entry in allocation {
    guard compound_id(fat, entry.0 * 4) == entry.1 else {
      @failure.reject(
        "malformed-package", "Compound allocation sector is reused",
      )
    }
  }
  { data, fat, block, base: block, used, }
}

///|
fn compound_stream_size(
  directory : Bytes,
  entry : Int32,
  maximum : Int32,
) -> Int32 raise @failure.Failure {
  let low = compound_id(directory, entry + 120)
  guard u32(directory, entry + 124) == 0 && low >= 0 && low <= maximum else {
    @failure.reject("malformed-package", "Invalid compound stream size")
  }
  low
}

///|
fn compound_stream_name(
  directory : Bytes,
  offset : Int32,
  name : Bytes,
) -> Bool raise @failure.Failure {
  let count = name.length()
  if u16(directory, offset + 64) != (count + 1) * 2 ||
    u16(directory, offset + count * 2) != 0 {
    return false
  }
  for index in 0..<count {
    if u16(directory, offset + index * 2) != name[index].to_int() {
      return false
    }
  }
  true
}

///|
/// Read the two root streams of an encrypted Office package within the input budget.
pub fn encrypted_office_streams(
  data : Bytes,
  budget : Budget,
) -> (Bytes, Bytes)? raise @failure.Failure {
  if data.length() < 8 || data[:8] != b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" {
    return None
  }
  guard data.length() <= budget.file_bytes &&
    data.length() <= budget.retained_bytes else {
    @failure.reject(
      "limit-exceeded", "Package or retained source budget exceeded",
    )
  }
  let storage = compound_storage(data)
  let directory = storage.read(compound_id(data, 48))
  guard directory.length() >= 128 && directory[66] == 5 else {
    @failure.reject("malformed-package", "Missing compound root directory")
  }
  let mut info = -1
  let mut payload = -1
  let seen : Set[Int32] = Set([])
  let pending = [compound_id(directory, 76)]
  while pending.pop() is Some(id) {
    if id == -1 {
      continue
    }
    guard id > 0 && id < directory.length() / 128 && !seen.contains(id) else {
      @failure.reject("malformed-package", "Invalid compound directory tree")
    }
    guard seen.length() < budget.entries else {
      @failure.reject(
        "limit-exceeded", "Compound directory entry budget exceeded",
      )
    }
    seen.add(id)
    let offset = id * 128
    pending.push(compound_id(directory, offset + 68))
    pending.push(compound_id(directory, offset + 72))
    if directory[offset + 66] != 2 {
      continue
    }
    if compound_stream_name(directory, offset, b"EncryptionInfo") {
      guard info < 0 else {
        @failure.reject("malformed-package", "Duplicate EncryptionInfo stream")
      }
      info = offset
    } else if compound_stream_name(directory, offset, b"EncryptedPackage") {
      guard payload < 0 else {
        @failure.reject(
          "malformed-package", "Duplicate EncryptedPackage stream",
        )
      }
      payload = offset
    }
  }
  if info < 0 && payload < 0 {
    return None
  }
  guard info >= 0 && payload >= 0 else {
    @failure.reject(
      "malformed-package", "Incomplete encrypted Office container",
    )
  }
  let info_size = compound_stream_size(directory, info, data.length())
  let package_size = compound_stream_size(directory, payload, data.length())
  let mini = if info_size < 4096 || package_size < 4096 {
    let count = compound_id(data, 64)
    guard count > 0 && count < data.length() / storage.block else {
      @failure.reject("malformed-package", "Invalid compound mini FAT size")
    }
    let fat = storage.read(compound_id(data, 60), size=count * storage.block)
    let size = compound_stream_size(directory, 0, data.length())
    Some({
      data: storage.read(compound_id(directory, 116), size~),
      fat,
      block: 64,
      base: 0,
      used: Set([]),
    })
  } else {
    None
  }
  let read = fn(entry : Int32, size : Int32) raise @failure.Failure {
    let target = if size < 4096 { mini.unwrap() } else { storage }
    target.read(compound_id(directory, entry + 116), size~)
  }
  Some((read(info, info_size), read(payload, package_size)))
}
