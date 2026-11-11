///|
// Based on IJG jpeg_idct_islow in jidctint.c.
// Copyright (C) 1991-1998, Thomas G. Lane. Modified by Guido Vollbeding.
fn jpeg_idct_pass(
  input : Array[Int64],
  output : Array[Int64],
  offset : Int32,
  stride : Int32,
  shift : Int32,
  bias : Int64,
) -> Unit {
  let c0 = input[offset]
  let c1 = input[offset + stride]
  let c2 = input[offset + 2 * stride]
  let c3 = input[offset + 3 * stride]
  let c4 = input[offset + 4 * stride]
  let c5 = input[offset + 5 * stride]
  let c6 = input[offset + 6 * stride]
  let c7 = input[offset + 7 * stride]
  let even = (c2 + c6) * 4433L
  let e2 = even + c2 * 6270L
  let e3 = even - c6 * 15137L
  let e0 = ((c0 + c4) << 13) + bias
  let e1 = ((c0 - c4) << 13) + bias
  let a = c7 + c3
  let b = c5 + c1
  let odd = (a + b) * 9633L
  let o2 = odd - a * 16069L
  let o3 = odd - b * 3196L
  let outer = -(c7 + c1) * 7373L
  let inner = -(c5 + c3) * 20995L
  let d0 = c1 * 12299L + outer + o3
  let d1 = c3 * 25172L + inner + o2
  let d2 = c5 * 16819L + inner + o3
  let d3 = c7 * 2446L + outer + o2
  output[offset] = (e0 + e2 + d0) >> shift
  output[offset + stride] = (e1 + e3 + d1) >> shift
  output[offset + 2 * stride] = (e1 - e3 + d2) >> shift
  output[offset + 3 * stride] = (e0 - e2 + d3) >> shift
  output[offset + 4 * stride] = (e0 - e2 - d3) >> shift
  output[offset + 5 * stride] = (e1 - e3 - d2) >> shift
  output[offset + 6 * stride] = (e1 + e3 - d1) >> shift
  output[offset + 7 * stride] = (e0 + e2 - d0) >> shift
}

///|
// Match the accurate eight-bit JPEG rounding with wide intermediate values.
fn jpeg_idct(block : Array[Int32]) -> Array[Int32] {
  let coefficients = block.map(value => value.to_int64())
  let workspace = Array::make(64, 0L)
  for column in 0..<8 {
    jpeg_idct_pass(coefficients, workspace, column, 8, 11, 1024L)
  }
  for row in 0..<8 {
    jpeg_idct_pass(workspace, coefficients, row * 8, 1, 18, 131072L)
  }
  coefficients.map(value => (value + 128L).max(0L).min(255L).to_int())
}
