///|
priv struct FlateImage {
  source : @syntax.PdfObject
  width : Int32
  height : Int32
  channels : Int32
  preview : (Int32, Int32)?
  decode : Array[Double]
  mask : (@syntax.PdfObject, Array[Double])?
  matte : Array[Double]?
  profile : IccProfile?
}

///|
fn is_plain_flate(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Bool raise @failure.Failure {
  guard object is PdfStreamObject(_) else { return false }
  let filter = match get(document, object, "Filter") {
    PdfArray([value]) => resolve(document, value)
    value => value
  }
  guard is_name(filter, "FlateDecode") || is_name(filter, "Fl") else {
    return false
  }
  let parameters = match get(document, object, "DecodeParms") {
    PdfArray([value]) => resolve(document, value)
    value => value
  }
  guard parameters == @syntax.PdfNull || parameters is PdfDictionary(_) else {
    return false
  }
  let predictor = get(document, parameters, "Predictor")
  predictor == @syntax.PdfNull || predictor == @syntax.PdfInteger(1)
}

///|
priv struct FlateRows {
  input : Bytes
  decoder : @zlib.Decoder
  mut offset : Int32
}

///|
fn FlateRows::new(source : @syntax.PdfObject) -> FlateRows raise {
  { input: source.stream_bytes(), decoder: @zlib.Decoder(), offset: 0, }
}

///|
fn FlateRows::step(
  self : FlateRows,
  output : MutArrayView[Byte],
) -> Int32 raise {
  let status = self.decoder.step(self.input[self.offset:], output, end=true) catch {
    @zlib.ZlibError(_, _) =>
      @failure.reject("invalid-pdf", "Invalid Flate image stream")
  }
  let read = self.decoder.last_consumed()
  let written = self.decoder.last_produced()
  self.offset += read
  guard read > 0 || written > 0 || status is @deflate.Done else {
    @failure.reject("invalid-pdf", "Incomplete Flate image stream")
  }
  @pdfcore.sdk_check(written / 16 + 1)
  written
}

///|
fn FlateRows::row(self : FlateRows, output : MutArrayView[Byte]) -> Unit raise {
  for offset = 0; offset < output.length(); {
    let size = self.step(output.mut_view(start=offset))
    guard size > 0 || !self.decoder.is_finished() else {
      @failure.reject("invalid-pdf", "Flate image has too few samples")
    }
    continue offset + size
  }
}

///|
fn FlateRows::finish(self : FlateRows) -> Unit raise {
  let extra = FixedArray::make(1, b'\x00')
  while !self.decoder.is_finished() {
    guard self.step(extra.mut_view()) == 0 else {
      @failure.reject("invalid-pdf", "Flate image has too many samples")
    }
  }
}

///|
fn image_sample(
  position : Int32,
  size : Int32,
  target : Int32,
) -> (Int32, Int32, Double) {
  let center = ((position.to_double() + 0.5) *
  size.to_double() /
  target.to_double() -
  0.5).max(0)
  let first = center.floor().to_int()
  let fraction = center - first.to_double()
  (
    first,
    if fraction == 0 {
      first
    } else {
      (first + 1).min(size - 1)
    },
    fraction,
  )
}

///|
fn FlateImage::raster(
  self : FlateImage,
  width : Int32,
  height : Int32,
) -> Bytes raise {
  let color = FlateRows::new(self.source)
  let mask = self.mask.map(pair => FlateRows::new(pair.0))
  let mask_decode = self.mask.map(pair => pair.1)
  let channels = self.channels
  let stride = self.width * channels
  let mask_stride = if mask is Some(_) { self.width } else { 0 }
  @pdfcore.sdk_decoded((stride + mask_stride) * 2 + (width + height) * 24)
  @pdfcore.sdk_decoded(width * height * 4)
  @pdfcore.sdk_check(width * height)
  let x_samples = Array::makei(width, i => image_sample(i, self.width, width))
  let y_samples = Array::makei(height, i => image_sample(i, self.height, height))
  let mut top = FixedArray::make(stride + mask_stride, b'\x00')
  let mut bottom = FixedArray::make(stride + mask_stride, b'\x00')
  let rgba = FixedArray::make(width * height * 4, b'\x00')
  let opacity = (row : FixedArray[Byte], x) => {
    match mask_decode {
      Some(values) => decoded_sample(row[stride + x], values[0], values[1])
      None => b'\xff'
    }
  }
  let component = (row : FixedArray[Byte], x, channel, alpha) => {
    let channel = if channels == 1 { 0 } else { channel }
    let value = decoded_sample(
      row[x * channels + channel],
      self.decode[channel * 2],
      self.decode[channel * 2 + 1],
    )
    match self.matte {
      Some(values) if mask is Some(_) =>
        unblend_sample(value, alpha, values[channel])
      _ => value
    }
  }
  let mut target_y = 0
  for y in 0..<self.height {
    let previous = top
    top = bottom
    bottom = previous
    color.row(bottom.mut_view(end=stride))
    if mask is Some(mask) {
      mask.row(bottom.mut_view(start=stride))
    }
    if target_y >= height || y_samples[target_y].1 != y {
      continue
    }
    let (y0, _, dy) = y_samples[target_y]
    let upper = if y0 == y { bottom } else { top }
    for x, (x0, x1, dx) in x_samples {
      let at = (target_y * width + x) * 4
      let a = opacity(upper, x0)
      if x0 == x1 && y0 == y {
        for channel in 0..<3 {
          rgba[at + channel] = component(upper, x0, channel, a)
        }
        rgba[at + 3] = a
        continue
      }
      // Interpolate premultiplied samples so transparent edges do not bleed.
      let b = opacity(upper, x1)
      let c = opacity(bottom, x0)
      let d = opacity(bottom, x1)
      let wa = (1.0 - dx) * (1.0 - dy) * a.to_int().to_double()
      let wb = dx * (1.0 - dy) * b.to_int().to_double()
      let wc = (1.0 - dx) * dy * c.to_int().to_double()
      let wd = dx * dy * d.to_int().to_double()
      let alpha = wa + wb + wc + wd
      rgba[at + 3] = alpha.round().to_int().min(255).to_byte()
      if alpha > 0 {
        for channel in 0..<3 {
          let value = wa * component(upper, x0, channel, a).to_int().to_double() +
            wb * component(upper, x1, channel, b).to_int().to_double() +
            wc * component(bottom, x0, channel, c).to_int().to_double() +
            wd * component(bottom, x1, channel, d).to_int().to_double()
          rgba[at + channel] = (value / alpha)
            .round()
            .to_int()
            .min(255)
            .to_byte()
        }
      }
    }
    target_y += 1
  }
  color.finish()
  if mask is Some(mask) {
    mask.finish()
  }
  icc_rgba(Bytes::from_array(rgba), self.profile)
}
