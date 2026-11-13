///|
const IccQuantizationBins : Int32 = 4096

///|
const IccRecentColors : Int32 = 4096

///|
priv struct IccRgbTable {
  contributions : Array[(Double, Double, Double)]
  channels : Array[FixedArray[(Double, Double, Double, Double)?]]
  thresholds : FixedArray[Double]
  bins : FixedArray[Byte]
  recent_keys : FixedArray[Int32]
  recent_colors : FixedArray[Int32]
}

///|
fn IccRgbTable::new(profile : IccProfile) -> IccRgbTable raise {
  @pdfcore.sdk_decoded(
    3 * 256 * 40 + 255 * 8 + IccQuantizationBins + IccRecentColors * 8,
  )
  @pdfcore.sdk_check(255 * 16 + IccQuantizationBins)
  let thresholds = FixedArray::makei(255, index => {
    srgb_linear((index.to_double() + 0.5) / 255)
  })
  let mut boundary = 0
  let bins = FixedArray::makei(IccQuantizationBins, index => {
    let lower = index.to_double() / IccQuantizationBins.to_double()
    while boundary < 255 && thresholds[boundary] <= lower {
      boundary += 1
    }
    boundary.to_byte()
  })
  {
    contributions: [
      profile.linear_srgb(1, 0, 0),
      profile.linear_srgb(0, 1, 0),
      profile.linear_srgb(0, 0, 1),
    ],
    channels: Array::makei(3, _ => FixedArray::make(256, None)),
    thresholds,
    bins,
    recent_keys: FixedArray::make(IccRecentColors, -1),
    recent_colors: FixedArray::make(IccRecentColors, 0),
  }
}

///|
fn IccRgbTable::sample(
  self : IccRgbTable,
  profile : IccProfile,
  channel : Int32,
  byte : Byte,
) -> (Double, Double, Double, Double) raise {
  let index = byte.to_int()
  let table = self.channels[channel]
  if table[index] is Some(sample) {
    return sample
  }
  @pdfcore.sdk_check(16)
  let linear = profile.curves[channel].apply(index.to_double() / 255)
  let (r, g, b) = self.contributions[channel]
  let sample = (linear, r * linear, g * linear, b * linear)
  table[index] = Some(sample)
  sample
}

///|
fn IccRgbTable::quantize(self : IccRgbTable, value : Double) -> (Int32, Bool) {
  let value = value.max(0).min(1)
  let index = (value * IccQuantizationBins.to_double())
    .to_int()
    .min(IccQuantizationBins - 1)
  let base = self.bins[index].to_int()
  let lower = self.thresholds[(base - 1).max(0)]
  let upper = self.thresholds[base.min(254)]
  // Even the narrowest sRGB byte interval is wider than a bin.
  let byte = if base < 255 && value >= upper { base + 1 } else { base }
  (byte, (value - lower).abs() < 1.0e-12 || (value - upper).abs() < 1.0e-12)
}

///|
fn pack_icc_rgb(color : Array[Double]) -> Int32 {
  (color[0] * 255).round().to_int() |
  ((color[1] * 255).round().to_int() << 8) |
  ((color[2] * 255).round().to_int() << 16)
}

///|
fn IccRgbTable::rgb(
  self : IccRgbTable,
  profile : IccProfile,
  rgba : Bytes,
  index : Int32,
) -> Int32 raise {
  let (red, rr, rg, rb) = self.sample(profile, 0, rgba[index])
  let (green, gr, gg, gb) = self.sample(profile, 1, rgba[index + 1])
  let (blue, br, bg, bb) = self.sample(profile, 2, rgba[index + 2])
  let (r, r_edge) = self.quantize(rr + gr + br)
  let (g, g_edge) = self.quantize(rg + gg + bg)
  let (b, b_edge) = self.quantize(rb + gb + bb)
  if r_edge || g_edge || b_edge {
    // Use the original operation order on quantization boundaries.
    @pdfcore.sdk_check(48)
    return pack_icc_rgb(profile.rgb_from_linear(red, green, blue))
  }
  r | (g << 8) | (b << 16)
}

///|
fn IccRgbTable::recent(
  self : IccRgbTable,
  profile : IccProfile,
  rgba : Bytes,
  index : Int32,
  key : Int32,
) -> Int32 raise {
  let slot = ((key ^ (key >> 12)) * 0x9e3779b9U.reinterpret_as_int()) &
    (IccRecentColors - 1)
  if self.recent_keys[slot] == key {
    return self.recent_colors[slot]
  }
  let color = self.rgb(profile, rgba, index)
  self.recent_keys[slot] = key
  self.recent_colors[slot] = color
  color
}

///|
fn icc_rgba(rgba : Bytes, profile : IccProfile?) -> Bytes raise {
  guard profile is Some(profile) else { return rgba }
  // Reserve the table lookup and quantization work for every pixel up front.
  @pdfcore.sdk_check(rgba.length() / 4)
  @pdfcore.sdk_decoded(rgba.length())
  let channels = profile.curves.length()
  let mut table : IccRgbTable? = None
  let mut color = 0
  let cache : Map[Int32, Int32] = Map([])
  Bytes::makei(rgba.length(), i => {
    let channel = i % 4
    if channel == 3 {
      return rgba[i]
    }
    if channel == 0 {
      let key = if channels == 3 {
        rgba[i].to_int() |
        (rgba[i + 1].to_int() << 8) |
        (rgba[i + 2].to_int() << 16)
      } else {
        rgba[i].to_int()
      }
      color = match cache.get(key) {
        Some(value) => value
        None => {
          if channels == 3 && cache.length() == 256 && table is None {
            table = Some(IccRgbTable::new(profile))
          }
          let value = if table is Some(table) {
            table.recent(profile, rgba, i, key)
          } else {
            @pdfcore.sdk_check(96)
            pack_icc_rgb(
              profile.rgb(
                Array::makei(channels, c => {
                  rgba[i + c].to_int().to_double() / 255
                }),
              ),
            )
          }
          if cache.length() < 256 {
            @pdfcore.sdk_decoded(32)
            cache[key] = value
          }
          value
        }
      }
    }
    (color >> (channel * 8)).to_byte()
  })
}
