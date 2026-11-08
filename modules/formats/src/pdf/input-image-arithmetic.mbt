///|
priv struct ImageArithmetic {
  bytes : Bytes
  states : Array[Int32]
  mut offset : Int32
  mut interval : UInt32
  mut code : UInt32
  mut remaining : Int32
}

///|
let image_probability : Array[UInt32] = [
  0x5601, 0x3401, 0x1801, 0x0ac1, 0x0521, 0x0221, 0x5601, 0x5401, 0x4801, 0x3801,
  0x3001, 0x2401, 0x1c01, 0x1601, 0x5601, 0x5401, 0x5101, 0x4801, 0x3801, 0x3401,
  0x3001, 0x2801, 0x2401, 0x2201, 0x1c01, 0x1801, 0x1601, 0x1401, 0x1201, 0x1101,
  0x0ac1, 0x09c1, 0x08a1, 0x0521, 0x0441, 0x02a1, 0x0221, 0x0141, 0x0111, 0x0085,
  0x0049, 0x0025, 0x0015, 0x0009, 0x0005, 0x0001, 0x5601,
]

///|
let image_mps : Array[Int32] = [
  1, 2, 3, 4, 5, 38, 7, 8, 9, 10, 11, 12, 13, 29, 15, 16, 17, 18, 19, 20, 21, 22,
  23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
  43, 44, 45, 45, 46,
]

///|
let image_lps : Array[Int32] = [
  1, 6, 9, 12, 29, 33, 6, 14, 14, 14, 17, 18, 20, 21, 14, 14, 15, 16, 17, 18, 19,
  19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
  39, 40, 41, 42, 43, 46,
]

///|
fn ImageArithmetic::refill(self : ImageArithmetic) -> Unit {
  let current = self.bytes[self.offset].to_int()
  let next = self.bytes[self.offset + 1].to_int()
  if current == 255 && next > 143 {
    self.remaining = 8
  } else {
    self.offset += 1
    self.code += if current == 255 {
      0xfe00U - (next.reinterpret_as_uint() << 9)
    } else {
      0xff00U - (next.reinterpret_as_uint() << 8)
    }
    self.remaining = if current == 255 { 7 } else { 8 }
  }
}

///|
fn ImageArithmetic::bit(self : ImageArithmetic, context : Int32) -> Int32 {
  let state = self.states[context]
  let index = state >> 1
  let mps = state & 1
  let probability = image_probability[index] << 16
  self.interval -= probability
  let lower = self.code < self.interval
  if lower && (self.interval & 0x80000000U) != 0 {
    return mps
  }
  let lps = if lower {
    self.interval < probability
  } else {
    self.code -= self.interval
    self.interval >= probability
  }
  self.states[context] = if lps {
    (image_lps[index] << 1) |
    (mps ^ (if index == 0 || index == 6 || index == 14 { 1 } else { 0 }))
  } else {
    (image_mps[index] << 1) | mps
  }
  if !lower {
    self.interval = probability
  }
  while (self.interval & 0x80000000U) == 0 {
    if self.remaining == 0 {
      self.refill()
    }
    self.interval = self.interval << 1
    self.code = self.code << 1
    self.remaining -= 1
  }
  mps ^ (if lps { 1 } else { 0 })
}

///|
fn image_arithmetic(
  bytes : Bytes,
  states : Array[Int32],
) -> ImageArithmetic raise {
  guard !bytes.is_empty() else {
    @failure.reject("invalid-pdf", "Empty image arithmetic segment")
  }
  @pdfcore.sdk_decoded(bytes.length() + 2)
  let padded = Bytes::makei(bytes.length() + 2, i => {
    if i < bytes.length() {
      bytes[i]
    } else {
      255
    }
  })
  let decoder : ImageArithmetic = {
    bytes: padded,
    states,
    offset: 0,
    interval: 0x80000000U,
    code: (bytes[0].to_uint() ^ 255U) << 16,
    remaining: 0,
  }
  decoder.refill()
  decoder.code = decoder.code << 7
  decoder.remaining -= 7
  decoder
}
