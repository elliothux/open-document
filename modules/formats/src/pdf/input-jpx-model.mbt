///|
priv struct JpxReader {
  bytes : Bytes
  mut offset : Int32
  end : Int32
}

///|
fn JpxReader::word(self : JpxReader, count~ : Int32 = 2) -> Int32 raise {
  guard count <= self.end - self.offset else {
    @failure.reject("invalid-pdf", "Truncated JPEG2000 data")
  }
  let mut value = 0L
  for _ in 0..<count {
    value = value * 256 + self.bytes[self.offset].to_int64()
    self.offset += 1
  }
  guard value <= 2147483647L else {
    @failure.reject("limit-exceeded", "JPEG2000 integer exceeds budget")
  }
  value.to_int()
}

///|
fn JpxReader::section(self : JpxReader) -> JpxReader raise {
  let size = self.word() - 2
  guard size >= 0 && size <= self.end - self.offset else {
    @failure.reject("invalid-pdf", "Invalid JPEG2000 marker length")
  }
  let offset = self.offset
  self.offset += size
  { bytes: self.bytes, offset, end: offset + size, }
}

///|
priv struct JpxContainer {
  bytes : Bytes
  width : Int32?
  height : Int32?
  channels : Int32?
  color : Int32?
  alpha : Int32?
  associated : Bool
}

///|
priv struct JpxComponent {
  precision : Int32
  signed : Bool
  dx : Int32
  dy : Int32
}

///|
priv struct JpxCoding {
  levels : Int32
  blockWidth : Int32
  blockHeight : Int32
  style : Int32
  reversible : Bool
}

///|
priv struct JpxQuant {
  style : Int32
  guardBits : Int32
  steps : Array[(Int32, Int32)]
}

///|
priv struct JpxHeader {
  x0 : Int32
  y0 : Int32
  x1 : Int32
  y1 : Int32
  tileX : Int32
  tileY : Int32
  tileWidth : Int32
  tileHeight : Int32
  components : Array[JpxComponent]
  coding : Array[JpxCoding]
  quant : Array[JpxQuant]
  mut layers : Int32
  mut progression : Int32
  mut mct : Bool
  mut packetFlags : Int32
}

///|
priv struct JpxBlock {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  mut included : Bool
  mut zeroBits : Int32
  mut passes : Int32
  mut lengthBits : Int32
  data : Array[Byte]
}

///|
priv struct JpxTree {
  widths : Array[Int32]
  nodes : Array[Array[(Int32, Bool)]]
}

///|
priv struct JpxBand {
  x0 : Int32
  y0 : Int32
  width : Int32
  height : Int32
  orientation : Int32
  resolution : Int32
  blocks : Array[JpxBlock]
  inclusion : JpxTree
  zeros : JpxTree
}

///|
priv struct JpxTile {
  x0 : Int32
  y0 : Int32
  x1 : Int32
  y1 : Int32
  header : JpxHeader
  bands : Array[Array[JpxBand]]
  mut packet : Int32
  mut parts : Int32
  mut expectedParts : Int32
}

///|
priv struct JpxPixels {
  width : Int32
  height : Int32
  components : Array[JpxComponent]
  samples : Bytes
  color : Int32?
  alpha : Int32?
  associated : Bool
}

///|
fn jpx_ceil(value : Int32, scale : Int32) -> Int32 {
  value / scale + (if value % scale > 0 { 1 } else { 0 })
}
