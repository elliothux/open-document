///|
priv struct JpxTier1 {
  width : Int32
  height : Int32
  orientation : Int32
  causal : Bool
  values : Array[Int32]
  flags : Array[Int32]
  decoder : ImageArithmetic
}

///|
fn JpxTier1::neighbor(
  self : JpxTier1,
  x : Int32,
  y : Int32,
  dx : Int32,
  dy : Int32,
) -> Int32 {
  let nx = x + dx
  let ny = y + dy
  if nx < 0 ||
    nx >= self.width ||
    ny < 0 ||
    ny >= self.height ||
    (self.causal && y % 4 == 3 && dy > 0) {
    return 0
  }
  let value = self.values[ny * self.width + nx]
  if value == 0 {
    0
  } else if value < 0 {
    -1
  } else {
    1
  }
}

///|
fn JpxTier1::context(self : JpxTier1, x : Int32, y : Int32) -> (Int32, Bool) {
  let horizontal = self.neighbor(x, y, -1, 0).abs() +
    self.neighbor(x, y, 1, 0).abs()
  let vertical = self.neighbor(x, y, 0, -1).abs() +
    self.neighbor(x, y, 0, 1).abs()
  let diagonal = self.neighbor(x, y, -1, -1).abs() +
    self.neighbor(x, y, 1, -1).abs() +
    self.neighbor(x, y, -1, 1).abs() +
    self.neighbor(x, y, 1, 1).abs()
  let h = if self.orientation == 1 { vertical } else { horizontal }
  let v = if self.orientation == 1 { horizontal } else { vertical }
  let context = if self.orientation == 3 {
    let total = h + v
    if diagonal < 2 {
      diagonal * 3 + total.min(2)
    } else if diagonal == 2 {
      if total == 0 {
        6
      } else {
        7
      }
    } else {
      8
    }
  } else if h == 0 {
    if v == 0 {
      diagonal.min(2)
    } else {
      v.min(2) + 2
    }
  } else if h == 1 {
    if v == 0 {
      if diagonal == 0 {
        5
      } else {
        6
      }
    } else {
      7
    }
  } else {
    8
  }
  (context, h + v + diagonal != 0)
}

///|
fn JpxTier1::significant(
  self : JpxTier1,
  x : Int32,
  y : Int32,
  plane : Int32,
) -> Unit {
  let horizontal = (self.neighbor(x, y, -1, 0) + self.neighbor(x, y, 1, 0))
    .max(-1)
    .min(1)
  let vertical = (self.neighbor(x, y, 0, -1) + self.neighbor(x, y, 0, 1))
    .max(-1)
    .min(1)
  let prediction = horizontal < 0 || (horizontal == 0 && vertical < 0)
  let v = if horizontal < 0 { -vertical } else { vertical }
  let context = 9 + (if horizontal == 0 { vertical.abs() } else { 3 + v })
  let negative = self.decoder.bit(context) ^ (if prediction { 1 } else { 0 })
  let value = 3 << plane
  self.values[y * self.width + x] = if negative == 1 { -value } else { value }
}

///|
fn jpx_codeblock(
  block : JpxBlock,
  orientation : Int32,
  bitplanes : Int32,
  style : Int32,
) -> Array[Double] raise {
  let area = block.width * block.height
  @pdfcore.sdk_decoded(area * 12 + 19 * 4)
  if block.passes == 0 {
    return Array::make(area, 0.0)
  }
  guard bitplanes > 0 && bitplanes <= 30 && block.passes <= bitplanes * 3 - 2 else {
    @failure.reject("invalid-pdf", "Invalid JPEG2000 coding pass count")
  }
  let states = Array::make(19, 0)
  states[0] = 8
  states[17] = 6
  states[18] = 92
  let decoder = image_arithmetic(Bytes::from_array(block.data), states)
  let state : JpxTier1 = {
    width: block.width,
    height: block.height,
    orientation,
    causal: (style & 8) != 0,
    values: Array::make(area, 0),
    flags: Array::make(area, 0),
    decoder,
  }
  for pass in 0..<block.passes {
    let plane = bitplanes - 1 - (pass + 2) / 3
    let kind = if pass == 0 { 2 } else { (pass - 1) % 3 }
    let mut stripe = 0
    while stripe < block.height {
      for x in 0..<block.width {
        let mut run = 0
        let mut implicit = false
        if kind == 2 && stripe + 4 <= block.height {
          let mut aggregate = true
          for dy in 0..<4 {
            let y = stripe + dy
            let index = y * block.width + x
            if state.values[index] != 0 ||
              (state.flags[index] & 1) != 0 ||
              state.context(x, y).1 {
              aggregate = false
              break
            }
          }
          if aggregate {
            @pdfcore.sdk_check(1)
            if decoder.bit(17) == 0 {
              continue
            }
            run = (decoder.bit(18) << 1) | decoder.bit(18)
            implicit = true
          }
        }
        for dy in run..<4 {
          let y = stripe + dy
          if y >= block.height {
            break
          }
          @pdfcore.sdk_check(1)
          let index = y * block.width + x
          let visited = (state.flags[index] & 1) != 0
          if kind == 0 {
            if state.values[index] == 0 && !visited {
              let (context, neighbors) = state.context(x, y)
              if neighbors {
                if decoder.bit(context) == 1 {
                  state.significant(x, y, plane)
                }
                state.flags[index] = state.flags[index] | 1
              }
            }
          } else if kind == 1 {
            if state.values[index] != 0 && !visited {
              let context = 14 +
                (if (state.flags[index] & 2) != 0 {
                  2
                } else if state.context(x, y).1 {
                  1
                } else {
                  0
                })
              let delta = if decoder.bit(context) == 1 {
                1 << plane
              } else {
                -(1 << plane)
              }
              state.values[index] += if state.values[index] < 0 {
                -delta
              } else {
                delta
              }
              state.flags[index] = state.flags[index] | 2
            }
          } else {
            if state.values[index] == 0 && !visited {
              if (implicit && dy == run) ||
                decoder.bit(state.context(x, y).0) == 1 {
                state.significant(x, y, plane)
              }
            }
            state.flags[index] = state.flags[index] & 2
          }
        }
      }
      stripe += 4
    }
    if kind == 2 && (style & 32) != 0 {
      let mut symbol = 0
      for _ in 0..<4 {
        symbol = (symbol << 1) | decoder.bit(18)
      }
      guard symbol == 10 else {
        @failure.reject("invalid-pdf", "Invalid JPEG2000 segmentation symbol")
      }
    }
    if (style & 2) != 0 {
      states.fill(0)
      states[0] = 8
      states[17] = 6
      states[18] = 92
    }
  }
  state.values.map(value => value.to_double() / 2.0)
}
