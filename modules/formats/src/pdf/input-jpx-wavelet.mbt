///|
fn jpx_inverse_line(
  values : Array[Double],
  origin : Int32,
  reversible : Bool,
) -> Unit raise {
  let length = values.length()
  if length <= 1 {
    if length == 1 && (origin & 1) == 1 {
      values[0] = values[0] / 2.0
    }
    return
  }
  @pdfcore.sdk_check(length * (if reversible { 2 } else { 5 }))
  if !reversible {
    for i in 0..<length {
      values[i] *= if ((i + origin) & 1) == 0 {
        1.230174104914001
      } else {
        1.0 / 1.230174104914001
      }
    }
  }
  let stages = if reversible {
    [(0, 0.0), (1, 0.0)]
  } else {
    [
      (0, 0.443506852043971),
      (1, 0.882911075530934),
      (0, -0.052980118572961),
      (1, -1.586134342059924),
    ]
  }
  for (parity, coefficient) in stages {
    for i in 0..<length {
      if ((i + origin) & 1) != parity {
        continue
      }
      let left = if i == 0 { 1 } else { i - 1 }
      let right = if i == length - 1 { length - 2 } else { i + 1 }
      let sum = values[left] + values[right]
      if reversible {
        if parity == 0 {
          values[i] -= ((sum + 2.0) / 4.0).floor()
        } else {
          values[i] += (sum / 2.0).floor()
        }
      } else {
        values[i] -= coefficient * sum
      }
      guard values[i].abs() <= 1000000000000000.0 else {
        @failure.reject("invalid-pdf", "JPEG2000 wavelet sample exceeds bounds")
      }
    }
  }
}

///|
fn jpx_band_values(
  tile : JpxTile,
  component : Int32,
  band : JpxBand,
  index : Int32,
) -> Array[Double] raise {
  let coding = tile.header.coding[component]
  let quant = tile.header.quant[component]
  let (exponent, mantissa) = quant.step(index, coding.levels)
  guard !coding.reversible || quant.style == 0 else {
    @failure.reject(
      "unsupported-pdf", "Quantized reversible JPEG2000 wavelets are unsupported",
    )
  }
  let gain = (band.orientation & 1) + (band.orientation >> 1)
  let step = (1.0 + mantissa.to_double() / 2048.0) *
    @math.pow(
      2.0,
      (tile.header.components[component].precision + gain - exponent).to_double(),
    )
  @pdfcore.sdk_decoded(band.width * band.height * 8)
  let output = Array::make(band.width * band.height, 0.0)
  for block in band.blocks {
    let values = jpx_codeblock(
      block,
      band.orientation,
      quant.guardBits + exponent - 1 - block.zeroBits,
      coding.style,
    )
    for y in 0..<block.height {
      for x in 0..<block.width {
        let value = values[y * block.width + x]
        output[(y + block.y - band.y0) * band.width + x + block.x - band.x0] = if coding.reversible {
          value.to_int().to_double()
        } else {
          value * step
        }
      }
    }
  }
  output
}

///|
fn jpx_component_values(
  tile : JpxTile,
  component : Int32,
) -> Array[Double] raise {
  let bands = tile.bands[component]
  let info = tile.header.components[component]
  let coding = tile.header.coding[component]
  let x0 = jpx_ceil(tile.x0, info.dx)
  let y0 = jpx_ceil(tile.y0, info.dy)
  let x1 = jpx_ceil(tile.x1, info.dx)
  let y1 = jpx_ceil(tile.y1, info.dy)
  let mut previous = jpx_band_values(tile, component, bands[0], 0)
  let mut previousWidth = bands[0].width
  let mut previousX = bands[0].x0
  let mut previousY = bands[0].y0
  for resolution in 1..<=coding.levels {
    let shift = coding.levels - resolution
    let left = jpx_ceil(x0, 1 << shift)
    let top = jpx_ceil(y0, 1 << shift)
    let width = jpx_ceil(x1, 1 << shift) - left
    let height = jpx_ceil(y1, 1 << shift) - top
    @pdfcore.sdk_decoded(width * height * 8 + (width + height) * 8)
    let high = Array::makei(3, o => {
      jpx_band_values(
        tile,
        component,
        bands[1 + (resolution - 1) * 3 + o],
        1 + (resolution - 1) * 3 + o,
      )
    })
    let output = Array::make(width * height, 0.0)
    for y in 0..<height {
      for x in 0..<width {
        let gx = x + left
        let gy = y + top
        let orientation = (gx & 1) + ((gy & 1) << 1)
        if orientation == 0 {
          output[y * width + x] = previous[(gy / 2 - previousY) * previousWidth +
            gx / 2 -
            previousX]
        } else {
          let band = bands[(resolution - 1) * 3 + orientation]
          output[y * width + x] = high[orientation - 1][(gy / 2 - band.y0) *
            band.width +
            gx / 2 -
            band.x0]
        }
      }
    }
    for y in 0..<height {
      let row = Array::makei(width, x => output[y * width + x])
      jpx_inverse_line(row, left, coding.reversible)
      for x in 0..<width {
        output[y * width + x] = row[x]
      }
    }
    for x in 0..<width {
      let column = Array::makei(height, y => output[y * width + x])
      jpx_inverse_line(column, top, coding.reversible)
      for y in 0..<height {
        output[y * width + x] = column[y]
      }
    }
    previous = output
    previousWidth = width
    previousX = left
    previousY = top
  }
  previous
}
