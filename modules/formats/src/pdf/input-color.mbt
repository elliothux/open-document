///|
priv enum InputColorSpace {
  GrayColor
  RgbColor
  CmykColor
  IccColor(IccProfile)
  PatternColor(InputColorSpace?)
}

///|
priv enum IccCurve {
  GammaCurve(Double)
  SampleCurve(Array[Double])
}

///|
priv struct IccProfile {
  matrix : Array[Array[Double]]
  curves : Array[IccCurve]
  srgb : Bool
}

///|
fn icc_word(
  data : Bytes,
  offset : Int32,
  bytes~ : Int32 = 4,
) -> Int64 raise @failure.Failure {
  guard offset >= 0 && offset <= data.length() - bytes else {
    @failure.reject("invalid-pdf", "Truncated ICC profile")
  }
  let mut value = 0L
  for index in offset..<(offset + bytes) {
    value = value * 256 + data[index].to_int64()
  }
  value
}

///|
fn icc_fixed(data : Bytes, offset : Int32) -> Double raise @failure.Failure {
  let value = icc_word(data, offset)
  (if value >= 2147483648L { value - 4294967296L } else { value }).to_double() /
  65536
}

///|
fn IccCurve::apply(self : IccCurve, value : Double) -> Double {
  match self {
    GammaCurve(gamma) => @math.pow(value, gamma)
    SampleCurve(values) => {
      let position = value * (values.length() - 1).to_double()
      let index = position.floor().to_int().min(values.length() - 2)
      values[index] +
      (values[index + 1] - values[index]) * (position - index.to_double())
    }
  }
}

///|
fn icc_curve(data : Bytes, offset : Int32, length : Int32) -> IccCurve raise {
  guard length >= 12 && icc_word(data, offset) == 0x63757276L else {
    @failure.reject(
      "unsupported-pdf", "ICC profile requires supported tone curves",
    )
  }
  let count = icc_word(data, offset + 8)
  guard count <= 4096 && 12L + count * 2 <= length.to_int64() else {
    @failure.reject("invalid-pdf", "Invalid or oversized ICC tone curve")
  }
  @pdfcore.sdk_check(count.to_int())
  if count == 0 {
    return GammaCurve(1)
  }
  if count == 1 {
    let gamma = icc_word(data, offset + 12, bytes=2).to_double() / 256
    guard gamma > 0 && gamma <= 10 else {
      @failure.reject(
        "unsupported-pdf", "ICC gamma is outside supported bounds",
      )
    }
    return GammaCurve(gamma)
  }
  let values = Array::makei(count.to_int(), index => {
    icc_word(data, offset + 12 + index * 2, bytes=2).to_double() / 65535
  })
  guard values
    .mapi((index, value) => index == 0 || value >= values[index - 1])
    .all(value => value) else {
    @failure.reject("invalid-pdf", "ICC tone curves must be monotone")
  }
  SampleCurve(values)
}

///|
fn srgb_linear(value : Double) -> Double {
  if value <= 0.04045 {
    value / 12.92
  } else {
    @math.pow((value + 0.055) / 1.055, 2.4)
  }
}

///|
fn icc_tags(
  data : Bytes,
  signature : Int64,
) -> Map[Int64, (Int32, Int32)] raise {
  guard data.length() >= 132 && data.length() <= 1048576 else {
    @failure.reject("limit-exceeded", "ICC profile size exceeds bounds")
  }
  guard icc_word(data, 0) == data.length().to_int64() &&
    icc_word(data, 36) == 0x61637370L &&
    [2, 4].contains(data[8].to_int()) &&
    icc_word(data, 16) == signature &&
    icc_word(data, 20) == 0x58595a20L else {
    @failure.reject(
      "unsupported-pdf", "ICC profile requires matching matrix/XYZ data",
    )
  }
  let count = icc_word(data, 128)
  guard count <= 128 && 132L + count * 12 <= data.length().to_int64() else {
    @failure.reject("invalid-pdf", "Invalid ICC tag directory")
  }
  let tags : Map[Int64, (Int32, Int32)] = Map([])
  for index in 0..<count.to_int() {
    let at = 132 + index * 12
    let signature = icc_word(data, at)
    let offset = icc_word(data, at + 4)
    let length = icc_word(data, at + 8)
    guard !tags.contains(signature) &&
      offset >= 132 + count * 12 &&
      offset % 4 == 0 &&
      length >= 8 &&
      offset + length <= data.length().to_int64() else {
      @failure.reject("invalid-pdf", "Invalid ICC tag range or identity")
    }
    guard ![
      0x41324230L, 0x41324231L, 0x41324232L, 0x44324230L, 0x44324231L, 0x44324232L,
      0x44324233L,
    ].contains(signature) else {
      @failure.reject(
        "unsupported-pdf", "ICC lookup-table profiles are unsupported",
      )
    }
    tags[signature] = (offset.to_int(), length.to_int())
  }
  tags
}

///|
fn icc_gray(data : Bytes) -> IccProfile raise {
  let tags = icc_tags(data, 0x47524159L)
  guard tags.get(0x6b545243L) is Some((at, length)) &&
    tags.get(0x77747074L) is Some((white, 20)) &&
    icc_word(data, white) == 0x58595a20L else {
    @failure.reject(
      "unsupported-pdf", "ICC gray curve or white point is missing",
    )
  }
  for i in 0..<3 {
    let value = icc_fixed(data, white + 8 + i * 4)
    guard value > 0 && value <= 4 else {
      @failure.reject("invalid-pdf", "Invalid ICC gray white point")
    }
  }
  // Relative gray uses the PCS D50 axis, as in LittleCMS BuildGrayInputMatrixPipeline.
  {
    matrix: [[0.9642], [1.0], [0.8249]],
    curves: [icc_curve(data, at, length)],
    srgb: false,
  }
}

///|
fn icc_rgb(data : Bytes) -> IccProfile raise {
  let tags = icc_tags(data, 0x52474220L)
  let columns : Array[Array[Double]] = []
  let curves : Array[IccCurve] = []
  for
    (colorant, tone) in [
      (0x7258595aL, 0x72545243L),
      (0x6758595aL, 0x67545243L),
      (0x6258595aL, 0x62545243L),
    ] {
    guard tags.get(colorant) is Some((offset, 20)) &&
      icc_word(data, offset) == 0x58595a20L &&
      tags.get(tone) is Some((curve_offset, length)) else {
      @failure.reject("unsupported-pdf", "ICC matrix or tone curve is missing")
    }
    let xyz = Array::makei(3, index => icc_fixed(data, offset + 8 + index * 4))
    guard xyz.all(value => value.abs() <= 4) else {
      @failure.reject("unsupported-pdf", "ICC matrix exceeds supported bounds")
    }
    columns.push(xyz)
    curves.push(icc_curve(data, curve_offset, length))
  }
  // Matrix/TRC quantization may vary; blend-space identity requires actual sRGB colorants and curves.
  let standard = [
    [0.4360747, 0.2225045, 0.0139322],
    [0.3850649, 0.7168786, 0.0971045],
    [0.1430804, 0.0606169, 0.7141733],
  ]
  let srgb = columns
    .mapi((column, values) => {
      values
      .mapi((row, value) => (value - standard[column][row]).abs() <= 0.0002)
      .all(value => value) &&
      (match curves[column] {
        SampleCurve(samples) =>
          samples.length() >= 256 &&
          samples
          .mapi((index, value) => {
            (value -
            srgb_linear(index.to_double() / (samples.length() - 1).to_double())).abs() <=
            4.0 / 65535
          })
          .all(value => value)
        _ => false
      })
    })
    .all(value => value)
  {
    matrix: Array::makei(3, row => columns.map(column => column[row])),
    curves,
    srgb,
  }
}

///|
fn InputColorSpace::components(self : InputColorSpace) -> Int32 {
  match self {
    GrayColor => 1
    CmykColor => 4
    IccColor(profile) => profile.curves.length()
    PatternColor(base) => base.map(space => space.components()).unwrap_or(0)
    _ => 3
  }
}

///|
fn InputColorSpace::initial_color(
  self : InputColorSpace,
) -> String raise @failure.Failure {
  if self is PatternColor(_) {
    return ""
  }
  self.color(
    if self is CmykColor {
      [0, 0, 0, 1]
    } else {
      Array::make(self.components(), 0)
    },
  )
}

///|
fn InputColorSpace::srgb_blending(self : InputColorSpace) -> Bool {
  match self {
    RgbColor => true
    IccColor(profile) => profile.srgb
    _ => false
  }
}

///|
fn InputColorSpace::color(
  self : InputColorSpace,
  values : Array[Double],
) -> String raise @failure.Failure {
  guard !(self is PatternColor(_)) else {
    @failure.reject("invalid-pdf", "Pattern color requires a pattern name")
  }
  guard values.length() == self.components() &&
    values.all(value => !value.is_nan() && !value.is_inf()) else {
    @failure.reject("invalid-pdf", "Invalid PDF color components")
  }
  if self is CmykColor {
    return rgb(cmyk_rgb(values))
  }
  guard self is IccColor(profile) else {
    // Device colors pass through PDF's 16.16 components before conversion to bytes.
    return rgb(
      values.map(value => {
        (value.max(0).min(1) * 65536).to_int().to_double() / 65536
      }),
    )
  }
  rgb(profile.rgb(values))
}

///|
fn IccProfile::rgb(self : IccProfile, values : Array[Double]) -> Array[Double] {
  let linear = values.mapi((index, value) => {
    self.curves[index].apply(value.max(0).min(1))
  })
  let xyz = self.matrix.map(row => {
    row
    .mapi((i, value) => value * linear[i])
    .fold(init=0.0, (sum, value) => sum + value)
  })
  // Bradford D50 -> D65 and XYZ -> linear sRGB coefficients: W3C CSS Color 4, conversions.js.
  let adapted = [
    0.955473421488075 * xyz[0] -
    0.02309845494876471 * xyz[1] +
    0.06325924320057072 * xyz[2],
    -0.0283697093338637 * xyz[0] +
    1.0099953980813041 * xyz[1] +
    0.021041441191917323 * xyz[2],
    0.012314014864481998 * xyz[0] -
    0.020507649298898964 * xyz[1] +
    1.330365926242124 * xyz[2],
  ]
  let output = [
    12831.0 / 3959 * adapted[0] -
    329.0 / 214 * adapted[1] -
    1974.0 / 3959 * adapted[2],
    -851781.0 / 878810 * adapted[0] +
    1648619.0 / 878810 * adapted[1] +
    36519.0 / 878810 * adapted[2],
    705.0 / 12673 * adapted[0] -
    2585.0 / 12673 * adapted[1] +
    705.0 / 667 * adapted[2],
  ]
  output.map(value => {
    let value = value.max(0).min(1)
    if value <= 0.0031308 {
      value * 12.92
    } else {
      1.055 * @math.pow(value, 1.0 / 2.4) - 0.055
    }
  })
}

///|
fn ContentContext::color_space(
  self : ContentContext,
  resources : @syntax.PdfObject,
  source : @syntax.PdfObject,
  depth~ : Int32 = 0,
) -> InputColorSpace raise {
  guard depth < 8 else {
    @failure.reject("invalid-pdf", "Cyclic or deep PDF color space")
  }
  let document = self.session.document
  let source = resolve(document, source)
  if source is PdfNameObject(name) {
    let name = @utf8.decode_lossy(name.bytes())[1:].to_owned()
    let spaces = get(document, resources, "ColorSpace")
    let replacement = get(
      document,
      spaces,
      if name == "DeviceRGB" {
        "DefaultRGB"
      } else if name == "DeviceGray" {
        "DefaultGray"
      } else if name == "DeviceCMYK" {
        "DefaultCMYK"
      } else {
        name
      },
    )
    if replacement != @syntax.PdfNull {
      return self.color_space(resources, replacement, depth=depth + 1)
    }
    return match name {
      "DeviceRGB" => RgbColor
      "DeviceGray" => GrayColor
      "DeviceCMYK" => CmykColor
      "Pattern" => PatternColor(None)
      _ =>
        @failure.reject(
          "unsupported-pdf",
          "Unsupported PDF color space: " + name,
        )
    }
  }
  if source is PdfArray([kind, ..]) &&
    is_name(resolve(document, kind), "Pattern") {
    return match source {
      PdfArray([_]) => PatternColor(None)
      PdfArray([_, base]) => {
        let base = self.color_space(resources, base, depth=depth + 1)
        guard !(base is PatternColor(_)) else {
          @failure.reject(
            "invalid-pdf", "Pattern base color space cannot be a pattern",
          )
        }
        PatternColor(Some(base))
      }
      _ => @failure.reject("invalid-pdf", "Invalid PDF pattern color space")
    }
  }
  guard source is PdfArray([kind, reference]) &&
    is_name(resolve(document, kind), "ICCBased") &&
    reference is PdfIndirect(id) else {
    @failure.reject(
      "unsupported-pdf", "Unsupported PDF color space declaration",
    )
  }
  if self.colors.get(id) is Some(space) {
    return space
  }
  guard self.colors.length() < 256 else {
    @failure.reject("limit-exceeded", "PDF ICC profile count exceeds budget")
  }
  let profile = resolve(document, reference)
  let components = get(document, profile, "N")
  guard profile is PdfStreamObject(_) &&
    [@syntax.PdfInteger(1), @syntax.PdfInteger(3)].contains(components) else {
    @failure.reject(
      "unsupported-pdf", "ICC profile requires gray or RGB components",
    )
  }
  let range = get(document, profile, "Range")
  guard range == @syntax.PdfNull ||
    (
      range is PdfArray(values) &&
      values.length() == integer(components) * 2 &&
      values
      .mapi((index, value) => {
        number(resolve(document, value)) == (index % 2).to_double()
      })
      .all(value => value)
    ) else {
    @failure.reject(
      "unsupported-pdf", "Nondefault ICC component ranges are unsupported",
    )
  }
  let bytes = stream_bytes(document, reference)
  let space = IccColor(
    if components == @syntax.PdfInteger(1) {
      icc_gray(bytes)
    } else {
      icc_rgb(bytes)
    },
  )
  self.colors[id] = space
  space
}
